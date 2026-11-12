import 'dart:io';

import 'package:dnd_tracker/main.dart';
import 'package:dnd_tracker/services/storage_service.dart';
import 'package:dnd_tracker/state/character_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dashboard renders, damage uses temp HP first, spell modal flow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 2400));
    final dir = Directory.systemTemp.createTempSync('dnd_ui');
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final ctrl = CharacterController(StorageService(overrideDirectory: dir),
        saveDelay: const Duration(milliseconds: 10));
    await tester.runAsync(ctrl.load);
    await tester.pumpWidget(DnDTrackerApp(controller: ctrl));

    expect(find.text('Hit Points'), findsOneWidget);
    expect(find.text('Spell Slots'), findsOneWidget);
    expect(find.text('Features & Notes'), findsOneWidget);
    expect(find.textContaining('Saved'), findsOneWidget);

    ctrl.mutate((c) {
      c.hpTemp = 5;
      c.hpCurrent = 10;
    });
    await tester.pump();
    await tester.tap(find.text('- Damage'));
    await tester.pump();
    expect(ctrl.active!.hpTemp, 4);
    expect(ctrl.active!.hpCurrent, 10);

    await tester.tap(find.text('Add Spell'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Spell Name'), 'Fireball');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(ctrl.active!.spells.single.name, 'Fireball');

    await tester.tap(find.text('Fireball'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Adding a proficiency must land in proficiencies, not notes.
    await tester.tap(find.text('Add Proficiency'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextField, 'Name')), 'Light armor');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(ctrl.active!.proficiencies.single.name, 'Light armor');
    expect(ctrl.active!.featuresAndNotes, isEmpty);

    // And adding a note must land in notes.
    await tester.tap(find.text('Add Note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextField, 'Name')), 'Clue');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(ctrl.active!.featuresAndNotes.single.name, 'Clue');
    expect(ctrl.active!.proficiencies.length, 1);

    // Bio pop-up edits the character's bio.
    await tester.tap(find.text('Add Bio'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Born in Waterdeep');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(ctrl.active!.bio, 'Born in Waterdeep');
    expect(find.text('View / Edit Bio'), findsOneWidget);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpWidget(const SizedBox());
    ctrl.dispose();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
}

