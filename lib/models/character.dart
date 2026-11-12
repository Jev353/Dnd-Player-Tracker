import '../constants/dnd_constants.dart';
import 'feature_note.dart';
import 'item.dart';
import 'json_helpers.dart';
import 'spell.dart';
import 'weapon.dart';

class Character {
  String id;
  String name;
  String characterClass;
  String bio;
  int level;
  int proficiencyBonus;
  int armorClass;
  int initiative;
  int speed;

  int hpCurrent;
  int hpMax;
  int hpTemp;

  String hitDiceTotal;
  int hitDiceRemaining;

  int deathSaveSuccesses;
  int deathSaveFailures;

  /// Ability used for spellcasting (one of STR..CHA).
  String spellcastingAbility;

  Map<String, int> abilities;
  Map<String, bool> savingThrowProficiencies;
  Map<String, bool> skillProficiencies;
  Map<String, bool> skillExpertise;
  Map<String, int> currency;

  List<Weapon> weapons;
  List<InventoryItem> items;
  List<FeatureNote> featuresAndNotes;
  List<FeatureNote> proficiencies;
  Map<int, SpellSlot> spellSlots;
  List<Spell> spells;

  Character({
    String? id,
    this.name = 'New Character',
    this.characterClass = '',
    this.bio = '',
    this.level = 1,
    this.proficiencyBonus = 2,
    this.armorClass = 10,
    this.initiative = 0,
    this.speed = 30,
    this.hpCurrent = 10,
    this.hpMax = 10,
    this.hpTemp = 0,
    this.hitDiceTotal = '1d8',
    this.hitDiceRemaining = 1,
    this.deathSaveSuccesses = 0,
    this.deathSaveFailures = 0,
    this.spellcastingAbility = 'INT',
    required this.abilities,
    required this.savingThrowProficiencies,
    required this.skillProficiencies,
    Map<String, bool>? skillExpertise,
    required this.currency,
    List<Weapon>? weapons,
    List<InventoryItem>? items,
    List<FeatureNote>? featuresAndNotes,
    List<FeatureNote>? proficiencies,
    required this.spellSlots,
    List<Spell>? spells,
  })  : id = id ?? newId(),
        skillExpertise = skillExpertise ?? {for (final s in skillNames) s: false},
        weapons = weapons ?? [],
        items = items ?? [],
        featuresAndNotes = featuresAndNotes ?? [],
        proficiencies = proficiencies ?? [],
        spells = spells ?? [];

  static const List<String> currencyKeys = ['cp', 'sp', 'ep', 'gp', 'pp'];

  factory Character.blank({String name = 'New Character'}) => Character(
        name: name,
        abilities: {for (final a in abilityNames) a: 10},
        savingThrowProficiencies: {for (final a in abilityNames) a: false},
        skillProficiencies: {for (final s in skillNames) s: false},
        currency: {for (final c in currencyKeys) c: 0},
        spellSlots: {for (var l = 1; l <= 9; l++) l: SpellSlot()},
      );

  // ---- Derived math ----
  static int modifierFor(int score) => ((score - 10) / 2).floor();

  int abilityModifier(String ability) => modifierFor(abilities[ability] ?? 10);

  int savingThrowTotal(String ability) =>
      abilityModifier(ability) +
      ((savingThrowProficiencies[ability] ?? false) ? proficiencyBonus : 0);

  int skillTotal(String skill) {
    final ability = skillAbilities[skill] ?? 'STR';
    final proficient = skillProficiencies[skill] ?? false;
    final expert = proficient && (skillExpertise[skill] ?? false);
    return abilityModifier(ability) +
        (expert ? proficiencyBonus * 2 : (proficient ? proficiencyBonus : 0));
  }

  /// Expertise is only offered to Rogues (also accepts the "Rouge" spelling).
  bool get isRogue {
    final cls = characterClass.trim().toLowerCase();
    return cls.contains('rogue') || cls.contains('rouge');
  }

  int get spellcastingModifier => abilityModifier(spellcastingAbility);
  int get spellSaveDc => 8 + proficiencyBonus + spellcastingModifier;
  int get spellAttackBonus => proficiencyBonus + spellcastingModifier;

  /// Deep copy via serialization, with a new id.
  Character duplicate() {
    final copy = Character.fromJson(toJson());
    copy.id = newId();
    copy.name = '$name (Copy)';
    return copy;
  }

  /// Long rest: restore HP, clear temp HP, restore slots, reset death saves.
  void longRest() {
    hpCurrent = hpMax;
    hpTemp = 0;
    for (final s in spellSlots.values) {
      s.remaining = s.max;
    }
    deathSaveSuccesses = 0;
    deathSaveFailures = 0;
  }

  // ---- Serialization ----
  factory Character.fromJson(Map<String, dynamic> json) {
    final hp = readMap(json['hp']);
    final hitDice = readMap(json['hitDice']);
    final death = readMap(json['deathSaves']);
    final abil = readMap(json['abilities']);
    final saves = readMap(json['savingThrowProficiencies']);
    final skills = readMap(json['skillProficiencies']);
    final cur = readMap(json['currency']);
    final slots = readMap(json['spellSlots']);

    final hpMax = readInt(hp['max'], 10);

    return Character(
      id: readString(json['id'], newId()),
      name: readString(json['name'], 'Unnamed Character'),
      characterClass: readString(json['characterClass'], ''),
      bio: readString(json['bio'], ''),
      level: readInt(json['level'], 1),
      proficiencyBonus: readInt(json['proficiencyBonus'], 2),
      armorClass: readInt(json['armorClass'], 10),
      initiative: readInt(json['initiative'], 0),
      speed: readInt(json['speed'], 30),
      hpCurrent: readInt(hp['current'], hpMax),
      hpMax: hpMax,
      hpTemp: readInt(hp['temp'], 0),
      hitDiceTotal: readString(hitDice['total'], '1d8'),
      hitDiceRemaining: readInt(hitDice['remaining'], 1),
      deathSaveSuccesses: readInt(death['successes'], 0),
      deathSaveFailures: readInt(death['failures'], 0),
      spellcastingAbility: abilityNames.contains(json['spellcastingAbility'])
          ? json['spellcastingAbility'] as String
          : 'INT',
      abilities: {for (final a in abilityNames) a: readInt(abil[a], 10)},
      savingThrowProficiencies: {
        for (final a in abilityNames) a: readBool(saves[a], false),
      },
      skillProficiencies: {
        for (final s in skillNames) s: readBool(skills[s], false),
      },
      skillExpertise: {
        for (final s in skillNames)
          s: readBool(readMap(json['skillExpertise'])[s], false),
      },
      currency: {for (final c in currencyKeys) c: readInt(cur[c], 0)},
      weapons: readList(json['weapons'])
          .whereType<Map>()
          .map((e) => Weapon.fromJson(readMap(e)))
          .toList(),
      items: readList(json['items'])
          .whereType<Map>()
          .map((e) => InventoryItem.fromJson(readMap(e)))
          .toList(),
      featuresAndNotes: readList(json['featuresAndNotes'])
          .whereType<Map>()
          .map((e) => FeatureNote.fromJson(readMap(e)))
          .toList(),
      proficiencies: readList(json['proficiencies'])
          .whereType<Map>()
          .map((e) => FeatureNote.fromJson(readMap(e)))
          .toList(),
      spellSlots: {
        for (var l = 1; l <= 9; l++)
          l: slots['$l'] is Map
              ? SpellSlot.fromJson(readMap(slots['$l']))
              : SpellSlot(),
      },
      spells: readList(json['spells'])
          .whereType<Map>()
          .map((e) => Spell.fromJson(readMap(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'characterClass': characterClass,
        'bio': bio,
        'level': level,
        'proficiencyBonus': proficiencyBonus,
        'armorClass': armorClass,
        'initiative': initiative,
        'speed': speed,
        'hp': {'current': hpCurrent, 'max': hpMax, 'temp': hpTemp},
        'hitDice': {'total': hitDiceTotal, 'remaining': hitDiceRemaining},
        'deathSaves': {
          'successes': deathSaveSuccesses,
          'failures': deathSaveFailures,
        },
        'spellcastingAbility': spellcastingAbility,
        'abilities': abilities,
        'savingThrowProficiencies': savingThrowProficiencies,
        'skillProficiencies': skillProficiencies,
        'skillExpertise': skillExpertise,
        'currency': currency,
        'weapons': weapons.map((e) => e.toJson()).toList(),
        'items': items.map((e) => e.toJson()).toList(),
        'featuresAndNotes': featuresAndNotes.map((e) => e.toJson()).toList(),
        'proficiencies': proficiencies.map((e) => e.toJson()).toList(),
        'spellSlots': {
          for (final e in spellSlots.entries) '${e.key}': e.value.toJson(),
        },
        'spells': spells.map((e) => e.toJson()).toList(),
      };
}
