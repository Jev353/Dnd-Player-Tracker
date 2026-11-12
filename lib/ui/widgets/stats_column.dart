import 'package:flutter/material.dart';

import '../../constants/dnd_constants.dart';
import '../../models/character.dart';
import '../../state/character_controller.dart';
import '../modals/bio_modal.dart';
import 'common.dart';

String signed(int v) => v >= 0 ? '+$v' : '$v';

class StatsColumn extends StatelessWidget {
  const StatsColumn({super.key, required this.ctrl, required this.character});

  final CharacterController ctrl;
  final Character character;

  @override
  Widget build(BuildContext context) {
    final c = character;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _identity(c),
        _combat(c),
        _HpCard(ctrl: ctrl, c: c),
        _abilities(c),
        _saves(c),
        _skills(c),
      ],
    );
  }

  Widget _identity(Character c) => SectionCard(
        title: 'Character',
        child: Column(children: [
          TextCommitField(
              key: ValueKey('name-${c.id}'),
              label: 'Name',
              value: c.name,
              onChanged: (v) => ctrl.mutate((x) => x.name = v)),
          Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (context) => TextButton.icon(
                onPressed: () => showBioModal(context, ctrl),
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: Text(c.bio.trim().isEmpty ? 'Add Bio' : 'View / Edit Bio'),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
              width: 180,
              child: TextCommitField(
                  key: ValueKey('class-${c.id}'),
                  label: 'Class',
                  value: c.characterClass,
                  onChanged: (v) => ctrl.mutate((x) => x.characterClass = v)),
            ),
            IntField(
                key: ValueKey('level-${c.id}'),
                label: 'Level',
                value: c.level,
                onChanged: (v) => ctrl.mutate((x) => x.level = v)),
            IntField(
                key: ValueKey('prof-${c.id}'),
                label: 'Prof. Bonus',
                width: 100,
                value: c.proficiencyBonus,
                onChanged: (v) => ctrl.mutate((x) => x.proficiencyBonus = v)),
          ]),
        ]),
      );

  Widget _combat(Character c) => SectionCard(
        title: 'Combat',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          IntField(
              key: ValueKey('ac-${c.id}'),
              label: 'Armor Class',
              width: 110,
              value: c.armorClass,
              onChanged: (v) => ctrl.mutate((x) => x.armorClass = v)),
          IntField(
              key: ValueKey('init-${c.id}'),
              label: 'Initiative',
              value: c.initiative,
              allowNegative: true,
              onChanged: (v) => ctrl.mutate((x) => x.initiative = v)),
          IntField(
              key: ValueKey('speed-${c.id}'),
              label: 'Speed',
              value: c.speed,
              onChanged: (v) => ctrl.mutate((x) => x.speed = v)),
        ]),
      );

  Widget _abilities(Character c) => SectionCard(
        title: 'Abilities',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in abilityNames)
            SizedBox(
              width: 96,
              child: Column(children: [
                Text(a, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(signed(c.abilityModifier(a)),
                    style: const TextStyle(fontSize: 22)),
                IntField(
                    key: ValueKey('abil-$a-${c.id}'),
                    label: 'Score',
                    value: c.abilities[a] ?? 10,
                    onChanged: (v) => ctrl.mutate((x) => x.abilities[a] = v)),
              ]),
            ),
        ]),
      );

  Widget _saves(Character c) => SectionCard(
        title: 'Saving Throws',
        child: Column(children: [
          for (final a in abilityNames)
            _profRow(
              label: a,
              total: c.savingThrowTotal(a),
              value: c.savingThrowProficiencies[a] ?? false,
              onChanged: (v) =>
                  ctrl.mutate((x) => x.savingThrowProficiencies[a] = v),
            ),
        ]),
      );

  Widget _skills(Character c) => SectionCard(
        title: 'Skills',
        child: Column(children: [
          for (final s in skillNames)
            _profRow(
              label: '$s (${skillAbilities[s]})',
              total: c.skillTotal(s),
              value: c.skillProficiencies[s] ?? false,
              onChanged: (v) => ctrl.mutate((x) {
                x.skillProficiencies[s] = v;
                if (!v) x.skillExpertise[s] = false;
              }),
              showExpertise: c.isRogue,
              expertise: c.skillExpertise[s] ?? false,
              onExpertiseChanged: (v) =>
                  ctrl.mutate((x) => x.skillExpertise[s] = v),
            ),
        ]),
      );

  Widget _profRow({
    required String label,
    required int total,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool showExpertise = false,
    bool expertise = false,
    ValueChanged<bool>? onExpertiseChanged,
  }) =>
      InkWell(
        onTap: () => onChanged(!value),
        child: Row(children: [
          Checkbox(
              value: value,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => onChanged(v ?? false)),
          SizedBox(
              width: 36,
              child: Text(signed(total),
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(label)),
          if (showExpertise && value)
            Tooltip(
              message: 'Expertise (double proficiency)',
              child: FilterChip(
                label: const Text('Expertise'),
                visualDensity: VisualDensity.compact,
                selected: expertise,
                onSelected: (v) => onExpertiseChanged?.call(v),
              ),
            ),
        ]),
      );
}

class _HpCard extends StatefulWidget {
  const _HpCard({required this.ctrl, required this.c});
  final CharacterController ctrl;
  final Character c;

  @override
  State<_HpCard> createState() => _HpCardState();
}

class _HpCardState extends State<_HpCard> {
  int _amount = 1;

  void _heal() => widget.ctrl.mutate((c) {
        c.hpCurrent = (c.hpCurrent + _amount).clamp(0, c.hpMax);
      });

  /// Damage drains temp HP first, then current HP (never below 0).
  void _damage() => widget.ctrl.mutate((c) {
        var dmg = _amount;
        final absorbed = dmg < c.hpTemp ? dmg : c.hpTemp;
        c.hpTemp -= absorbed;
        dmg -= absorbed;
        c.hpCurrent = (c.hpCurrent - dmg).clamp(0, c.hpMax);
      });

  Widget _deathRow(String label, int count, Color color,
      ValueChanged<int> onChanged) {
    return Row(children: [
      SizedBox(width: 80, child: Text(label)),
      for (var i = 1; i <= 3; i++)
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(
              count >= i ? Icons.circle : Icons.circle_outlined,
              color: color),
          onPressed: () => onChanged(count == i ? i - 1 : i),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final id = c.id;
    return SectionCard(
      title: 'Hit Points',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${c.hpCurrent} / ${c.hpMax}'
            '${c.hpTemp > 0 ? '  (+${c.hpTemp} temp)' : ''}',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          IntField(
              key: ValueKey('hpamt-$id'),
              label: 'Amount',
              value: _amount,
              onChanged: (v) => _amount = v),
          FilledButton(onPressed: _heal, child: const Text('+ Heal')),
          FilledButton.tonal(
              onPressed: _damage, child: const Text('- Damage')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          IntField(
              key: ValueKey('hpcur-$id'),
              label: 'Current',
              value: c.hpCurrent,
              onChanged: (v) =>
                  widget.ctrl.mutate((x) => x.hpCurrent = v.clamp(0, x.hpMax))),
          IntField(
              key: ValueKey('hpmax-$id'),
              label: 'Max',
              value: c.hpMax,
              onChanged: (v) => widget.ctrl.mutate((x) {
                    x.hpMax = v;
                    if (x.hpCurrent > v) x.hpCurrent = v;
                  })),
          IntField(
              key: ValueKey('hptemp-$id'),
              label: 'Temp',
              value: c.hpTemp,
              onChanged: (v) => widget.ctrl.mutate((x) => x.hpTemp = v)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          SizedBox(
            width: 100,
            child: TextCommitField(
                key: ValueKey('hd-$id'),
                label: 'Hit Dice',
                value: c.hitDiceTotal,
                onChanged: (v) =>
                    widget.ctrl.mutate((x) => x.hitDiceTotal = v)),
          ),
          IntField(
              key: ValueKey('hdrem-$id'),
              label: 'HD Left',
              value: c.hitDiceRemaining,
              onChanged: (v) =>
                  widget.ctrl.mutate((x) => x.hitDiceRemaining = v)),
        ]),
        const Divider(),
        _deathRow('Successes', c.deathSaveSuccesses, Colors.green,
            (n) => widget.ctrl.mutate((x) => x.deathSaveSuccesses = n)),
        _deathRow('Failures', c.deathSaveFailures, Colors.red,
            (n) => widget.ctrl.mutate((x) => x.deathSaveFailures = n)),
      ]),
    );
  }
}

