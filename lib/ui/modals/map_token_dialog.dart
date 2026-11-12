import 'package:flutter/material.dart';

import '../../models/map_token.dart';

const _tokenColors = <String, Color>{
  '#D4AF37': Color(0xFFD4AF37),
  '#E57373': Color(0xFFE57373),
  '#64B5F6': Color(0xFF64B5F6),
  '#81C784': Color(0xFF81C784),
  '#BA68C8': Color(0xFFBA68C8),
  '#FFFFFF': Color(0xFFFFFFFF),
};

/// Collects label, size, color and starting visibility for a Monster/NPC.
class AddTokenDialog extends StatefulWidget {
  const AddTokenDialog({super.key});

  @override
  State<AddTokenDialog> createState() => _AddTokenDialogState();
}

class _AddTokenDialogState extends State<AddTokenDialog> {
  final _label = TextEditingController();
  double _size = 1.0;
  String _color = '#E57373';
  bool _hidden = true;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AlertDialog(
      title: const Text('Add Monster/NPC Token'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _label,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<double>(
              initialValue: _size,
              decoration: const InputDecoration(
                labelText: 'Size (grid squares)',
              ),
              items: const [
                DropdownMenuItem(value: 0.5, child: Text('Tiny (0.5)')),
                DropdownMenuItem(value: 1.0, child: Text('Medium (1)')),
                DropdownMenuItem(value: 2.0, child: Text('Large (2)')),
                DropdownMenuItem(value: 3.0, child: Text('Huge (3)')),
                DropdownMenuItem(value: 4.0, child: Text('Gargantuan (4)')),
              ],
              onChanged: (v) => setState(() => _size = v ?? _size),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final e in _tokenColors.entries)
                  GestureDetector(
                    onTap: () => setState(() => _color = e.key),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: e.value,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == e.key ? primary : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start hidden from players'),
              value: _hidden,
              onChanged: (v) => setState(() => _hidden = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            MapToken(
              label: _label.text.trim().isEmpty ? 'NPC' : _label.text.trim(),
              size: _size,
              colorHex: _color,
              visibleToPlayers: !_hidden,
            ),
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
