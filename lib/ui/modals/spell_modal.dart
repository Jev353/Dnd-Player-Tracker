import 'package:flutter/material.dart';

import '../../models/spell.dart';
import '../../state/character_controller.dart';
import '../widgets/common.dart';

/// Opens the spell dialog. Pass [spell] to view it, or null to create one.
Future<void> showSpellModal(BuildContext context, CharacterController ctrl,
    {Spell? spell}) {
  return showDialog(
    context: context,
    builder: (_) => _SpellDialog(ctrl: ctrl, spell: spell),
  );
}

String levelLabel(int level) => level == 0 ? 'Cantrip' : 'Level $level';

void _copySpell(Spell from, Spell to) {
  to
    ..name = from.name.trim()
    ..level = from.level
    ..castingTime = from.castingTime
    ..range = from.range
    ..duration = from.duration
    ..components = from.components
    ..damage = from.damage
    ..description = from.description;
}

class _SpellDialog extends StatefulWidget {
  const _SpellDialog({required this.ctrl, this.spell});
  final CharacterController ctrl;
  final Spell? spell;

  @override
  State<_SpellDialog> createState() => _SpellDialogState();
}

class _SpellDialogState extends State<_SpellDialog> {
  late bool _editing = widget.spell == null;
  late final Spell _draft = Spell();
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.spell != null) _copySpell(widget.spell!, _draft);
  }

  void _save() {
    if (_draft.name.trim().isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final existing = widget.spell;
    widget.ctrl.mutate((c) {
      if (existing == null) {
        final s = Spell();
        _copySpell(_draft, s);
        c.spells.add(s);
      } else {
        _copySpell(_draft, existing);
      }
    });
    if (existing == null) {
      Navigator.pop(context);
    } else {
      setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spell = widget.spell;
    return AlertDialog(
      title: Text(spell == null
          ? 'Add Spell'
          : (_editing ? 'Edit Spell' : spell.name)),
      content: SizedBox(
        width: 520,
        child: _editing ? _form() : _view(spell!),
      ),
      actions: _editing
          ? [
              TextButton(
                onPressed: () {
                  if (spell == null) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      _editing = false;
                      _copySpell(spell, _draft);
                      _error = null;
                    });
                  }
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                  onPressed: _save,
                  child: Text(spell == null ? 'Save' : 'Save Changes')),
            ]
          : [
              TextButton(
                onPressed: () {
                  widget.ctrl.mutate((c) => c.spells.remove(spell));
                  Navigator.pop(context);
                },
                child: const Text('Delete'),
              ),
              OutlinedButton(
                  onPressed: () => setState(() => _editing = true),
                  child: const Text('Edit')),
              FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close')),
            ],
    );
  }

  Widget _form() => SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 4),
          TextCommitField(
              label: 'Spell Name',
              value: _draft.name,
              onChanged: (v) => _draft.name = v),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _draft.level,
            decoration: const InputDecoration(
                labelText: 'Spell Level',
                isDense: true,
                border: OutlineInputBorder()),
            items: [
              for (var l = 0; l <= 9; l++)
                DropdownMenuItem(
                    value: l, child: Text(l == 0 ? '0 (Cantrip)' : '$l')),
            ],
            onChanged: (v) => _draft.level = v ?? 0,
          ),
          const SizedBox(height: 12),
          TextCommitField(
              label: 'Casting Time',
              value: _draft.castingTime,
              onChanged: (v) => _draft.castingTime = v),
          const SizedBox(height: 12),
          TextCommitField(
              label: 'Range',
              value: _draft.range,
              onChanged: (v) => _draft.range = v),
          const SizedBox(height: 12),
          TextCommitField(
              label: 'Duration',
              value: _draft.duration,
              onChanged: (v) => _draft.duration = v),
          const SizedBox(height: 12),
          TextCommitField(
              label: 'Components',
              value: _draft.components,
              onChanged: (v) => _draft.components = v),
          const SizedBox(height: 12),
          TextCommitField(
              label: 'Damage (e.g. 8d6 fire)',
              value: _draft.damage,
              onChanged: (v) => _draft.damage = v),
          const SizedBox(height: 12),
          TextCommitField(
              label: 'Description',
              value: _draft.description,
              maxLines: 6,
              onChanged: (v) => _draft.description = v),
        ]),
      );

  Widget _meta(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: SelectableText(value.isEmpty ? '-' : value)),
        ]),
      );

  Widget _view(Spell s) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Chip(label: Text(levelLabel(s.level))),
          const SizedBox(height: 8),
          _meta('Casting Time', s.castingTime),
          _meta('Range', s.range),
          _meta('Duration', s.duration),
          _meta('Components', s.components),
          _meta('Damage', s.damage),
          const Divider(),
          Flexible(
            child: SingleChildScrollView(
              child: SelectableText(
                  s.description.isEmpty ? 'No description.' : s.description),
            ),
          ),
        ],
      );
}
