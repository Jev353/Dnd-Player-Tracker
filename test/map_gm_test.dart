import 'dart:async';
import 'dart:io';

import 'package:dnd_tracker/models/json_helpers.dart';
import 'package:dnd_tracker/models/map_layer.dart';
import 'package:dnd_tracker/models/map_scene.dart';
import 'package:dnd_tracker/models/map_token.dart';
import 'package:dnd_tracker/services/map_sync_service.dart';
import 'package:dnd_tracker/state/map_controller.dart';
import 'package:dnd_tracker/services/storage_service.dart';
import 'package:dnd_tracker/state/character_controller.dart';
import 'package:dnd_tracker/ui/modals/map_modal.dart';
import 'package:flutter/material.dart';
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
    if (force) {
      if (row == null) {
        row = {
          'party_code': partyCode,
          'gm_id': clientId,
          'active_scene_id': activeSceneId,
          'scenes': (scenes ?? const <MapScene>[]).map((s) => s.toJson()).toList(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
      } else {
        row!['gm_id'] = clientId;
        row!['updated_at'] = DateTime.now().toUtc().toIso8601String();
      }
      db.emit();
      return true;
    }
    if (row == null) {
      row = {
        'party_code': partyCode,
        'gm_id': clientId,
        'active_scene_id': activeSceneId,
        'scenes': (scenes ?? const <MapScene>[]).map((s) => s.toJson()).toList(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
    } else if (row!['gm_id'] == null) {
      row!['gm_id'] = clientId;
      row!['updated_at'] = DateTime.now().toUtc().toIso8601String();
    } else {
      return row!['gm_id'] == clientId;
    }
    db.emit();
    return true;
  }
  @override
  Future<bool> forceClaimGm(
    String partyCode,
    String clientId, {
    String? activeSceneId,
    List<MapScene>? scenes,
  }) async {
    if (row == null) {
      return claimGm(
        partyCode,
        clientId,
        activeSceneId: activeSceneId,
        scenes: scenes,
      );
    }
    row!['gm_id'] = clientId;
    row!['updated_at'] = DateTime.now().toUtc().toIso8601String();
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

class _SlowReleaseSync extends FakeMapSync {
  _SlowReleaseSync({required FakeDb db, required this.onReleasing})
    : super(db: db);

  final void Function() onReleasing;

  @override
  Future<void> releaseGm(
    String partyCode,
    String clientId, {
    String? activeSceneId,
    List<MapScene>? scenes,
  }) async {
    onReleasing();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await super.releaseGm(
      partyCode,
      clientId,
      activeSceneId: activeSceneId,
      scenes: scenes,
    );
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
  test('player-added token survives DM moving another token', () async {
    final db = FakeDb();
    final dm = MapController(syncService: FakeMapSync(db: db, userId: 'DM'));
    final player = MapController(
      syncService: FakeMapSync(db: db, userId: 'P1'),
    );
    dm.setPartySession(partyCode: 'ABCD', isGM: false);
    player.setPartySession(partyCode: 'ABCD', isGM: false);
    await settle();
    await dm.requestGm();
    await settle();
    dm.addScene(MapScene(name: 'World'));
    final goblin = MapToken(label: 'Goblin', x: 10, y: 20);
    dm.addToken(goblin);
    await settle();
    expect(player.activeScene!.tokens.length, 1);

    // Player adds their character; DM has not seen it yet.
    final hero = MapToken(characterId: 'c1', label: 'Hero', x: 50, y: 60);
    player.addToken(hero, currentCharacterId: 'c1');
    // DM moves the goblin from stale state (before the echo is processed).
    dm.beginTokenDrag(goblin.id, currentCharacterId: null);
    dm.moveToken(goblin.id, 30, 40, currentCharacterId: null);
    dm.endTokenDrag();
    await settle();
    await settle();

    for (final c in [dm, player]) {
      final tokens = c.activeScene!.tokens;
      expect(tokens.length, 2, reason: 'both tokens present');
      final g = tokens.firstWhere((t) => t.id == goblin.id);
      final h = tokens.firstWhere((t) => t.id == hero.id);
      expect((g.x, g.y), (30.0, 40.0));
      expect((h.x, h.y), (50.0, 60.0));
    }
    final stored = readList(db.row!['scenes']).first;
    expect(readList(readMap(stored)['tokens']).length, 2);
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

  test('strict single-GM: normal claim never displaces an active GM', () async {
    final db = FakeDb();
    final a = MapController(syncService: FakeMapSync(db: db), clientId: 'A');
    final b = MapController(syncService: FakeMapSync(db: db), clientId: 'B');
    a.setPartySession(partyCode: 'ABCD', isGM: false);
    b.setPartySession(partyCode: 'ABCD', isGM: false);
    await settle();
    expect(await a.requestGm(), isTrue);
    await settle();
    // Even a very old heartbeat must not allow a normal takeover.
    db.row!['updated_at'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 1))
        .toIso8601String();
    expect(await b.requestGm(), isFalse);
    await settle();
    expect(b.isGM, isFalse);
    expect(b.gmTaken, isTrue);
    expect(a.isGM, isTrue);
    expect(db.row!['gm_id'], 'A');
    a.dispose();
    b.dispose();
  });

  test('force takeover demotes previous GM immediately', () async {
    final db = FakeDb();
    final a = MapController(syncService: FakeMapSync(db: db), clientId: 'A');
    final b = MapController(syncService: FakeMapSync(db: db), clientId: 'B');
    a.setPartySession(partyCode: 'ABCD', isGM: false);
    b.setPartySession(partyCode: 'ABCD', isGM: false);
    await settle();
    expect(await a.requestGm(), isTrue);
    a.addScene(MapScene(name: 'World'));
    await settle();
    var notified = 0;
    a.addListener(() => notified++);

    expect(await b.requestGm(force: true), isTrue);
    await settle();
    expect(b.isGM, isTrue);
    expect(a.isGM, isFalse);
    expect(a.gmTaken, isTrue);
    expect(notified, greaterThan(0));
    expect(db.row!['gm_id'], 'B');
    a.dispose();
    b.dispose();
  });

  test('releasing GM is not undone by a stale stream echo', () async {
    final db = FakeDb();
    late FakeMapSync syncA;
    syncA = _SlowReleaseSync(db: db, onReleasing: () {
      // In-flight echo still carrying the old gm_id.
      db.emit();
    });
    final a = MapController(syncService: syncA, clientId: 'A');
    a.setPartySession(partyCode: 'ABCD', isGM: false);
    await settle();
    expect(await a.requestGm(), isTrue);
    await settle();
    a.addScene(MapScene(name: 'World'));
    await settle();

    await a.releaseGm();
    await settle();
    expect(a.isGM, isFalse);
    expect(db.row!['gm_id'], isNull);
    a.dispose();
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

  test('forceRequestGm takes the seat from an active GM, keeps maps', () async {
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
    a.addScene(MapScene(name: 'World'));
    a.addLayer(MapLayer(name: 'Roof'));
    a.addToken(MapToken(label: 'Orc', x: 1, y: 2));
    a.setFogEnabled(true);
    await settle();

    expect(await b.requestGm(), isFalse);
    expect(await b.forceRequestGm(), isTrue);
    await settle();
    expect(db.row!['gm_id'], 'B');
    expect(b.isGM, isTrue);
    expect(b.gmId, 'B');
    expect(a.isGM, isFalse, reason: 'old GM demoted');
    expect(a.gmTaken, isTrue);
    for (final mc in [a, b]) {
      expect(mc.scenes.length, 1);
      expect(mc.activeScene!.layers.length, 1);
      expect(mc.activeScene!.tokens.single.label, 'Orc');
      expect(mc.activeScene!.fogEnabled, isTrue);
    }
    a.dispose();
    b.dispose();
  });

  Future<void> openModal(
    WidgetTester tester,
    MapController mc,
    CharacterController ctrl,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMapModal(
                context,
                mapController: mc,
                characterController: ctrl,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Force Takeover DM only shows for a character named DM', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('dnd_gm');
    final ctrl = CharacterController(
      StorageService(overrideDirectory: dir),
      saveDelay: const Duration(milliseconds: 10),
    );
    await tester.runAsync(ctrl.load);
    final db = FakeDb();
    final a = MapController(
      syncService: FakeMapSync(db: db),
      clientId: 'A',
    );
    final mc = MapController(
      syncService: FakeMapSync(db: db),
      clientId: 'B',
    );
    await tester.runAsync(() async {
      a.setPartySession(partyCode: 'ABCD', isGM: false);
      mc.setPartySession(partyCode: 'ABCD', isGM: false);
      await settle();
      await a.requestGm();
      await settle();
    });
    expect(mc.gmTaken, isTrue);
    ctrl.mutate((c) => c.name = 'Aragorn');
    ctrl.currentRoomCode = 'ABCD';

    await openModal(tester, mc, ctrl);
    final button = find.byKey(const ValueKey('force-takeover-dm'));
    expect(button, findsNothing);

    ctrl.mutate((c) => c.name = '  dm ');
    await tester.pump();
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    ctrl.mutate((c) => c.name = 'Aragorn');
    await tester.pump();
    expect(button, findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    a.dispose();
    mc.dispose();
    ctrl.dispose();
  });
}
