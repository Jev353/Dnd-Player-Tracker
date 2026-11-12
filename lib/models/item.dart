import 'json_helpers.dart';

class InventoryItem {
  String id;
  String name;
  int amount;
  String description;

  InventoryItem({
    String? id,
    this.name = '',
    this.amount = 1,
    this.description = '',
  }) : id = id ?? newId();

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
    id: readString(json['id'], newId()),
    name: readString(json['name'], 'Unnamed Item'),
    amount: readInt(json['amount'], 1),
    description: readString(json['description'], ''),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'description': description,
  };
}
