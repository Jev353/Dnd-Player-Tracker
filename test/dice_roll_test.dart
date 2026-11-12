import 'package:dnd_tracker/models/dice_roll_event.dart';
import 'package:dnd_tracker/state/map_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DiceRollEvent json round trip and message', () {
    final e = DiceRollEvent(
      id: 'a',
      rollerName: 'Flint',
      dieType: 20,
      quantity: 1,
      results: const [16],
      total: 16,
      timestamp: DateTime.utc(2024, 1, 1),
    );
    final back = DiceRollEvent.fromJson(e.toJson());
    expect(back.id, 'a');
    expect(back.results, [16]);
    expect(back.timestamp, e.timestamp);
    expect(back.message, 'Flint rolled a d(20) and got a 16');
    final many = DiceRollEvent(
      id: 'b',
      rollerName: 'Flint',
      dieType: 6,
      quantity: 3,
      results: const [1, 2, 3],
      total: 6,
      timestamp: DateTime.utc(2024, 1, 1),
    );
    expect(many.message, 'Flint rolled 3d(6) and got a 6 (1, 2, 3)');
  });

  test('rollDice stays in bounds and fills toasts', () async {
    final c = MapController();
    addTearDown(c.dispose);
    for (final d in DiceRollEvent.allowedDice) {
      for (var i = 0; i < 50; i++) {
        final e = await c.rollDice(dieType: d, quantity: 5, rollerName: 'F');
        expect(e.results.length, 5);
        expect(e.results.every((r) => r >= 1 && r <= d), isTrue);
        expect(e.total, e.results.reduce((a, b) => a + b));
      }
    }
    expect(c.activeRollToasts.length, 4);
    final one = await c.rollDice(dieType: 20, rollerName: 'F');
    expect(one.quantity, 1);
    expect(c.activeRollToasts.last.id, one.id);
  });
}
