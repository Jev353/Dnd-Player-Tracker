import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset, Rect;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../models/dice_roll_event.dart';
import '../models/json_helpers.dart';
import '../models/map_layer.dart';
import '../models/map_scene.dart';
import '../models/map_token.dart';
import '../services/map_sync_service.dart';
import '../services/storage_service.dart';

/// Holds the party's map scenes, the active scene, and token permissions.
/// When a real party code is set, state is mirrored through Supabase.
class MapController extends ChangeNotifier {
  MapController({
    MapSyncService? syncService,
    this.dragPushInterval = const Duration(milliseconds: 100),
    StorageService? storage,
    String? clientId,
  }) : _sync = syncService ?? MapSyncService(),
       _storage = storage,
       _persistentClientId = clientId;

  final String? _persistentClientId;

  /// How often an active GM refreshes `updated_at` so the seat isn't stale.
  static const Duration heartbeatInterval = Duration(seconds: 45);
  Timer? _heartbeatTimer;

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (!isGM || !isSynced || _disposed || gmId != clientId) return;
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      final code = partyCode;
      if (!isGM || code == null || !isSynced || gmId != clientId) {
        _stopHeartbeat();
        return;
      }
      final stamp = DateTime.now().toUtc();
      _ownPushes.add(stamp.microsecondsSinceEpoch); // Ignore our own echo.
      if (_ownPushes.length > 64) _ownPushes.remove(_ownPushes.first);
      _sync.touchGmHeartbeat(code, clientId, updatedAt: stamp).catchError((
        Object e,
      ) {
        debugPrint('heartbeat failed: $e');
      });
    });
  }

  void _stopGmHeartbeat() => _stopHeartbeat();

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Best-effort release for app termination.
  void releaseGmOnExit() => _releaseGmQuietly();

  final StorageService? _storage;

  /// Saves scenes + active scene locally (per party code) after changes.
  @override
  void notifyListeners() {
    super.notifyListeners();
    final storage = _storage;
    final code = partyCode;
    if (storage == null || code == null || _disposed) return;
    if (_scenes.isEmpty) return; // Never overwrite a saved map with nothing.
    storage
        .saveMaps(code, activeSceneId, _scenes.map((s) => s.toJson()).toList())
        .catchError((Object e) => debugPrint('saveMaps failed: $e'));
  }

  /// Loads locally saved scenes for the current party code if we have none.
  Future<void> _hydrateLocal() async {
    final storage = _storage;
    final code = partyCode;
    if (storage == null || code == null) return;
    final doc = await storage.loadMaps(code);
    if (doc == null || _disposed || partyCode != code || _scenes.isNotEmpty) {
      return;
    }
    final loaded = readList(
      doc['scenes'],
    ).map((s) => MapScene.fromJson(readMap(s))).toList();
    if (loaded.isEmpty) return;
    _scenes.addAll(loaded);
    final a = doc['active_scene_id'];
    final id = a == null ? null : readString(a, '');
    activeSceneId = _sceneById(id) != null ? id : _scenes.first.id;
    if (isGM) _restoreGmView();
    notifyListeners();
  }

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
  String get clientId =>
      _persistentClientId ?? _sync.currentUserId ?? _fallbackClientId;

  /// True when someone other than this client holds the GM seat.
  bool get gmTaken => isSynced && gmId != null && gmId != clientId;

  /// Joins [partyCode]. In a synced party the GM seat is exclusive, so
  /// [isGM] is ignored there: call [requestGm] to claim it instead.
  void setPartySession({required String partyCode, required bool isGM}) {
    final changed = this.partyCode != partyCode;
    if (changed) {
      _releaseGmQuietly();
      _stopHeartbeat();
      gmId = null;
      _voluntarilyReleasedGm = false;
    }
    this.partyCode = partyCode;
    if (changed) {
      this.isGM = isSynced ? false : isGM;
      viewedSceneId = null;
      viewedLayerId = null;
      _restartSubscription();
      _hydrateLocal();
    } else if (!isSynced) {
      this.isGM = isGM;
    }
    notifyListeners();
  }

  /// Tries to become GM. Local (unsynced) sessions always succeed; in a
  /// synced party this fails if another player already holds the seat.
  ///
  /// With [force], a GM seat held by a client whose heartbeat is stale is
  /// taken over (see [MapSyncService.staleGmTimeout]).
  Future<bool> requestGm({bool force = false}) => _claimGm(force: force);

  /// True while a claim/release is in flight, so stale stream echoes can't
  /// undo it.
  bool _claimingOrReleasing = false;
  bool _voluntarilyReleasedGm = false;

  /// Unconditionally takes the GM seat from whoever holds it (secret DM
  /// override). Scenes are preserved; the old GM demotes via the stream.
  Future<bool> forceRequestGm() => _claimGm(force: true);

  Future<bool> _claimGm({bool force = false}) async {
    final code = partyCode;
    if (code == null || !isSynced) {
      isGM = true;
      _restoreGmView();
      notifyListeners();
      return true;
    }
    // Optimistic: claiming writes a row that echoes back through the stream,
    // and that echo must already be treated as coming from the GM.
    _voluntarilyReleasedGm = false;
    _claimingOrReleasing = true;
    isGM = true;
    try {
      final ok = await _sync.claimGm(
        code,
        clientId,
        force: force,
        activeSceneId: activeSceneId ?? viewedSceneId,
        scenes: List<MapScene>.of(_scenes),
      );
      if (ok) {
        gmId = clientId;
        _startHeartbeat();
        syncError = null;
        final remote = await _sync.fetchPartyMap(code);
        if (remote != null) {
          final remoteScenes = readList(remote['scenes']);
          if (remoteScenes.isNotEmpty && _scenes.isEmpty) {
            _scenes.addAll(
              remoteScenes.map((s) => MapScene.fromJson(readMap(s))),
            );
            final ra = remote['active_scene_id'];
            final raId = ra == null ? null : readString(ra, '');
            activeSceneId = _sceneById(raId) != null ? raId : _scenes.first.id;
          } else if (remoteScenes.isEmpty && _scenes.isNotEmpty) {
            await _pushNow();
          }
        } else if (_scenes.isNotEmpty) {
          await _pushNow();
        }
        _restoreGmView();
        notifyListeners();
        await uploadLocalImages();
      } else {
        isGM = false;
        _stopHeartbeat();
        // Refreshed from the stream shortly; mark taken in the meantime.
        gmId ??= '?';
      }
      notifyListeners();
      return ok;
    } catch (e) {
      isGM = false;
      _stopHeartbeat();
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
    } finally {
      _claimingOrReleasing = false;
    }
  }

  /// A GM with no viewed scene would see an empty map even though scenes
  /// exist (e.g. after releasing and re-claiming), so fall back to the
  /// party scene, then the first scene.
  void _restoreGmView() {
    if (_sceneById(viewedSceneId) != null) return;
    viewedSceneId = activeSceneId != null && partyScene != null
        ? activeSceneId
        : (_scenes.isEmpty ? null : _scenes.first.id);
    viewedLayerId = null;
    if (_sceneById(activeSceneId) == null && _scenes.isNotEmpty) {
      activeSceneId = viewedSceneId;
      _pushNow();
    }
  }

  /// Gives up the GM seat so another player can take it.
  Future<void> releaseGm() async {
    final code = partyCode;
    final wasGm = isGM;
    _voluntarilyReleasedGm = true;
    _claimingOrReleasing = true;
    _stopHeartbeat();
    if (wasGm && activeSceneId == null && _scenes.isNotEmpty) {
      activeSceneId = viewedSceneId ?? _scenes.first.id;
    }
    if (wasGm && code != null && isSynced) {
      _pushTimer?.cancel();
      _pushTimer = null;
      await _pushNow();
    }
    isGM = false;
    viewedSceneId = null;
    viewedLayerId = null;
    try {
      if (wasGm && code != null && isSynced) {
        gmId = null;
        await _releaseGm(code);
      }
    } finally {
      _claimingOrReleasing = false;
    }
    notifyListeners();
  }

  Future<void> _releaseGm(String code) async {
    try {
      await _sync.releaseGm(
        code,
        clientId,
        activeSceneId: activeSceneId,
        scenes: List<MapScene>.of(_scenes),
      );
    } catch (e) {
      debugPrint('releaseGm failed: $e');
    }
  }

  void _releaseGmQuietly() {
    final code = partyCode;
    if (isGM && code != null && isSynced) _releaseGm(code);
  }

  // ---- Dice ----
  static const int _maxToasts = 4;

  final List<DiceRollEvent> _activeRollToasts = [];
  final List<Timer> _toastTimers = [];
  final Random _random = Random();
  bool _disposed = false;

  List<DiceRollEvent> get activeRollToasts =>
      List.unmodifiable(_activeRollToasts);

  bool get isInParty => isSynced;

  void _handleIncomingDiceRoll(DiceRollEvent event) {
    if (_disposed || _activeRollToasts.any((e) => e.id == event.id)) return;
    _activeRollToasts.add(event);
    while (_activeRollToasts.length > _maxToasts) {
      _activeRollToasts.removeAt(0);
    }
    notifyListeners();
    late final Timer timer;
    timer = Timer(const Duration(seconds: 6), () {
      _toastTimers.remove(timer);
      if (_disposed) return;
      _activeRollToasts.removeWhere((e) => e.id == event.id);
      notifyListeners();
    });
    _toastTimers.add(timer);
  }

  /// Rolls [quantity] x d[dieType], shows it locally, and broadcasts it to
  /// the party when connected.
  Future<DiceRollEvent> rollDice({
    required int dieType,
    int quantity = 1,
    required String rollerName,
  }) async {
    final count = quantity < 1 ? 1 : quantity;
    final results = [
      for (var i = 0; i < count; i++) _random.nextInt(dieType) + 1,
    ];
    final event = DiceRollEvent(
      id: newId(),
      rollerName: rollerName,
      dieType: dieType,
      quantity: count,
      results: results,
      total: results.fold<int>(0, (a, b) => a + b),
      timestamp: DateTime.now(),
    );
    _handleIncomingDiceRoll(event);
    if (isInParty) {
      try {
        await _sync.broadcastDiceRoll(event);
      } catch (e) {
        debugPrint('broadcastDiceRoll failed: $e');
      }
    }
    return event;
  }

  // ---- Sync ----
  void _restartSubscription() {
    _sub?.cancel();
    _sub = null;
    _receivedFirst = false;
    _sync.leaveSession();
    final code = partyCode;
    if (code == null || !isSynced) return;
    try {
      _sync.joinSession(code, onRemoteDiceRoll: _handleIncomingDiceRoll);
    } catch (e) {
      debugPrint('joinSession failed: $e');
    }
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
    // GM seat check runs first, before any early return (e.g. own-push echo).
    if (row != null) {
      final g = row['gm_id'];
      final newGm = g == null ? null : readString(g, '');
      if (isGM && isSynced && newGm != clientId && !_claimingOrReleasing) {
        gmId = newGm;
        isGM = false;
        viewedSceneId = null;
        viewedLayerId = null;
        _stopGmHeartbeat();
        _pushTimer?.cancel();
        _pushTimer = null;
        notifyListeners();
      }
    }
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
    if (first &&
        isSynced &&
        gmId != null &&
        gmId == clientId &&
        !isGM &&
        !_voluntarilyReleasedGm &&
        !_claimingOrReleasing) {
      // Returning GM (e.g. app restart): resume the seat automatically.
      isGM = true;
      _restoreGmView();
      _startHeartbeat();
    }
    // Claiming GM creates an empty row. A GM never deletes every scene, so an
    // empty remote list means "not uploaded yet": keep ours and upload it
    // instead of wiping the GM's maps.
    final remoteScenes = readList(row['scenes']);
    if (remoteScenes.isEmpty && _scenes.isNotEmpty) {
      // Never wipe local maps with an empty remote list.
      if (isGM) {
        _restoreGmView();
        notifyListeners();
        _pushNow();
      } else {
        notifyListeners();
      }
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

    final merged = _mergePendingTokens(_keepDraggedToken(incoming));
    _scenes
      ..clear()
      ..addAll(merged);
    // Players are locked to the GM's scene; the GM keeps their own view.
    final localStillValid =
        activeSceneId != null && _scenes.any((s) => s.id == activeSceneId);
    final remoteValid =
        remoteActiveId != null && _scenes.any((s) => s.id == remoteActiveId);
    if (!isGM || !localStillValid) {
      if (remoteValid || _scenes.isEmpty) {
        activeSceneId = remoteActiveId;
      } else if (!localStillValid) {
        activeSceneId = _scenes.first.id;
      }
    }
    if (isGM && _sceneById(viewedSceneId) == null) _restoreGmView();
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

  /// Locally added/changed tokens not yet confirmed written: id -> (sceneId,
  /// token). Remote updates are merged with these so they never vanish.
  final Map<String, (String, MapToken)> _pendingTokens = {};
  Timer? _tokenPatchTimer;

  List<MapScene> _mergePendingTokens(List<MapScene> incoming) {
    if (_pendingTokens.isEmpty) return incoming;
    // Confirmed once a remote row contains the token; otherwise another
    // writer clobbered it (concurrent read-modify-write), so re-assert it.
    final seen = <String>{
      for (final s in incoming)
        for (final t in s.tokens) t.id,
    };
    _pendingTokens.removeWhere((id, _) => seen.contains(id));
    for (final id in _pendingTokens.keys.toList()) {
      scheduleMicrotask(() {
        if (_pendingTokens.containsKey(id) && !_disposed) _pushTokenPatch(id);
      });
    }
    if (_pendingTokens.isEmpty) return incoming;
    return [
      for (final s in incoming)
        () {
          final extra = [
            for (final e in _pendingTokens.values)
              if (e.$1 == s.id && !s.tokens.any((t) => t.id == e.$2.id)) e.$2,
          ];
          return extra.isEmpty
              ? s
              : s.copyWith(tokens: [...s.tokens, ...extra]);
        }(),
    ];
  }

  void _scheduleTokenPatch(String tokenId) {
    if (!isSynced) return;
    _tokenPatchTimer ??= Timer(dragPushInterval, () {
      _tokenPatchTimer = null;
      _pushTokenPatch(tokenId);
    });
  }

  /// Writes only token [tokenId] (merged by id into the latest remote row).
  /// Allowed for players too: permission is enforced by the callers.
  Future<void> _pushTokenPatch(String tokenId) {
    final code = partyCode;
    final scene = activeScene;
    if (code == null || !isSynced || scene == null) return Future.value();
    final sceneId = scene.id;
    return _enqueue(() => _pushTokenPatchImpl(code, sceneId, tokenId));
  }

  Future<void> _pushTokenPatchImpl(
    String code,
    String sceneId,
    String tokenId,
  ) async {
    final scene = _sceneById(sceneId);
    if (scene == null) return;
    final token = _findToken(scene, tokenId); // Latest local version.
    if (token == null) return;
    try {
      await _sync.upsertToken(code, scene.id, token);
      if (syncError != null) {
        syncError = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('upsertToken failed: $e');
      syncError = e.toString();
      notifyListeners();
    }
  }

  Future<void> _pushTokenRemoval(String sceneId, String tokenId) {
    final code = partyCode;
    if (code == null || !isSynced) return Future.value();
    return _enqueue(() async {
      try {
        await _sync.removeTokenById(code, sceneId, tokenId);
      } catch (e) {
        debugPrint('removeTokenById failed: $e');
        syncError = e.toString();
        notifyListeners();
      }
    });
  }

  /// Throttled push used while dragging: at most one per [dragPushInterval],
  /// always carrying the latest state.
  void _schedulePush() {
    if (!isSynced) return;
    _pushTimer ??= Timer(dragPushInterval, _pushNow);
  }

  Future<void> _writeChain = Future<void>.value();

  /// Runs [op] after every previously queued write so full pushes and
  /// per-token patches never interleave (no lost updates).
  Future<void> _enqueue(Future<void> Function() op) {
    final next = _writeChain.then((_) => op()).catchError((Object e) {
      debugPrint('map write failed: $e');
    });
    _writeChain = next;
    return next;
  }

  Future<void> _pushNow() {
    _pushTimer?.cancel();
    _pushTimer = null;
    return _enqueue(_pushNowImpl);
  }

  Future<void> _pushNowImpl() async {
    final code = partyCode;
    if (code == null || !isSynced) return;
    if (!isGM && !_claimingOrReleasing) return; // Demoted: never push.
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

  bool _isLocalPath(String url) {
    final u = url.trim();
    return u.isNotEmpty &&
        !u.startsWith('http://') &&
        !u.startsWith('https://');
  }

  /// GM only: uploads every scene/layer image that is still a local file
  /// path (e.g. maps prepared before joining a party) to Supabase Storage
  /// and swaps in the public URL so players can see them. Images that fail
  /// to upload are left as they are. Returns how many were uploaded.
  Future<int> uploadLocalImages() async {
    if (!isGM || !isSynced) return 0;
    var uploaded = 0;
    for (final scene in List<MapScene>.of(_scenes)) {
      var imageUrl = scene.imageUrl;
      if (_isLocalPath(imageUrl)) {
        final url = await resolveImageUrl(imageUrl);
        if (!_isLocalPath(url)) {
          imageUrl = url;
          uploaded++;
        }
      }
      final layers = <MapLayer>[];
      for (final layer in scene.layers) {
        var layerUrl = layer.imageUrl;
        if (_isLocalPath(layerUrl)) {
          final url = await resolveImageUrl(layerUrl);
          if (!_isLocalPath(url)) {
            layerUrl = url;
            uploaded++;
          }
        }
        layers.add(layer.copyWith(imageUrl: layerUrl));
      }
      // Re-read: the scene may have changed while uploading.
      final i = _scenes.indexWhere((s) => s.id == scene.id);
      if (i < 0) continue;
      _scenes[i] = _scenes[i].copyWith(imageUrl: imageUrl, layers: layers);
    }
    if (uploaded > 0) {
      notifyListeners();
      await _pushNow();
    }
    return uploaded;
  }

  @override
  void dispose() {
    _stopHeartbeat();
    _pushTimer?.cancel();
    _sub?.cancel();
    for (final timer in _toastTimers) {
      timer.cancel();
    }
    try {
      _sync.leaveSession();
    } catch (_) {}
    _disposed = true;
    super.dispose();
  }

  // ---- Scenes (GM only) ----
  /// Adds a scene and switches the GM's view to it. Players are not moved
  /// until the GM calls [setActiveScene].
  void addScene(MapScene scene) {
    if (!isGM) return;
    _scenes.add(scene);
    activeSceneId ??= scene.id;
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

  // ---- Fog of War (GM only, applies to the viewed scene) ----
  Offset? _lastReveal;

  void setFogEnabled(bool enabled) {
    if (!isGM) return;
    final scene = activeScene;
    if (scene == null) return;
    _replaceActive(scene.copyWith(fogEnabled: enabled));
    _pushNow();
  }

  /// Reveals a circle of [radius] around [center] (scene coordinates).
  /// Pushes are throttled while brushing; finish with [endReveal].
  void revealArea(Offset center, [double? radius]) {
    if (!isGM) return;
    final scene = activeScene;
    if (scene == null || !scene.fogEnabled) return;
    final r = radius ?? fogBrushRadius;
    // Skip near-duplicates so a long drag does not create thousands of rects.
    final last = _lastReveal;
    if (last != null && (center - last).distance < r * 0.35) return;
    _lastReveal = center;
    final rect = Rect.fromCircle(center: center, radius: r);
    final target = fogTargetCharacterId;
    if (target == null) {
      _replaceActive(
        scene.copyWith(revealedRects: [...scene.revealedRects, rect]),
      );
    } else {
      _replaceActive(
        scene.copyWith(
          playerRevealedRects: {
            ...scene.playerRevealedRects,
            target: [...(scene.playerRevealedRects[target] ?? const []), rect],
          },
        ),
      );
    }
    _schedulePush();
  }

  static const double minFogBrushRadius = 15.0;
  static const double maxFogBrushRadius = 250.0;

  /// Radius of the reveal brush (scene units).
  double fogBrushRadius = 60.0;

  /// null = Global (all players); otherwise the characterId revealed to.
  String? fogTargetCharacterId;

  void setFogBrushRadius(double radius) {
    fogBrushRadius = radius.clamp(minFogBrushRadius, maxFogBrushRadius);
    notifyListeners();
  }

  void setFogTargetCharacterId(String? characterId) {
    fogTargetCharacterId = characterId;
    notifyListeners();
  }

  /// Covers the map again for the selected target only: the target player's
  /// private reveals, or the global reveals when no player is selected.
  void resetTargetFog() {
    if (!isGM) return;
    final scene = activeScene;
    if (scene == null) return;
    final target = fogTargetCharacterId;
    if (target == null) {
      _replaceActive(scene.copyWith(revealedRects: const []));
    } else {
      _replaceActive(
        scene.copyWith(
          playerRevealedRects: {...scene.playerRevealedRects}..remove(target),
        ),
      );
    }
    _pushNow();
  }

  /// Ends a brush stroke and pushes the final fog state immediately.
  void endReveal() {
    if (_lastReveal == null) return;
    _lastReveal = null;
    _pushNow();
  }

  /// Covers the whole map again.
  void resetFog() {
    if (!isGM) return;
    final scene = activeScene;
    if (scene == null) return;
    _replaceActive(
      scene.copyWith(revealedRects: const [], playerRevealedRects: const {}),
    );
    _pushNow();
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
    _pendingTokens[token.id] = (scene.id, token);
    _pushTokenPatch(token.id);
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
    final id = _draggingTokenId!;
    _draggingTokenId = null;
    _tokenPatchTimer?.cancel();
    _tokenPatchTimer = null;
    _pushTokenPatch(id);
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
    final moved = token.copyWith(x: newX, y: newY);
    _updateToken(scene, moved);
    if (_pendingTokens.containsKey(tokenId)) {
      _pendingTokens[tokenId] = (scene.id, moved);
    }
    _scheduleTokenPatch(tokenId);
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
    _pendingTokens.remove(tokenId);
    _pushTokenRemoval(scene.id, tokenId);
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
