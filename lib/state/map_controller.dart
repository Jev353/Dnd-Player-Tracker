import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../models/json_helpers.dart';
import '../models/map_layer.dart';
import '../models/map_scene.dart';
import '../models/map_token.dart';
import '../services/map_sync_service.dart';

/// Holds the party's map scenes, the active scene, and token permissions.
/// When a real party code is set, state is mirrored through Supabase.
class MapController extends ChangeNotifier {
  MapController({
    MapSyncService? syncService,
    this.dragPushInterval = const Duration(milliseconds: 100),
  }) : _sync = syncService ?? MapSyncService();

  /// Party code used when not connected to a room (never synced).
  static const String localPartyCode = 'LOCAL';

  final MapSyncService _sync;

  /// Minimum gap between pushes while a token is being dragged.
  final Duration dragPushInterval;

  String? partyCode;
  bool isGM = false;
  String? activeSceneId;
  String? syncError;
  final List<MapScene> _scenes = [];

  StreamSubscription<Map<String, dynamic>?>? _sub;
  Timer? _pushTimer;
  bool _receivedFirst = false;
  String? _draggingTokenId;
  final Set<int> _ownPushes = <int>{};

  List<MapScene> get scenes => List.unmodifiable(_scenes);

  /// The token this client is currently dragging, if any.
  String? get draggingTokenId => _draggingTokenId;

  bool get isSynced => partyCode != null && partyCode != localPartyCode;

  /// GM-only: the scene the GM is currently looking at. It is local and
  /// never synced, so browsing maps does not change what players see.
  String? viewedSceneId;

  MapScene? _sceneById(String? id) {
    if (id == null) return null;
    final i = _scenes.indexWhere((s) => s.id == id);
    return i < 0 ? null : _scenes[i];
  }

  /// The scene pushed to the party ([activeSceneId]).
  MapScene? get partyScene => _sceneById(activeSceneId);

  /// The scene this client is looking at, and the one token edits apply to.
  /// Players always see the party scene; the GM sees [viewedSceneId],
  /// falling back to the party scene.
  MapScene? get activeScene =>
      (isGM ? _sceneById(viewedSceneId) : null) ?? partyScene;

  /// Id of the client holding the GM seat for this party (synced parties).
  String? gmId;

  final String _fallbackClientId = newId();

  /// Stable id for this client: the Supabase user id when available.
  String get clientId => _sync.currentUserId ?? _fallbackClientId;

  /// True when someone other than this client holds the GM seat.
  bool get gmTaken => isSynced && gmId != null && gmId != clientId;

  /// Joins [partyCode]. In a synced party the GM seat is exclusive, so
  /// [isGM] is ignored there: call [requestGm] to claim it instead.
  void setPartySession({required String partyCode, required bool isGM}) {
    final changed = this.partyCode != partyCode;
    if (changed) {
      _releaseGmQuietly();
      gmId = null;
    }
    this.partyCode = partyCode;
    if (changed) {
      this.isGM = isSynced ? false : isGM;
      viewedSceneId = null;
      viewedLayerId = null;
      _restartSubscription();
    } else if (!isSynced) {
      this.isGM = isGM;
    }
    notifyListeners();
  }

  /// Tries to become GM. Local (unsynced) sessions always succeed; in a
  /// synced party this fails if another player already holds the seat.
  Future<bool> requestGm() async {
    final code = partyCode;
    if (code == null || !isSynced) {
      isGM = true;
      notifyListeners();
      return true;
    }
    try {
      final ok = await _sync.claimGm(code, clientId);
      if (ok) {
        gmId = clientId;
        isGM = true;
        syncError = null;
      } else {
        // Refreshed from the stream shortly; mark taken in the meantime.
        gmId ??= '?';
      }
      notifyListeners();
      return ok;
    } catch (e) {
      debugPrint('claimGm failed: $e');
      final missingColumn =
          e is PostgrestException &&
          (e.code == '42703' || e.code == 'PGRST204');
      syncError = missingColumn
          ? 'Supabase is missing the gm_id column. Run supabase_party_maps.sql '
                'in the Supabase SQL Editor, then try again.'
          : 'Could not claim GM: $e';
      notifyListeners();
      return false;
    }
  }

  /// Gives up the GM seat so another player can take it.
  Future<void> releaseGm() async {
    final code = partyCode;
    final wasGm = isGM;
    isGM = false;
    viewedSceneId = null;
    viewedLayerId = null;
    if (wasGm && code != null && isSynced) {
      gmId = null;
      await _releaseGm(code);
    }
    notifyListeners();
  }

  Future<void> _releaseGm(String code) async {
    try {
      await _sync.releaseGm(code, clientId);
    } catch (e) {
      debugPrint('releaseGm failed: $e');
    }
  }

  void _releaseGmQuietly() {
    final code = partyCode;
    if (isGM && code != null && isSynced) _releaseGm(code);
  }

  // ---- Sync ----
  void _restartSubscription() {
    _sub?.cancel();
    _sub = null;
    _receivedFirst = false;
    final code = partyCode;
    if (code == null || !isSynced) return;
    try {
      _sub = _sync
          .subscribeToPartyMap(code)
          .listen(
            _applyRemote,
            onError: (Object e) {
              syncError = e.toString();
              notifyListeners();
            },
          );
    } catch (e) {
      syncError = e.toString();
    }
  }

  void _applyRemote(Map<String, dynamic>? row) {
    final first = !_receivedFirst;
    _receivedFirst = true;
    if (row == null) {
      gmId = null;
      // No shared state yet: a GM seeds it with whatever they have locally.
      if (first && isGM && _scenes.isNotEmpty) _pushNow();
      return;
    }
    // GM seat: always honoured, even for our own echoes. If someone else
    // now holds it, step down.
    final gm = row['gm_id'];
    gmId = gm == null ? null : readString(gm, '');
    if (isGM && gmId != null && gmId != clientId) {
      isGM = false;
      viewedSceneId = null;
      viewedLayerId = null;
    }
    // Claiming GM creates an empty row; keep the GM's local scenes then.
    final remoteScenes = readList(row['scenes']);
    if (first && isGM && remoteScenes.isEmpty && _scenes.isNotEmpty) {
      notifyListeners();
      _pushNow();
      return;
    }
    final stamp = DateTime.tryParse(readString(row['updated_at'], ''));
    if (stamp != null &&
        _ownPushes.contains(stamp.toUtc().microsecondsSinceEpoch)) {
      return; // Echo of our own push; local state is already up to date.
    }
    final incoming = readList(
      row['scenes'],
    ).map((s) => MapScene.fromJson(readMap(s))).toList();
    final remoteActive = row['active_scene_id'];
    final remoteActiveId = remoteActive == null
        ? null
        : readString(remoteActive, '');

    final merged = _keepDraggedToken(incoming);
    _scenes
      ..clear()
      ..addAll(merged);
    // Players are locked to the GM's scene; the GM keeps their own view.
    final localStillValid =
        activeSceneId != null && _scenes.any((s) => s.id == activeSceneId);
    if (!isGM || !localStillValid) activeSceneId = remoteActiveId;
    syncError = null;
    notifyListeners();
  }

  /// Replaces the incoming copy of the locally-dragged token with the local
  /// one so remote updates never make it jump under the cursor.
  List<MapScene> _keepDraggedToken(List<MapScene> incoming) {
    final dragId = _draggingTokenId;
    final local = activeScene;
    if (dragId == null || local == null) return incoming;
    final matches = local.tokens.where((t) => t.id == dragId);
    if (matches.isEmpty) return incoming;
    final localToken = matches.first;
    return [
      for (final s in incoming)
        s.id == local.id
            ? s.copyWith(
                tokens: [
                  for (final t in s.tokens) t.id == dragId ? localToken : t,
                ],
              )
            : s,
    ];
  }

  /// Throttled push used while dragging: at most one per [dragPushInterval],
  /// always carrying the latest state.
  void _schedulePush() {
    if (!isSynced) return;
    _pushTimer ??= Timer(dragPushInterval, _pushNow);
  }

  Future<void> _pushNow() async {
    _pushTimer?.cancel();
    _pushTimer = null;
    final code = partyCode;
    if (code == null || !isSynced) return;
    final stamp = DateTime.now().toUtc();
    _ownPushes.add(stamp.microsecondsSinceEpoch);
    if (_ownPushes.length > 64) _ownPushes.remove(_ownPushes.first);
    try {
      await _sync.pushPartyMapState(
        code,
        activeSceneId,
        _scenes,
        updatedAt: stamp,
      );
      if (syncError != null) {
        syncError = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('pushPartyMapState failed: $e');
      syncError = e.toString();
      notifyListeners();
    }
  }

  /// For a local file path in a synced party, uploads it and returns the
  /// public URL so players can render it. Otherwise returns [url] unchanged.
  Future<String> resolveImageUrl(String url) async {
    final trimmed = url.trim();
    final code = partyCode;
    final isRemote =
        trimmed.startsWith('http://') || trimmed.startsWith('https://');
    if (trimmed.isEmpty || isRemote || code == null || !isSynced) return url;
    try {
      return await _sync.uploadMapImage(code, trimmed) ?? url;
    } catch (e) {
      debugPrint('uploadMapImage failed: $e');
      syncError = 'Map image upload failed: $e';
      notifyListeners();
      return url;
    }
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  // ---- Scenes (GM only) ----
  /// Adds a scene and switches the GM's view to it. Players are not moved
  /// until the GM calls [setActiveScene].
  void addScene(MapScene scene) {
    if (!isGM) return;
    _scenes.add(scene);
    viewedLayerId = null;
    viewedSceneId = scene.id;
    notifyListeners();
    _pushNow();
  }

  /// GM only: switch which scene the GM is viewing (local only).
  void viewScene(String sceneId) {
    if (!isGM) return;
    if (!_scenes.any((s) => s.id == sceneId)) return;
    if (viewedSceneId != sceneId) viewedLayerId = null;
    viewedSceneId = sceneId;
    notifyListeners();
  }

  // ---- Layers ----
  /// GM-only, local: the layer the GM is looking at within the viewed scene.
  /// Null means "same as the layer players see".
  String? viewedLayerId;

  /// The layer id this client is displaying for [scene]. Players always see
  /// the pushed layer; the GM sees their own pick if it still exists.
  String shownLayerId(MapScene scene) {
    final v = viewedLayerId;
    if (isGM && v != null && scene.hasLayer(v)) return v;
    return scene.hasLayer(scene.activeLayerId)
        ? scene.activeLayerId
        : MapScene.baseLayerId;
  }

  /// Background image for what this client is displaying in [scene].
  String shownImageUrl(MapScene scene) =>
      scene.imageUrlFor(shownLayerId(scene));

  /// GM only: adds a layer to the viewed scene and switches the GM to it.
  /// Players keep seeing their layer until [pushLayer].
  void addLayer(MapLayer layer) {
    if (!isGM) return;
    final scene = activeScene;
    if (scene == null) return;
    _replaceActive(scene.copyWith(layers: [...scene.layers, layer]));
    viewedLayerId = layer.id;
    notifyListeners();
    _pushNow();
  }

  /// GM only: switch which layer the GM is viewing (local only).
  void viewLayer(String layerId) {
    if (!isGM) return;
    final scene = activeScene;
    if (scene == null || !scene.hasLayer(layerId)) return;
    viewedLayerId = layerId;
    notifyListeners();
  }

  /// GM only: "Push Layer to Party". Players on this scene switch to it.
  void pushLayer(String layerId) {
    if (!isGM) return;
    final scene = activeScene;
    if (scene == null || !scene.hasLayer(layerId)) return;
    viewedLayerId = layerId;
    _replaceActive(scene.copyWith(activeLayerId: layerId));
    _pushNow();
  }

  /// GM only: removes an extra layer (the base map cannot be removed).
  void removeLayer(String layerId) {
    if (!isGM || layerId == MapScene.baseLayerId) return;
    final scene = activeScene;
    if (scene == null || !scene.layers.any((l) => l.id == layerId)) return;
    final pushedWasRemoved = scene.activeLayerId == layerId;
    if (viewedLayerId == layerId) viewedLayerId = null;
    _replaceActive(
      scene.copyWith(
        layers: scene.layers.where((l) => l.id != layerId).toList(),
        activeLayerId: pushedWasRemoved ? MapScene.baseLayerId : null,
      ),
    );
    _pushNow();
  }

  /// GM only: "Push Scene to Party". Makes [sceneId] the party's scene and
  /// syncs it to players.
  void setActiveScene(String sceneId) {
    if (!isGM) return;
    if (!_scenes.any((s) => s.id == sceneId)) return;
    activeSceneId = sceneId;
    if (viewedSceneId != sceneId) viewedLayerId = null;
    viewedSceneId = sceneId;
    notifyListeners();
    _pushNow();
  }

  void updateSceneSettings(
    String sceneId, {
    bool? gridEnabled,
    double? gridSize,
    String? imageUrl,
  }) {
    if (!isGM) return;
    final i = _scenes.indexWhere((s) => s.id == sceneId);
    if (i < 0) return;
    _scenes[i] = _scenes[i].copyWith(
      gridEnabled: gridEnabled,
      gridSize: gridSize,
      imageUrl: imageUrl,
    );
    notifyListeners();
    // Slider changes fire continuously, so throttle like a drag.
    _schedulePush();
  }

  // ---- Tokens ----
  /// GM may add any token. A player may only add a token for their own
  /// character ([currentCharacterId]) that is not already on the active scene.
  void addToken(MapToken token, {String? currentCharacterId}) {
    final scene = activeScene;
    if (scene == null) return;
    if (!isGM) {
      final own = currentCharacterId;
      if (own == null || token.characterId != own) return;
      if (scene.tokens.any((t) => t.characterId == own)) return;
    }
    _replaceActive(scene.copyWith(tokens: [...scene.tokens, token]));
    _pushNow();
  }

  /// Marks [tokenId] as being dragged locally so remote updates leave it
  /// alone. Ignored if the caller may not move that token.
  void beginTokenDrag(String tokenId, {required String? currentCharacterId}) {
    final scene = activeScene;
    if (scene == null) return;
    final token = _findToken(scene, tokenId);
    if (token == null || !_canMove(token, currentCharacterId)) return;
    _draggingTokenId = tokenId;
  }

  /// Ends a drag and immediately pushes the final position.
  void endTokenDrag() {
    if (_draggingTokenId == null) return;
    _draggingTokenId = null;
    _pushNow();
  }

  bool _canMove(MapToken token, String? currentCharacterId) =>
      isGM ||
      (token.characterId != null && token.characterId == currentCharacterId);

  /// Allowed if [isGM] or the token belongs to [currentCharacterId].
  /// Pushes are throttled; finish the gesture with [endTokenDrag].
  void moveToken(
    String tokenId,
    double newX,
    double newY, {
    required String? currentCharacterId,
  }) {
    final scene = activeScene;
    if (scene == null) return;
    final token = _findToken(scene, tokenId);
    if (token == null || !_canMove(token, currentCharacterId)) return;
    _updateToken(scene, token.copyWith(x: newX, y: newY));
    _schedulePush();
  }

  /// Moves a token by ([dx], [dy]) from its CURRENT position. Use this while
  /// dragging: several pointer events can arrive between widget rebuilds, so
  /// adding to a stale position would drop movement.
  void moveTokenBy(
    String tokenId,
    double dx,
    double dy, {
    required String? currentCharacterId,
  }) {
    final scene = activeScene;
    if (scene == null) return;
    final token = _findToken(scene, tokenId);
    if (token == null) return;
    moveToken(
      tokenId,
      token.x + dx,
      token.y + dy,
      currentCharacterId: currentCharacterId,
    );
  }

  /// Snaps the token to the nearest grid intersection when the active
  /// scene has its grid enabled. No-op otherwise. Call before [endTokenDrag]
  /// so the snapped position is what gets pushed.
  void snapTokenToGrid(String tokenId) {
    final scene = activeScene;
    if (scene == null || !scene.gridEnabled || scene.gridSize <= 0) return;
    final token = _findToken(scene, tokenId);
    if (token == null) return;
    final g = scene.gridSize;
    _updateToken(
      scene,
      token.copyWith(
        x: (token.x / g).roundToDouble() * g,
        y: (token.y / g).roundToDouble() * g,
      ),
    );
  }

  /// GM only.
  void toggleTokenVisibility(String tokenId) {
    if (!isGM) return;
    final scene = activeScene;
    if (scene == null) return;
    final token = _findToken(scene, tokenId);
    if (token == null) return;
    _updateToken(
      scene,
      token.copyWith(visibleToPlayers: !token.visibleToPlayers),
    );
    _pushNow();
  }

  /// GM only.
  void removeToken(String tokenId) {
    if (!isGM) return;
    final scene = activeScene;
    if (scene == null) return;
    _replaceActive(
      scene.copyWith(
        tokens: scene.tokens.where((t) => t.id != tokenId).toList(),
      ),
    );
    _pushNow();
  }

  MapToken? _findToken(MapScene scene, String tokenId) {
    for (final t in scene.tokens) {
      if (t.id == tokenId) return t;
    }
    return null;
  }

  void _updateToken(MapScene scene, MapToken updated) {
    _replaceActive(
      scene.copyWith(
        tokens: [
          for (final t in scene.tokens) t.id == updated.id ? updated : t,
        ],
      ),
    );
  }

  void _replaceActive(MapScene updated) {
    final i = _scenes.indexWhere((s) => s.id == updated.id);
    if (i < 0) return;
    _scenes[i] = updated;
    notifyListeners();
  }
}
