import 'package:flutter/material.dart';

import '../../models/character.dart';
import '../../state/character_controller.dart';
import '../modals/item_modal.dart';
import '../modals/note_modal.dart';
import '../modals/weapon_modal.dart';
import 'common.dart';

class InventoryColumn extends StatelessWidget {
  const InventoryColumn(
      {super.key, required this.ctrl, required this.character});

  final CharacterController ctrl;
  final Character character;

  static const _coinNames = {
    'cp': 'Copper',
    'sp': 'Silver',
    'ep': 'Electrum',
    'gp': 'Gold',
    'pp': 'Platinum',
  };

  @override
  Widget build(BuildContext context) {
    final c = character;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        SectionCard(
          title: 'Currency',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in Character.currencyKeys)
              IntField(
                  key: ValueKey('cur-$k-${c.id}'),
                  label: '${k.toUpperCase()} (${_coinNames[k]})',
                  width: 110,
                  value: c.currency[k] ?? 0,
                  onChanged: (v) => ctrl.mutate((x) => x.currency[k] = v)),
          ]),
        ),
        SectionCard(
          title: 'Weapons',
          trailing: TextButton.icon(
              onPressed: () => showWeaponModal(context, ctrl),
              icon: const Icon(Icons.add),
              label: const Text('Add Weapon')),
          child: c.weapons.isEmpty
              ? const Text('No weapons yet.')
              : ReorderList(
                  items: c.weapons,
                  idOf: (w) => w.id,
                  onReorder: (o, n) => ctrl.mutate(
                      (x) => x.weapons.insert(n, x.weapons.removeAt(o))),
                  itemBuilder: (w) => ListTile(
                    dense: true,
                    title: Text(w.name),
                    trailing: Text('x${w.amount}'),
                    subtitle: (w.attackBonus.isEmpty && w.damage.isEmpty)
                        ? null
                        : Text([
                            if (w.attackBonus.isNotEmpty)
                              '${w.attackBonus} to hit',
                            if (w.damage.isNotEmpty) w.damage,
                          ].join(' · ')),
                    onTap: () => showWeaponModal(context, ctrl, weapon: w),
                  ),
                ),
        ),
        SectionCard(
          title: 'Items',
          trailing: TextButton.icon(
              onPressed: () => showItemModal(context, ctrl),
              icon: const Icon(Icons.add),
              label: const Text('Add Item')),
          child: c.items.isEmpty
              ? const Text('No items yet.')
              : ReorderList(
                  items: c.items,
                  idOf: (i) => i.id,
                  onReorder: (o, n) => ctrl
                      .mutate((x) => x.items.insert(n, x.items.removeAt(o))),
                  itemBuilder: (item) => ListTile(
                    dense: true,
                    title: Text(item.name),
                    trailing: Text('x${item.amount}'),
                    onTap: () => showItemModal(context, ctrl, item: item),
                  ),
                ),
        ),
        SectionCard(
          title: 'Proficiencies',
          trailing: TextButton.icon(
              onPressed: () =>
                  showNoteModal(context, ctrl, proficiency: true),
              icon: const Icon(Icons.add),
              label: const Text('Add Proficiency')),
          child: c.proficiencies.isEmpty
              ? const Text('No proficiencies yet.')
              : ReorderList(
                  items: c.proficiencies,
                  idOf: (p) => p.id,
                  onReorder: (o, n) => ctrl.mutate((x) =>
                      x.proficiencies.insert(n, x.proficiencies.removeAt(o))),
                  itemBuilder: (p) => ListTile(
                    dense: true,
                    title: Text(p.name),
                    onTap: () => showNoteModal(context, ctrl,
                        note: p, proficiency: true),
                  ),
                ),
        ),
        SectionCard(
          title: 'Features & Notes',
          trailing: TextButton.icon(
              onPressed: () => showNoteModal(context, ctrl),
              icon: const Icon(Icons.add),
              label: const Text('Add Note')),
          child: c.featuresAndNotes.isEmpty
              ? const Text('No features or notes yet.')
              : ReorderList(
                  items: c.featuresAndNotes,
                  idOf: (n) => n.id,
                  onReorder: (o, n) => ctrl.mutate((x) => x.featuresAndNotes
                      .insert(n, x.featuresAndNotes.removeAt(o))),
                  itemBuilder: (n) => ListTile(
                    dense: true,
                    title: Text(n.name),
                    onTap: () => showNoteModal(context, ctrl, note: n),
                  ),
                ),
        ),
      ],
    );
  }
}
