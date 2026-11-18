import 'dart:async';

import 'package:dnd_tracker/models/json_helpers.dart';
import 'package:dnd_tracker/models/map_layer.dart';
import 'package:dnd_tracker/models/map_scene.dart';
import 'package:dnd_tracker/models/map_token.dart';
import 'package:dnd_tracker/services/map_sync_service.dart';
import 'package:dnd_tracker/state/map_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shared in-memory `party_maps` table.
class FakeDb {
  Map<String, dynamic>? row;
  final List<StreamController<Map<String, dynamic>?>> streams = [];

  void emit() {
    for (final s in streams) {
      s.add(row == null ? null : Map<String, dynamic>.from(row!));
    }
  }
}

/// In-memory stand-in for the `party_maps` table.
class FakeMapSync extends MapSyncService {
  FakeMapSync({FakeDb? db, this.userId = 'me'}) : db = db ?? FakeDb();

  final FakeDb db;
  final String userId;

  Map<String, dynamic>? get row => db.row;
  set row(Map<String, dynamic>? v) => db.row = v;

  @override
  String? get currentUserId => userId;

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
    db.emit();
  }

  @override
  Stream<Map<String, dynamic>?> subscribeToPartyMap(String partyCode) {
    final c = StreamController<Map<String, dynamic>?>();
    db.streams.add(c);
    scheduleMicrotask(
      () => c.add(row == null ? null : Map<String, dynamic>.from(row!)),
    );
    return c.stream;
  }

  @override
  Future<Map<String, dynamic>?> fetchPartyMap(String partyCode) async =>
      row == null ? null : Map<String, dynamic>.from(row!);

  @override
  Future<bool> claimGm(
    String partyCode,
    String clientId, {
    bool force = false,
    String? activeSceneId,
    List<MapScene>? scenes,
  }) async {
    final holder = row?['gm_id'];
    if (row != null && holder != null && holder != clientId) {
      final stamp = DateTime.tryParse('${row!['updated_at']}');
      if (!MapSyncService.isStale(stamp)) return false;
      row!['gm_id'] = clientId;
      row!['updated_at'] = DateTime.now().toUtc().toIso8601String();
      db.emit();
      return true;
    }
    if (row == null) {
      row = {
        'party_code': partyCode,
        'gm_id': clientId,
        'active_scene_id': activeSceneId,
        'scenes': (scenes ?? const <MapScene>[])
            .map((s) => s.toJson())
            .toList(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
    } else if (row!['gm_id'] == null || row!['gm_id'] == clientId) {
      row!['gm_id'] = clientId;
      row!['updated_at'] = DateTime.now().toUtc().toIso8601String();
    } else {
      return false;
    }
    db.emit();
    return true;
  }

  @override
  Future<void> releaseGm(
    String partyCode,
    String clientId, {
    String? activeSceneId,
    List<MapScene>? scenes,
  }) async {
    if (row != null && row!['gm_id'] == clientId) {
      row!['gm_id'] = null;
      if (scenes != null) {
        row!['active_scene_id'] = activeSceneId;
        row!['scenes'] = scenes.map((s) => s.toJson()).toList();
      }
      row!['updated_at'] = DateTime.now().toUtc().toIso8601String();
      db.emit();
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

  test('same DM releases and re-claims keeps everything', () async {
    final fake = FakeMapSync();
    final mc = MapController(syncService: fake);
    mc.setPartySession(partyCode: 'ABCD', isGM: false);
    await settle();
    await mc.requestGm();
    await settle();
    mc.addScene(MapScene(name: 'World'));
    mc.addLayer(MapLayer(name: 'Roof'));
    mc.addToken(MapToken(label: 'Goblin', x: 10, y: 20));
    mc.setFogEnabled(true);
    mc.revealArea(const Offset(100, 100), 50);
    mc.endReveal();
    mc.addScene(MapScene(name: 'Town'));
    mc.viewScene(mc.scenes.first.id);
    await settle();
    final sceneId = mc.activeScene!.id;

    await mc.releaseGm();
    await settle();
    await mc.requestGm();
    await settle();

    expect(mc.scenes.length, 2);
    expect(mc.activeScene, isNotNull);
    expect(mc.activeScene!.id, sceneId);
    expect(mc.activeScene!.layers.length, 1);
    expect(mc.activeScene!.tokens.single.label, 'Goblin');
    expect(mc.activeScene!.fogEnabled, isTrue);
    expect(mc.activeScene!.revealedRects, isNotEmpty);
  });

  test('release without setActiveScene keeps active scene', () async {
    final fake = FakeMapSync();
    final mc = MapController(syncService: fake);
    mc.setPartySession(partyCode: 'ABCD', isGM: false);
    await settle();
    await mc.requestGm();
    await settle();
    mc.addScene(MapScene(name: 'World'));
    await mc.releaseGm();
    await settle();
    expect(mc.activeScene, isNotNull);
    await mc.requestGm();
    await settle();
    expect(mc.activeScene, isNotNull);
    expect(mc.scenes.length, 1);
  });

  test('handoff from DM A to DM B', () async {
    final db = FakeDb();
    final a = MapController(
      syncService: FakeMapSync(db: db, userId: 'A'),
    );
    final b = MapController(
      syncService: FakeMapSync(db: db, userId: 'B'),
    );
    a.setPartySession(partyCode: 'ABCD', isGM: false);
    b.setPartySession(partyCode: 'ABCD', isGM: false);
    await settle();
    await a.requestGm();
    await settle();
    a.addScene(MapScene(name: 'World'));
    a.addLayer(MapLayer(name: 'Roof'));
    a.addToken(MapToken(label: 'Orc', x: 1, y: 2));
    await settle();
    final sceneId = a.activeScene!.id;
    await a.releaseGm();
    await settle();

    expect(await b.requestGm(), isTrue);
    await settle();
    expect(b.scenes.length, 1);
    expect(b.activeScene!.id, sceneId);
    expect(b.activeScene!.layers.length, 1);
    expect(b.activeScene!.tokens.single.label, 'Orc');
    b.addToken(MapToken(label: 'Elf', x: 5, y: 5));
    await settle();
    expect(b.activeScene!.tokens.length, 2);
    expect(db.row!['gm_id'], 'B');
  });

  test('GM reconnects with same clientId after restart', () async {
    final db = FakeDb();
    final first = MapController(
      syncService: FakeMapSync(db: db),
      clientId: 'persistent-1',
    );
    first.setPartySession(partyCode: 'ABCD', isGM: false);
    await settle();
    expect(await first.requestGm(), isTrue);
    await settle();
    first.addScene(MapScene(name: 'World'));
    await settle();
    first.dispose(); // App closed without releasing the seat.

    final second = MapController(
      syncService: FakeMapSync(db: db, userId: 'different-anon-user'),
      clientId: 'persistent-1',
    );
    second.setPartySession(partyCode: 'ABCD', isGM: false);
    await settle();
    expect(second.isGM, isTrue);
    expect(second.gmTaken, isFalse);
    expect(second.activeScene, isNotNull);
    second.dispose();
  });

  test('stale GM seat can be taken over, fresh one cannot', () async {
    final db = FakeDb();
    final a = MapController(
      syncService: FakeMapSync(db: db),
      clientId: 'A',
    );
    final b = MapController(
      syncService: FakeMapSync(db: db),
      clientId: 'B',
    );
    a.setPartySession(partyCode: 'ABCD', isGM: false);
    b.setPartySession(partyCode: 'ABCD', isGM: false);
    await settle();
    expect(await a.requestGm(), isTrue);
    await settle();

    expect(await b.requestGm(force: true), isFalse, reason: 'A is active');
    expect(b.isGM, isFalse);

    db.row!['updated_at'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 3))
        .toIso8601String();
    expect(await b.requestGm(force: true), isTrue);
    await settle();
    expect(db.row!['gm_id'], 'B');
    expect(b.isGM, isTrue);
    expect(a.isGM, isFalse);
    a.dispose();
    b.dispose();
  });

  test('empty remote row does not wipe local scenes', () async {
    final fake = FakeMapSync();
    final mc = MapController(syncService: fake);
    mc.setPartySession(partyCode: MapController.localPartyCode, isGM: true);
    mc.addScene(MapScene(name: 'Prepared'));
    fake.row = {
      'party_code': 'ABCD',
      'gm_id': null,
      'active_scene_id': null,
      'scenes': <dynamic>[],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    mc.setPartySession(partyCode: 'ABCD', isGM: false);
    await settle();
    expect(mc.isGM, isFalse);
    expect(mc.scenes.length, 1, reason: 'not wiped by empty remote');

    await mc.requestGm();
    await settle();
    expect(mc.scenes.length, 1);
    expect(readList(fake.row!['scenes']).length, 1, reason: 'pushed');
  });
}
