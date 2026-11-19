import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show isCloudSyncConfigured;
import '../models/dice_roll_event.dart';
import '../models/json_helpers.dart';
import '../models/map_scene.dart';
import '../models/map_token.dart';
import 'sync_service.dart';

/// Pushes/pulls the shared party map via Supabase. No-ops when not configured.
class MapSyncService {
  static const String mapImageBucket = 'map-images';

  SupabaseClient get _supabase => Supabase.instance.client;

  RealtimeChannel? _channel;

  /// Called when another player broadcasts a dice roll.
  void Function(DiceRollEvent event)? onRemoteDiceRoll;

  /// Joins the party's realtime broadcast channel. No-op when cloud sync is
  /// not configured.
  void joinSession(
    String partyCode, {
    void Function(DiceRollEvent event)? onRemoteDiceRoll,
  }) {
    leaveSession();
    if (onRemoteDiceRoll != null) this.onRemoteDiceRoll = onRemoteDiceRoll;
    if (!isCloudSyncConfigured) return;
    final code = SyncService.normalizeRoom(partyCode);
    _channel = _supabase
        .channel('party_map_$code')
        .onBroadcast(
          event: 'dice_roll',
          callback: (payload) {
            this.onRemoteDiceRoll?.call(DiceRollEvent.fromJson(payload));
          },
        )
        .subscribe();
  }

  /// Leaves the realtime channel joined by [joinSession].
  void leaveSession() {
    final ch = _channel;
    _channel = null;
    if (ch != null) _supabase.removeChannel(ch);
  }

  /// Sends [event] to everyone else in the party lobby.
  Future<void> broadcastDiceRoll(DiceRollEvent event) async {
    if (_channel != null) {
      await _channel!.sendBroadcastMessage(
        event: 'dice_roll',
        payload: event.toJson(),
      );
    }
  }

  /// Upserts the whole party map document. [updatedAt] lets the caller
  /// remember the exact stamp so it can recognise its own echo.
  Future<void> pushPartyMapState(
    String partyCode,
    String? activeSceneId,
    List<MapScene> scenes, {
    DateTime? updatedAt,
  }) async {
    if (!isCloudSyncConfigured) return;
    await _supabase.from('party_maps').upsert({
      'party_code': SyncService.normalizeRoom(partyCode),
      'active_scene_id': activeSceneId,
      'scenes': scenes.map((s) => s.toJson()).toList(),
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    });
  }

  /// True once the atomic token functions proved absent from the database
  /// (see supabase/migrations/20261118_atomic_map_tokens.sql).
  bool _rpcMissing = false;

  static bool _isMissingFunction(PostgrestException e) =>
      e.code == 'PGRST202' || e.code == '42883';

  /// Adds or replaces a single token (by id) in scene [sceneId] without
  /// touching any other token: reads the latest row, merges, writes back.
  Future<void> upsertToken(
    String partyCode,
    String sceneId,
    MapToken token,
  ) async {
    if (isCloudSyncConfigured && !_rpcMissing) {
      try {
        await _supabase.rpc(
          'upsert_map_token',
          params: {
            'p_party_code': SyncService.normalizeRoom(partyCode),
            'p_scene_id': sceneId,
            'p_token': token.toJson(),
          },
        );
        return;
      } on PostgrestException catch (e) {
        if (!_isMissingFunction(e)) rethrow;
        _rpcMissing = true; // Migration not applied: use the fallback below.
      }
    }
    // Fallback: the party map is one JSON document, so concurrent read-modify-write
    // cycles can clobber each other. Verify after writing and retry if our
    // token was lost to a racing writer.
    for (var attempt = 0; attempt < 4; attempt++) {
      final row = await fetchPartyMap(partyCode);
      if (row == null) return;
      final scenes = readList(
        row['scenes'],
      ).map((s) => MapScene.fromJson(readMap(s))).toList();
      final i = scenes.indexWhere((s) => s.id == sceneId);
      if (i < 0) return;
      final tokens = [...scenes[i].tokens];
      final t = tokens.indexWhere((x) => x.id == token.id);
      if (t < 0) {
        tokens.add(token);
      } else {
        tokens[t] = token;
      }
      scenes[i] = scenes[i].copyWith(tokens: tokens);
      final active = row['active_scene_id'];
      await pushPartyMapState(
        partyCode,
        active == null ? null : readString(active, ''),
        scenes,
      );
      final check = await fetchPartyMap(partyCode);
      if (check == null) return;
      final stored = readList(check['scenes'])
          .map((s) => MapScene.fromJson(readMap(s)))
          .where((s) => s.id == sceneId)
          .expand((s) => s.tokens);
      if (stored.any((x) => x.id == token.id)) return;
    }
  }

  /// Removes a single token (by id) from scene [sceneId], leaving every
  /// other token in the latest stored row untouched.
  Future<void> removeTokenById(
    String partyCode,
    String sceneId,
    String tokenId,
  ) async {
    if (isCloudSyncConfigured && !_rpcMissing) {
      try {
        await _supabase.rpc(
          'remove_map_token',
          params: {
            'p_party_code': SyncService.normalizeRoom(partyCode),
            'p_scene_id': sceneId,
            'p_token_id': tokenId,
          },
        );
        return;
      } on PostgrestException catch (e) {
        if (!_isMissingFunction(e)) rethrow;
        _rpcMissing = true;
      }
    }
    final row = await fetchPartyMap(partyCode);
    if (row == null) return;
    final scenes = readList(
      row['scenes'],
    ).map((s) => MapScene.fromJson(readMap(s))).toList();
    final i = scenes.indexWhere((s) => s.id == sceneId);
    if (i < 0) return;
    scenes[i] = scenes[i].copyWith(
      tokens: scenes[i].tokens.where((t) => t.id != tokenId).toList(),
    );
    final active = row['active_scene_id'];
    await pushPartyMapState(
      partyCode,
      active == null ? null : readString(active, ''),
      scenes,
    );
  }

  /// Emits the party's map row (or null while none exists yet) on every
  /// change. Empty stream when cloud sync is not configured.
  Stream<Map<String, dynamic>?> subscribeToPartyMap(String partyCode) {
    if (!isCloudSyncConfigured) return const Stream.empty();
    return _supabase
        .from('party_maps')
        .stream(primaryKey: ['party_code'])
        .eq('party_code', SyncService.normalizeRoom(partyCode))
        .map<Map<String, dynamic>?>(
          (rows) => rows.isEmpty ? null : readMap(rows.first),
        );
  }

  /// Fetches the party's map row once, or null if none / not configured.
  Future<Map<String, dynamic>?> fetchPartyMap(String partyCode) async {
    if (!isCloudSyncConfigured) return null;
    final row = await _supabase
        .from('party_maps')
        .select()
        .eq('party_code', SyncService.normalizeRoom(partyCode))
        .maybeSingle();
    return row == null ? null : readMap(row);
  }

  /// Stable id for this install (Supabase anonymous user), or null when
  /// cloud sync is unavailable.
  String? get currentUserId =>
      isCloudSyncConfigured ? _supabase.auth.currentUser?.id : null;

  /// Tries to become the party's GM. Returns true if [clientId] now holds
  /// the role (including when it already did), false if someone else does.
  /// Requires the `gm_id text` column on `party_maps`.
  ///
  /// A normal claim ([force] false) NEVER overwrites an existing GM: there
  /// is no time-based takeover (clock skew would make it unsafe). Only
  /// [force] (the hidden DM takeover) replaces the current GM.
  Future<bool> claimGm(
    String partyCode,
    String clientId, {
    bool force = false,
    String? activeSceneId,
    List<MapScene>? scenes,
  }) async {
    if (!isCloudSyncConfigured) return true;
    final code = SyncService.normalizeRoom(partyCode);
    final now = DateTime.now().toUtc().toIso8601String();
    if (force) {
      final updated = await _supabase
          .from('party_maps')
          .update({'gm_id': clientId, 'updated_at': now})
          .eq('party_code', code)
          .select();
      if (updated.isNotEmpty) return true;
      return _insertRow(code, clientId, activeSceneId, scenes, now);
    }
    final row = await _supabase
        .from('party_maps')
        .select('gm_id')
        .eq('party_code', code)
        .maybeSingle();
    if (row == null) {
      return _insertRow(code, clientId, activeSceneId, scenes, now);
    }
    final current = row['gm_id'];
    if (current == clientId) return true;
    if (current != null) return false;
    // Conditional update: only succeeds while the seat is still empty.
    final updated = await _supabase
        .from('party_maps')
        .update({'gm_id': clientId, 'updated_at': now})
        .eq('party_code', code)
        .isFilter('gm_id', null)
        .select();
    return updated.isNotEmpty;
  }

  Future<bool> _insertRow(
    String code,
    String clientId,
    String? activeSceneId,
    List<MapScene>? scenes,
    String now,
  ) async {
    try {
      await _supabase.from('party_maps').insert({
        'party_code': code,
        'gm_id': clientId,
        'active_scene_id': activeSceneId,
        'scenes': (scenes ?? const <MapScene>[]).map((s) => s.toJson()).toList(),
        'updated_at': now,
      });
      return true;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return false; // Lost a race to another GM.
      rethrow;
    }
  }

  /// Unconditionally takes the GM seat (hidden DM override).
  Future<bool> forceClaimGm(
    String partyCode,
    String clientId, {
    String? activeSceneId,
    List<MapScene>? scenes,
  }) => claimGm(
    partyCode,
    clientId,
    force: true,
    activeSceneId: activeSceneId,
    scenes: scenes,
  );
  /// Refreshes `updated_at` so an active GM's seat is never stale.
  Future<void> touchGmHeartbeat(
    String partyCode,
    String clientId, {
    DateTime? updatedAt,
  }) async {
    if (!isCloudSyncConfigured) return;
    await _supabase
        .from('party_maps')
        .update({
          'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
        })
        .eq('party_code', SyncService.normalizeRoom(partyCode))
        .eq('gm_id', clientId);
  }

  /// Gives up the GM role, but only if [clientId] actually holds it.
  Future<void> releaseGm(
    String partyCode,
    String clientId, {
    String? activeSceneId,
    List<MapScene>? scenes,
  }) async {
    if (!isCloudSyncConfigured) return;
    await _supabase
        .from('party_maps')
        .update({
          'gm_id': null,
          if (scenes != null) ...{
            'active_scene_id': activeSceneId,
            'scenes': scenes.map((s) => s.toJson()).toList(),
          },
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('party_code', SyncService.normalizeRoom(partyCode))
        .eq('gm_id', clientId);
  }

  /// Uploads a local image to the public `map-images` bucket and returns its
  /// public URL, or null when cloud sync is not configured. Throws on
  /// Supabase errors (e.g. bucket missing).
  Future<String?> uploadMapImage(String partyCode, String filePath) async {
    if (!isCloudSyncConfigured) return null;
    final dot = filePath.lastIndexOf('.');
    final ext = dot < 0 ? '' : filePath.substring(dot).toLowerCase();
    final objectPath = '${SyncService.normalizeRoom(partyCode)}/${newId()}$ext';
    final bucket = _supabase.storage.from(mapImageBucket);
    await bucket.upload(
      objectPath,
      File(filePath),
      fileOptions: FileOptions(upsert: true, contentType: _contentType(ext)),
    );
    return bucket.getPublicUrl(objectPath);
  }

  static String? _contentType(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
    }
    return null;
  }
}
