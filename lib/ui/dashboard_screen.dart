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
        final c = ctrl.active;
        return Scaffold(
          body: Column(
            children: [
              TopActionBar(ctrl: ctrl),
              Expanded(
                child: c == null
                    ? const Center(child: Text('No character loaded'))
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              flex: 4,
                              child: StatsColumn(
                                  key: ValueKey('stats-${c.id}'),
                                  ctrl: ctrl,
                                  character: c)),
                          Expanded(
                              flex: 3,
                              child: InventoryColumn(
                                  key: ValueKey('inv-${c.id}'),
                                  ctrl: ctrl,
                                  character: c)),
                          Expanded(
                              flex: 3,
                              child: SpellsColumn(
                                  key: ValueKey('spells-${c.id}'),
                                  ctrl: ctrl,
                                  character: c)),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
