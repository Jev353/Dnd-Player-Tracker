import 'package:flutter/material.dart';

import '../../models/dice_roll_event.dart';
import '../../state/map_controller.dart';

/// Opens the dice roller. [rollerName] falls back to 'GM' / 'Player'.
Future<void> showDiceRollerDialog(
  BuildContext context, {
  required MapController mapController,
  String rollerName = '',
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        DiceRollerDialog(mapController: mapController, rollerName: rollerName),
  );
}

class DiceRollerDialog extends StatefulWidget {
  const DiceRollerDialog({
    super.key,
    required this.mapController,
    this.rollerName = '',
  });

  final MapController mapController;
  final String rollerName;

  @override
  State<DiceRollerDialog> createState() => _DiceRollerDialogState();
}

class _DiceRollerDialogState extends State<DiceRollerDialog> {
  static const List<int> _quick = [1, 2, 3, 4, 5, 6, 8, 10];

  int _die = 20;
  int _quantity = 1;
  DiceRollEvent? _last;

  String get _name {
    final n = widget.rollerName.trim();
    if (n.isNotEmpty) return n;
    return widget.mapController.isGM ? 'GM' : 'Player';
  }

  void _setQty(int q) => setState(() => _quantity = q.clamp(1, 20));

  Future<void> _roll() async {
    final e = await widget.mapController.rollDice(
      dieType: _die,
      quantity: _quantity,
      rollerName: _name,
    );
    if (mounted) setState(() => _last = e);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.casino_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          const Text('Roll Dice'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Die type'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in DiceRollEvent.allowedDice)
                    ChoiceChip(
                      key: ValueKey('die-$d'),
                      label: Text('d$d'),
                      selected: _die == d,
                      onSelected: (_) => setState(() => _die = d),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('How many dice'),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton.outlined(
                    key: const ValueKey('qty-minus'),
                    onPressed: _quantity > 1
                        ? () => _setQty(_quantity - 1)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '$_quantity',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton.outlined(
                    key: const ValueKey('qty-plus'),
                    onPressed: _quantity < 20
                        ? () => _setQty(_quantity + 1)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final q in _quick)
                    ChoiceChip(
                      key: ValueKey('qty-$q'),
                      label: Text('$q'),
                      selected: _quantity == q,
                      onSelected: (_) => _setQty(q),
                    ),
                ],
              ),
              if (_last != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.primary),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_last!.message, key: const ValueKey('last-roll')),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          key: const ValueKey('roll-button'),
          onPressed: _roll,
          icon: const Icon(Icons.casino_outlined),
          label: Text('Roll ${_quantity}d($_die)'),
        ),
      ],
    );
  }
}
