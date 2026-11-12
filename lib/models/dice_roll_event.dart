import 'json_helpers.dart';

/// One dice roll, broadcast to the party and shown as a toast.
class DiceRollEvent {
  const DiceRollEvent({
    required this.id,
    required this.rollerName,
    required this.dieType,
    required this.quantity,
    required this.results,
    required this.total,
    required this.timestamp,
  });

  static const List<int> allowedDice = [2, 4, 6, 8, 10, 12, 20];

  final String id;
  final String rollerName;
  final int dieType;
  final int quantity;
  final List<int> results;
  final int total;
  final DateTime timestamp;

  String get message => quantity == 1
      ? '$rollerName rolled a d($dieType) and got a $total'
      : '$rollerName rolled ${quantity}d($dieType) and got a $total (${results.join(", ")})';

  Map<String, dynamic> toJson() => {
    'id': id,
    'rollerName': rollerName,
    'dieType': dieType,
    'quantity': quantity,
    'results': results,
    'total': total,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };

  factory DiceRollEvent.fromJson(Map<String, dynamic> json) {
    final results = readList(
      json['results'],
    ).map((e) => readInt(e, 0)).toList();
    return DiceRollEvent(
      id: readString(json['id'], newId()),
      rollerName: readString(json['rollerName'], 'Player'),
      dieType: readInt(json['dieType'], 20),
      quantity: readInt(json['quantity'], results.isEmpty ? 1 : results.length),
      results: results,
      total: readInt(json['total'], results.fold<int>(0, (a, b) => a + b)),
      timestamp:
          DateTime.tryParse(readString(json['timestamp'], '')) ??
          DateTime.now(),
    );
  }
}
