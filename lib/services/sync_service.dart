import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show isCloudSyncConfigured;
import '../models/character.dart';

/// Pushes/pulls party characters via Supabase. No-ops when not configured.
class SyncService {
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  SupabaseClient get _supabase => Supabase.instance.client;

  static String normalizeRoom(String code) => code.toUpperCase().trim();

  Future<void> pushCharacter({
    required String roomCode,
    required Character character,
  }) async {
    if (!isCloudSyncConfigured) return;
    await _supabase.from('party_characters').upsert({
      'character_id': character.id,
      'room_code': normalizeRoom(roomCode),
      'character_name': character.name,
      'character_data': character.toJson(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void listenToParty({
    required String roomCode,
    required void Function(List<Character>) onPartyUpdated,
    void Function(Object)? onError,
  }) {
    _sub?.cancel();
    _sub = null;
    if (!isCloudSyncConfigured) return;
    try {
      _sub = _supabase
          .from('party_characters')
          .stream(primaryKey: ['character_id'])
          .eq('room_code', normalizeRoom(roomCode))
          .listen((rows) {
            final members = <Character>[];
            for (final row in rows) {
              try {
                final data = row['character_data'];
                if (data is Map) {
                  members.add(
                    Character.fromJson(Map<String, dynamic>.from(data)),
                  );
                }
              } catch (_) {
                // Skip malformed rows.
              }
            }
            onPartyUpdated(members);
          }, onError: (Object e) => onError?.call(e));
    } catch (e) {
      onError?.call(e);
    }
  }

  void disconnect() {
    _sub?.cancel();
    _sub = null;
  }
}
