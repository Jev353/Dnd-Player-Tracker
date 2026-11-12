import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show isCloudSyncConfigured;
import '../models/json_helpers.dart';
import '../models/map_scene.dart';
import 'sync_service.dart';

/// Pushes/pulls the shared party map via Supabase. No-ops when not configured.
class MapSyncService {
  static const String mapImageBucket = 'map-images';

  SupabaseClient get _supabase => Supabase.instance.client;

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
