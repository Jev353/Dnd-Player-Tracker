import 'dart:io';

import 'package:dnd_tracker/services/storage_service.dart';
import 'package:dnd_tracker/state/character_controller.dart';
import 'package:dnd_tracker/ui/modals/map_modal.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_tracker/models/map_scene.dart';
import 'package:dnd_tracker/models/map_token.dart';
import 'package:dnd_tracker/state/map_controller.dart';
import 'package:dnd_tracker/ui/widgets/map_canvas.dart';

void main() {
  testWidgets('players cannot see or hover tokens under fog', (tester) async {
    final mc = MapController();
    mc.setPartySession(partyCode: MapController.localPartyCode, isGM: true);
    mc.addScene(MapScene(name: 'Test'));
    mc.addToken(MapToken(label: 'Secret Dragon', x: 400, y: 400));
    mc.setFogEnabled(true);
    mc.setPartySession(partyCode: MapController.localPartyCode, isGM: false);
    mc.activeSceneId = mc.scenes.first.id;

    Future<void> show() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapCanvas(
            scene: mc.activeScene!,
            mapController: mc,
            currentCharacterId: null,
          ),
        ),
      ),
    );

    await show();
    expect(find.byType(Tooltip), findsNothing);
    expect(find.text('SD'), findsNothing);
    expect(find.text('Secret Dragon'), findsNothing);

    // Reveal the area over the token: it becomes visible again.
    mc.setPartySession(partyCode: MapController.localPartyCode, isGM: true);
    mc.revealArea(const Offset(425, 425), 100);
    mc.endReveal();
    mc.setPartySession(partyCode: MapController.localPartyCode, isGM: false);
    await show();
    await tester.pump();
    expect(find.text('SD'), findsOneWidget);
  });

  testWidgets('map modal: become GM, fog, reveal drag, mouse hover', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('dnd_fog');
    final ctrl = CharacterController(
      StorageService(overrideDirectory: dir),
      saveDelay: const Duration(milliseconds: 10),
    );
    await tester.runAsync(ctrl.load);
    final mc = MapController();
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

    await tester.tap(find.text('Become GM'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    mc.addScene(MapScene(name: 'Test', gridEnabled: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).at(0)); // Fog of War
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Reveal Area (drag)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 500));
    await mouse.moveTo(const Offset(500, 520));
    await tester.pump();
    await mouse.down(const Offset(500, 520));
    await mouse.moveTo(const Offset(600, 560));
    await mouse.moveTo(const Offset(700, 600));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(mc.activeScene!.revealedRects, isNotEmpty);
  });

  for (final gm in [true, false]) {
    testWidgets('map canvas renders with fog (gm=$gm)', (tester) async {
      final mc = MapController();
      mc.setPartySession(partyCode: MapController.localPartyCode, isGM: true);
      mc.addScene(MapScene(name: 'Test', gridEnabled: true));
      mc.addToken(MapToken(label: 'Goblin', x: 100, y: 100));
      mc.setFogEnabled(true);
      mc.revealArea(const Offset(300, 300), 100);
      mc.endReveal();
      mc.setPartySession(partyCode: MapController.localPartyCode, isGM: gm);
      mc.activeSceneId ??= mc.scenes.first.id;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapCanvas(
              scene: mc.activeScene!,
              mapController: mc,
              currentCharacterId: null,
              revealMode: gm,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      if (gm) {
        await tester.dragFrom(const Offset(200, 200), const Offset(60, 60));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
