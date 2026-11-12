import 'package:flutter/material.dart';

import '../../state/character_controller.dart';
import '../widgets/common.dart';

/// Pop-up character bio. Edits auto-save as you type.
Future<void> showBioModal(BuildContext context, CharacterController ctrl) {
  final c = ctrl.active;
  if (c == null) return Future.value();
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(c.name.isEmpty ? 'Character Bio' : '${c.name} - Bio'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextCommitField(
              label: 'Backstory, appearance, personality, goals...',
              value: c.bio,
              maxLines: 16,
              onChanged: (v) => ctrl.mutate((x) => x.bio = v),
            ),
          ),
        ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
    ),
  );
}
