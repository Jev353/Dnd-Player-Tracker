import 'json_helpers.dart';

class SpellSlot {
  int remaining;
  int max;

  SpellSlot({this.remaining = 0, this.max = 0});

  factory SpellSlot.fromJson(Map<String, dynamic> json) {
    final max = readInt(json['max'], 0);
    return SpellSlot(remaining: readInt(json['remaining'], max), max: max);
  }

  Map<String, dynamic> toJson() => {'remaining': remaining, 'max': max};
}

class Spell {
  String id;
  String name;
  int level;
  String castingTime;
  String range;
  String duration;
  String components;
  String damage;
  String description;

  Spell({
    String? id,
    this.name = '',
    this.level = 0,
    this.castingTime = '',
    this.range = '',
    this.duration = '',
    this.components = '',
    this.damage = '',
    this.description = '',
  }) : id = id ?? newId();

  factory Spell.fromJson(Map<String, dynamic> json) => Spell(
    id: readString(json['id'], newId()),
    name: readString(json['name'], 'Unnamed Spell'),
    level: readInt(json['level'], 0).clamp(0, 9),
    castingTime: readString(json['castingTime'], ''),
    range: readString(json['range'], ''),
    duration: readString(json['duration'], ''),
    components: readString(json['components'], ''),
    damage: readString(json['damage'], ''),
    description: readString(json['description'], ''),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'level': level,
    'castingTime': castingTime,
    'range': range,
    'duration': duration,
    'components': components,
    'damage': damage,
    'description': description,
  };
}
