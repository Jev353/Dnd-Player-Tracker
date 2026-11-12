import 'json_helpers.dart';

class Weapon {
  String id;
  String name;
  int amount;
  String attackBonus;
  String damage;
  String damageType;
  String range;
  String properties;
  String description;

  Weapon({
    String? id,
    this.name = '',
    this.amount = 1,
    this.attackBonus = '',
    this.damage = '',
    this.damageType = '',
    this.range = '',
    this.properties = '',
    this.description = '',
  }) : id = id ?? newId();

  factory Weapon.fromJson(Map<String, dynamic> json) => Weapon(
    id: readString(json['id'], newId()),
    name: readString(json['name'], 'Unnamed Weapon'),
    amount: readInt(json['amount'], 1),
    attackBonus: readString(json['attackBonus'], ''),
    damage: readString(json['damage'], ''),
    damageType: readString(json['damageType'], ''),
    range: readString(json['range'], ''),
    properties: readString(json['properties'], ''),
    description: readString(json['description'], ''),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'attackBonus': attackBonus,
    'damage': damage,
    'damageType': damageType,
    'range': range,
    'properties': properties,
    'description': description,
  };
}
