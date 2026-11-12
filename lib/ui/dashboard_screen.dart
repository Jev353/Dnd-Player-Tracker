import 'package:flutter/material.dart';

import '../state/character_controller.dart';
import '../state/map_controller.dart';
import 'widgets/inventory_column.dart';
import 'widgets/spells_column.dart';
import 'widgets/stats_column.dart';
import 'widgets/top_action_bar.dart';

/// Top bar plus a 40/30/30 three-column body for the single active character.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.ctrl, this.mapController});

  final CharacterController ctrl;

  /// Optional injection for tests; a private one is created otherwise.
  final MapController? mapController;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final MapController _map = widget.mapController ?? MapController();

  CharacterController get ctrl => widget.ctrl;

  @override
  void dispose() {
    if (widget.mapController == null) _map.dispose();
    super.dispose();
  }

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
              TopActionBar(
                key: const ValueKey('top-action-bar'),
                ctrl: ctrl,
                mapController: _map,
              ),
              PartyBar(key: const ValueKey('party-bar'), ctrl: ctrl),
              if (viewing)
                Material(
                  key: const ValueKey('read-only-banner'),
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
                key: const ValueKey('dashboard-body'),
                child: c == null
                    ? const Center(child: Text('No character loaded'))
                    : KeyedSubtree(
                        key: const ValueKey('dashboard-columns'),
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
