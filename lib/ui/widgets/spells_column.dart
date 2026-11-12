import 'package:flutter/material.dart';

import '../../constants/dnd_constants.dart';
import '../../models/character.dart';
import '../../state/character_controller.dart';
import '../modals/spell_modal.dart';
import 'common.dart';

class SpellsColumn extends StatelessWidget {
  const SpellsColumn({super.key, required this.ctrl, required this.character});

  final CharacterController ctrl;
  final Character character;

  Future<void> _editMax(BuildContext context, int level) async {
    final slot = character.spellSlots[level]!;
    var value = slot.max;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Level $level max slots'),
        content: IntField(
            label: 'Max', value: value, onChanged: (v) => value = v),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      ctrl.mutate((_) {
        slot.max = value;
        if (slot.remaining > value) slot.remaining = value;
      });
    }
  }

  Widget _slotRow(BuildContext context, int level) {
    final slot = character.spellSlots[level]!;
    return Row(children: [
      SizedBox(width: 70, child: Text('Level $level')),
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.remove),
        onPressed: slot.remaining > 0
            ? () => ctrl.mutate((_) => slot.remaining--)
            : null,
      ),
      Text('${slot.remaining} / '),
      InkWell(
        onTap: () => _editMax(context, level),
        child: Tooltip(
          message: 'Click to edit max',
          child: Text('${slot.max}',
              style: TextStyle(
                  decoration: TextDecoration.underline,
                  color: Theme.of(context).colorScheme.primary)),
        ),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.add),
        onPressed: slot.remaining < slot.max
            ? () => ctrl.mutate((_) => slot.remaining++)
            : null,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = character;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _spellcasting(context, c),
        SectionCard(
          title: 'Spell Slots',
          child: Column(children: [
            for (var l = 1; l <= 9; l++) _slotRow(context, l),
          ]),
        ),
        SectionCard(
          title: 'Spells',
          trailing: TextButton.icon(
              onPressed: () => showSpellModal(context, ctrl),
              icon: const Icon(Icons.add),
              label: const Text('Add Spell')),
          child: c.spells.isEmpty
              ? const Text('No spells yet.')
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (var l = 0; l <= 9; l++)
                    ..._group(context, l),
                ]),
        ),
      ],
    );
  }

  Widget _spellcasting(BuildContext context, Character c) {
    String signed(int v) => v >= 0 ? '+$v' : '$v';
    Widget stat(String label, String value) => Column(children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]);
    return SectionCard(
      title: 'Spellcasting',
      child: Column(children: [
        DropdownButtonFormField<String>(
          key: ValueKey('sc-${c.id}'),
          initialValue: c.spellcastingAbility,
          decoration: const InputDecoration(
              labelText: 'Spellcasting Ability',
              isDense: true,
              border: OutlineInputBorder()),
          items: [
            for (final a in abilityNames)
              DropdownMenuItem(value: a, child: Text(a)),
          ],
          onChanged: (v) {
            if (v != null) ctrl.mutate((x) => x.spellcastingAbility = v);
          },
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          stat('Modifier', signed(c.spellcastingModifier)),
          stat('Spell Save DC', '${c.spellSaveDc}'),
          stat('Spell Attack', signed(c.spellAttackBonus)),
        ]),
      ]),
    );
  }

  List<Widget> _group(BuildContext context, int level) {
    final spells = character.spells.where((s) => s.level == level).toList();
    if (spells.isEmpty) return [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(level == 0 ? 'Cantrips' : 'Level $level',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary)),
      ),
      ReorderList(
        items: spells,
        idOf: (s) => s.id,
        onReorder: (o, n) => ctrl.mutate((x) {
          final moved = spells[o];
          x.spells.remove(moved);
          final rest = x.spells.where((s) => s.level == level).toList();
          if (n < rest.length) {
            x.spells.insert(x.spells.indexOf(rest[n]), moved);
          } else if (rest.isNotEmpty) {
            x.spells.insert(x.spells.indexOf(rest.last) + 1, moved);
          } else {
            x.spells.add(moved);
          }
        }),
        itemBuilder: (s) => ListTile(
          dense: true,
          title: Text(s.name),
          onTap: () => showSpellModal(context, ctrl, spell: s),
        ),
      ),
    ];
  }
}
