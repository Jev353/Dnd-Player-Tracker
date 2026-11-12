import 'package:flutter/material.dart';

import '../../models/weapon.dart';
import '../../state/character_controller.dart';
import '../widgets/common.dart';

/// Opens the weapon dialog. Pass [weapon] to view it, or null to create one.
Future<void> showWeaponModal(BuildContext context, CharacterController ctrl,
    {Weapon? weapon}) {
  return showDialog(
    context: context,
    builder: (_) => _WeaponDialog(ctrl: ctrl, weapon: weapon),
  );
}

void _copyWeapon(Weapon from, Weapon to) {
  to
    ..name = from.name.trim()
    ..attackBonus = from.attackBonus
    ..damage = from.damage
    ..damageType = from.damageType
    ..range = from.range
    ..properties = from.properties
    ..description = from.description;
}

class _WeaponDialog extends StatefulWidget {
  const _WeaponDialog({required this.ctrl, this.weapon});
  final CharacterController ctrl;
  final Weapon? weapon;

  @override
  State<_WeaponDialog> createState() => _WeaponDialogState();
}

class _WeaponDialogState extends State<_WeaponDialog> {
  late bool _editing = widget.weapon == null;
  final Weapon _draft = Weapon();
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.weapon != null) _copyWeapon(widget.weapon!, _draft);
  }

  void _save() {
    if (_draft.name.trim().isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final existing = widget.weapon;
    widget.ctrl.mutate((c) {
      if (existing == null) {
        final w = Weapon();
        _copyWeapon(_draft, w);
        c.weapons.add(w);
      } else {
        _copyWeapon(_draft, existing);
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
    final weapon = widget.weapon;
    return AlertDialog(
      title: Text(weapon == null
          ? 'Add Weapon'
          : (_editing ? 'Edit Weapon' : weapon.name)),
      content: SizedBox(
        width: 520,
        child: _editing ? _form() : _view(weapon!),
      ),
      actions: _editing
          ? [
              TextButton(
                onPressed: () {
                  if (weapon == null) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      _editing = false;
                      _copyWeapon(weapon, _draft);
                      _error = null;
                    });
                  }
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                  onPressed: _save,
                  child: Text(weapon == null ? 'Save' : 'Save Changes')),
            ]
          : [
              TextButton(
                onPressed: () {
                  widget.ctrl.mutate((c) => c.weapons.remove(weapon));
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

  Widget _field(String label, String value, ValueChanged<String> onChanged,
          {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextCommitField(
            label: label,
            value: value,
            maxLines: maxLines,
            onChanged: onChanged),
      );

  Widget _form() => SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 4),
          TextCommitField(
              label: 'Weapon Name',
              value: _draft.name,
              onChanged: (v) => _draft.name = v),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          _field('Attack Bonus (e.g. +5)', _draft.attackBonus,
              (v) => _draft.attackBonus = v),
          _field('Damage (e.g. 1d8 + 3)', _draft.damage,
              (v) => _draft.damage = v),
          _field('Damage Type (e.g. slashing)', _draft.damageType,
              (v) => _draft.damageType = v),
          _field('Range (e.g. 5 ft / 80-320 ft)', _draft.range,
              (v) => _draft.range = v),
          _field('Properties (e.g. Finesse, Light)', _draft.properties,
              (v) => _draft.properties = v),
          _field('Description', _draft.description,
              (v) => _draft.description = v,
              maxLines: 6),
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

  Widget _view(Weapon w) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _meta('Attack Bonus', w.attackBonus),
          _meta('Damage', w.damage),
          _meta('Damage Type', w.damageType),
          _meta('Range', w.range),
          _meta('Properties', w.properties),
          const Divider(),
          Flexible(
            child: SingleChildScrollView(
              child: SelectableText(
                  w.description.isEmpty ? 'No description.' : w.description),
            ),
          ),
        ],
      );
}
