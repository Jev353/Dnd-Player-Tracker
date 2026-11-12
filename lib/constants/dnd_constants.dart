import '../models/character.dart';

const List<String> abilityNames = ['STR', 'DEX', 'CON', 'INT', 'WIS', 'CHA'];

/// Skill name -> linked ability (standard 5e mapping).
const Map<String, String> skillAbilities = {
  'Acrobatics': 'DEX',
  'Animal Handling': 'WIS',
  'Arcana': 'INT',
  'Athletics': 'STR',
  'Deception': 'CHA',
  'History': 'INT',
  'Insight': 'WIS',
  'Intimidation': 'CHA',
  'Investigation': 'INT',
  'Medicine': 'WIS',
  'Nature': 'INT',
  'Perception': 'WIS',
  'Performance': 'CHA',
  'Persuasion': 'CHA',
  'Religion': 'INT',
  'Sleight of Hand': 'DEX',
  'Stealth': 'DEX',
  'Survival': 'WIS',
};

List<String> get skillNames => skillAbilities.keys.toList();

const int maxExhaustion = 6;

/// Effects at each exhaustion level (2024 / 5.5e Player's Handbook).
/// Each level: D20 Tests -2 per level, Speed -5 ft per level; level 6 = death.
String exhaustionEffect(int level) {
  if (level <= 0) return 'No exhaustion.';
  if (level >= maxExhaustion) {
    return 'Level 6: You die.';
  }
  return 'Level $level: D20 Tests (attack rolls, ability checks, saving '
      'throws) are reduced by ${level * 2}. Speed is reduced by '
      '${level * 5} feet. A Long Rest removes 1 level of exhaustion.';
}

/// Creates a blank character with default stats.
Character defaultCharacter({String name = 'New Character'}) {
  return Character.blank(name: name);
}
