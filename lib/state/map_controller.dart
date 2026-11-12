import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/json_helpers.dart';
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

  void setPartySession({required String partyCode, required bool isGM}) {
    final changed = this.partyCode != partyCode;
    this.partyCode = partyCode;
    this.isGM = isGM;
    if (changed) _restartSubscription();
    notifyListeners();
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
      // No shared state yet: a GM seeds it with whatever they have locally.
      if (first && isGM && _scenes.isNotEmpty) _pushNow();
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
    viewedSceneId = scene.id;
    notifyListeners();
    _pushNow();
  }

  /// GM only: switch which scene the GM is viewing (local only).
  void viewScene(String sceneId) {
    if (!isGM) return;
    if (!_scenes.any((s) => s.id == sceneId)) return;
    viewedSceneId = sceneId;
    notifyListeners();
  }

  /// GM only: "Push Scene to Party". Makes [sceneId] the party's scene and
  /// syncs it to players.
  void setActiveScene(String sceneId) {
    if (!isGM) return;
    if (!_scenes.any((s) => s.id == sceneId)) return;
    activeSceneId = sceneId;
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
