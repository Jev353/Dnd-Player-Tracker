import 'dart:async';

import 'package:dnd_tracker/models/json_helpers.dart';
import 'package:dnd_tracker/models/map_scene.dart';
import 'package:dnd_tracker/services/map_sync_service.dart';
import 'package:dnd_tracker/state/map_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the `party_maps` table.
class FakeMapSync extends MapSyncService {
  Map<String, dynamic>? row;
  final List<StreamController<Map<String, dynamic>?>> _streams = [];

  void _emit() {
    for (final s in _streams) {
      s.add(row == null ? null : Map<String, dynamic>.from(row!));
    }
  }

  @override
  String? get currentUserId => 'me';

  @override
  Future<void> pushPartyMapState(
    String partyCode,
    String? activeSceneId,
    List<MapScene> scenes, {
    DateTime? updatedAt,
  }) async {
    row = {
      'party_code': partyCode,
      'gm_id': row?['gm_id'],
      'active_scene_id': activeSceneId,
      'scenes': scenes.map((s) => s.toJson()).toList(),
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
    _emit();
  }

  @override
  Stream<Map<String, dynamic>?> subscribeToPartyMap(String partyCode) {
    final c = StreamController<Map<String, dynamic>?>();
    _streams.add(c);
    scheduleMicrotask(
      () => c.add(row == null ? null : Map<String, dynamic>.from(row!)),
    );
    return c.stream;
  }

  @override
  Future<bool> claimGm(String partyCode, String clientId) async {
    if (row == null) {
      row = {
        'party_code': partyCode,
        'gm_id': clientId,
        'active_scene_id': null,
        'scenes': <dynamic>[],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
    } else if (row!['gm_id'] == null || row!['gm_id'] == clientId) {
      row!['gm_id'] = clientId;
      row!['updated_at'] = DateTime.now().toUtc().toIso8601String();
    } else {
      return false;
    }
    _emit();
    return true;
  }

  @override
  Future<void> releaseGm(String partyCode, String clientId) async {
    if (row != null && row!['gm_id'] == clientId) {
      row!['gm_id'] = null;
      row!['updated_at'] = DateTime.now().toUtc().toIso8601String();
      _emit();
    }
  }
}

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  test('release then become GM keeps scenes (in a party)', () async {
    final fake = FakeMapSync();
    final mc = MapController(syncService: fake);
    mc.setPartySession(partyCode: 'ABCD', isGM: false);
    await settle();
    await mc.requestGm();
    await settle();
    mc.addScene(MapScene(name: 'World'));
    mc.addScene(MapScene(name: 'Town'));
    await settle();
    expect(mc.scenes.length, 2);

    await mc.releaseGm();
    await settle();
    expect(mc.scenes.length, 2, reason: 'after release');

    await mc.requestGm();
    await settle();
    expect(mc.scenes.length, 2, reason: 'after re-claim');
    expect(readList(fake.row!['scenes']).length, 2, reason: 'server copy');
  });

  test('scenes made locally survive joining a party and claiming GM', () async {
    final fake = FakeMapSync();
    final mc = MapController(syncService: fake);
    mc.setPartySession(partyCode: MapController.localPartyCode, isGM: true);
    mc.addScene(MapScene(name: 'Prepared offline'));
    expect(mc.scenes.length, 1);

    mc.setPartySession(partyCode: 'ABCD', isGM: false);
    await settle();
    await mc.requestGm();
    await settle();
    expect(mc.scenes.length, 1, reason: 'prepared scenes kept');
    expect(readList(fake.row!['scenes']).length, 1, reason: 'uploaded');
  });
}
