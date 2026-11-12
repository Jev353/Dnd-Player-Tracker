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

/// Creates a blank character with default stats.
Character defaultCharacter({String name = 'New Character'}) {
  return Character.blank(name: name);
}
