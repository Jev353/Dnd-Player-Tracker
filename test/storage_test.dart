import 'dart:io';

import 'package:dnd_tracker/models/character.dart';
import 'package:dnd_tracker/models/feature_note.dart';
import 'package:dnd_tracker/models/weapon.dart';
import 'package:dnd_tracker/services/storage_service.dart';
import 'package:dnd_tracker/state/character_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('dnd_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('fromJson tolerates empty / malformed input', () {
    final c = Character.fromJson({'name': 5, 'hp': 'bad', 'items': [1, {}]});
    expect(c.name, '5');
    expect(c.items.length, 1);
    expect(c.spellSlots.length, 9);
    expect(Character.modifierFor(9), -1);
    expect(Character.modifierFor(18), 4);
  });

  test('weapons round trip and default to empty', () {
    expect(Character.fromJson({}).weapons, isEmpty);
    final c = Character.blank()..weapons.add(Weapon(name: 'Dagger', damage: '1d4'));
    final c2 = Character.fromJson(c.toJson());
    expect(c2.weapons.single.name, 'Dagger');
    expect(c2.weapons.single.damage, '1d4');
  });

  test('proficiencies round trip and default to empty', () {
    expect(Character.fromJson({}).proficiencies, isEmpty);
    final c = Character.blank()
      ..proficiencies.add(FeatureNote(name: 'Light armor'));
    expect(Character.fromJson(c.toJson()).proficiencies.single.name,
        'Light armor');
  });

  test('bio round trips and defaults to empty', () {
    expect(Character.fromJson({}).bio, '');
    final c = Character.blank()..bio = 'Raised by wolves.';
    expect(Character.fromJson(c.toJson()).bio, 'Raised by wolves.');
  });

  test('export then import (same id gets a fresh id, bad file rejected)',
      () async {
    final storage = StorageService(overrideDirectory: tmp);
    final c = Character.blank(name: 'Theren')..bio = 'Elf';
    await storage.save(c);
    final outDir = Directory.systemTemp.createTempSync('dnd_export');
    addTearDown(() => outDir.deleteSync(recursive: true));
    final out = '${outDir.path}${Platform.pathSeparator}shared';
    await storage.exportTo(c, out);
    expect(File('$out.json').existsSync(), isTrue);

    final imported = await storage.importFrom('$out.json', {c.id});
    expect(imported.id, isNot(c.id));
    expect(imported.name, 'Theren');
    expect(imported.bio, 'Elf');
    expect((await storage.loadAll()).length, 2);

    final bad = File('${outDir.path}${Platform.pathSeparator}bad.txt')
      ..writeAsStringSync('not json');
    expect(() => storage.importFrom(bad.path, {}),
        throwsA(isA<FormatException>()));
  });

  test('json round trip', () {
    final c = Character.blank(name: 'A')..abilities['INT'] = 18;
    final c2 = Character.fromJson(c.toJson());
    expect(c2.toJson(), c.toJson());
  });

  test('controller creates starter, autosaves, atomic write leaves no tmp',
      () async {
    final storage = StorageService(overrideDirectory: tmp);
    final ctrl = CharacterController(storage,
        saveDelay: const Duration(milliseconds: 20));
    await ctrl.load();
    expect(ctrl.characters.length, 1);
    ctrl.mutate((c) => c.name = 'Theren');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(ctrl.saveStatus, SaveStatus.saved);
    final reloaded = await storage.loadAll();
    expect(reloaded.single.name, 'Theren');
    expect(tmp.listSync().any((f) => f.path.endsWith('.tmp')), isFalse);
    await ctrl.duplicateActive();
    expect(ctrl.active!.name, 'Theren (Copy)');
    expect((await storage.loadAll()).length, 2);
  });
}
