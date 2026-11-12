import 'package:flutter/material.dart';

import '../state/character_controller.dart';
import 'widgets/inventory_column.dart';
import 'widgets/spells_column.dart';
import 'widgets/stats_column.dart';
import 'widgets/top_action_bar.dart';

/// Top bar plus a 40/30/30 three-column body for the single active character.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.ctrl});

  final CharacterController ctrl;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final c = ctrl.inspectedPartyMember ?? ctrl.active;
        final viewing = ctrl.isViewingPartyMember;
        return Scaffold(
          body: Column(
            children: [
              TopActionBar(ctrl: ctrl),
              PartyBar(ctrl: ctrl),
              if (viewing)
                Material(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: InkWell(
                    onTap: () => ctrl.inspectPartyMember(null),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.visibility, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Viewing ${c?.name ?? ''} (Read-Only) \u2014 Return to My Character',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: c == null
                    ? const Center(child: Text('No character loaded'))
                    : IgnorePointer(
                        ignoring: viewing,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 4,
                              child: StatsColumn(
                                key: ValueKey('stats-${c.id}'),
                                ctrl: ctrl,
                                character: c,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: InventoryColumn(
                                key: ValueKey('inv-${c.id}'),
                                ctrl: ctrl,
                                character: c,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: SpellsColumn(
                                key: ValueKey('spells-${c.id}'),
                                ctrl: ctrl,
                                character: c,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
