import 'package:flutter/material.dart';

import '../../models/dice_roll_event.dart';
import '../../state/map_controller.dart';

/// Bottom-left stack of recent party dice rolls. Never intercepts input.
class DiceRollToastOverlay extends StatelessWidget {
  const DiceRollToastOverlay({super.key, required this.mapController});

  final MapController mapController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: mapController,
      builder: (context, _) {
        final toasts = mapController.activeRollToasts;
        return Align(
          alignment: Alignment.bottomLeft,
          child: IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final e in toasts) _ToastCard(event: e)],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.event});

  final DiceRollEvent event;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = event.quantity == 1
        ? 'd(${event.dieType})'
        : '${event.quantity}d(${event.dieType})';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: scheme.surfaceContainer,
        elevation: 4,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.primary),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.casino_outlined, color: scheme.primary),
                  const SizedBox(height: 2),
                  Text(
                    badge,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  event.message,
                  style: TextStyle(color: scheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
