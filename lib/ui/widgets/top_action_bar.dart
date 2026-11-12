import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../main.dart' show isCloudSyncConfigured;
import '../../models/character.dart';
import '../../state/character_controller.dart';

class TopActionBar extends StatelessWidget {
  const TopActionBar({super.key, required this.ctrl});

  final CharacterController ctrl;

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _import(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Import Character (.json)',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      await ctrl.importCharacter(path);
      if (context.mounted) _toast(context, 'Imported "${ctrl.active?.name}"');
    } on FormatException {
      if (context.mounted) {
        _toast(context, 'Import failed: not a valid character JSON file.');
      }
    } catch (e) {
      if (context.mounted) _toast(context, 'Import failed: $e');
    }
  }

  Future<void> _export(BuildContext context) async {
    final c = ctrl.active;
    if (c == null) return;
    try {
      await ctrl.flush();
      final safe = c.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
      final path = await FilePicker.saveFile(
        dialogTitle: 'Export Character (.json)',
        fileName: '${safe.isEmpty ? 'character' : safe}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path == null) return;
      await ctrl.exportActive(path);
      if (context.mounted) _toast(context, 'Exported "${c.name}"');
    } catch (e) {
      if (context.mounted) _toast(context, 'Export failed: $e');
    }
  }

  Future<void> _partyDialog(BuildContext context) async {
    if (!isCloudSyncConfigured) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Party Sync not configured'),
          content: const Text(
            'Copy supabase_config.example.json to supabase_config.json, fill in your Supabase URL and anon key, then run:\n\n'
            'flutter run -d windows --dart-define-from-file=supabase_config.json\n\n'
            '(build_release.ps1 does this automatically when the file exists.)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final room = ctrl.currentRoomCode;
    final field = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setState) {
            void submit() {
              final code = field.text.toUpperCase().trim();
              if (!RegExp(r'^[A-Z0-9]{4,8}\$').hasMatch(code)) {
                setState(() => error = 'Use 4-8 letters or numbers.');
                return;
              }
              Navigator.pop(ctx);
              ctrl.joinRoom(code);
            }

            return AlertDialog(
              title: Text(room == null ? 'Join Party' : 'Room: '),
              content: room != null
                  ? const Text(
                      'You are connected. Disconnect to leave this room.',
                    )
                  : TextField(
                      controller: field,
                      autofocus: true,
                      maxLength: 8,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Room Code (4-8 characters)',
                        errorText: error,
                      ),
                      onSubmitted: (_) => submit(),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                if (room != null)
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ctrl.leaveRoom();
                    },
                    child: const Text('Disconnect'),
                  )
                else
                  FilledButton(onPressed: submit, child: const Text('Join')),
              ],
            );
          },
        );
      },
    );
    field.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ctrl.active;
    final room = ctrl.currentRoomCode;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            DropdownButton<String>(
              value: active?.id,
              underline: const SizedBox.shrink(),
              items: [
                for (final c in ctrl.characters)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name.isEmpty ? '(unnamed)' : c.name),
                  ),
              ],
              onChanged: (id) {
                if (id != null) ctrl.selectCharacter(id);
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton.icon(
                    onPressed: ctrl.createCharacter,
                    icon: const Icon(Icons.add),
                    label: const Text('New Character'),
                  ),
                  OutlinedButton.icon(
                    onPressed: ctrl.duplicateActive,
                    icon: const Icon(Icons.copy),
                    label: const Text('Duplicate'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      if (await _confirm(
                        context,
                        'Delete Character',
                        'Permanently delete "${active?.name}"?',
                      )) {
                        await ctrl.deleteActive();
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _import(context),
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Import JSON'),
                  ),
                  OutlinedButton.icon(
                    onPressed: active == null ? null : () => _export(context),
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Export JSON'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _partyDialog(context),
                    icon: Icon(
                      Icons.circle,
                      size: 12,
                      color: room == null ? Colors.grey : Colors.green,
                    ),
                    label: Text(room == null ? 'Join Party' : 'Room: '),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      if (await _confirm(
                        context,
                        'Long Rest',
                        'Restore HP, spell slots and reset death saves?',
                      )) {
                        ctrl.longRest();
                      }
                    },
                    icon: const Icon(Icons.bedtime),
                    label: const Text('Long Rest'),
                  ),
                ],
              ),
            ),
            _SaveIndicator(status: ctrl.saveStatus),
          ],
        ),
      ),
    );
  }
}

class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.status});
  final SaveStatus status;

  @override
  Widget build(BuildContext context) {
    final (text, icon, color) = switch (status) {
      SaveStatus.saved => ('Saved ✓', Icons.check_circle_outline, Colors.green),
      SaveStatus.saving => ('Saving…', Icons.sync, Colors.amber),
      SaveStatus.error => ('Save failed', Icons.error_outline, Colors.red),
    };
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color)),
      ],
    );
  }
}

class PartyBar extends StatelessWidget {
  const PartyBar({super.key, required this.ctrl});

  final CharacterController ctrl;

  @override
  Widget build(BuildContext context) {
    if (ctrl.currentRoomCode == null) return const SizedBox.shrink();
    final localId = ctrl.active?.id;
    final inspectedId = ctrl.inspectedPartyMember?.id;
    final scheme = Theme.of(context).colorScheme;
    Widget chip(Character m) {
      final isLocal = m.id == localId;
      final selected = isLocal ? inspectedId == null : inspectedId == m.id;
      return ActionChip(
        backgroundColor: selected ? scheme.primaryContainer : null,
        avatar: Icon(isLocal ? Icons.person : Icons.groups, size: 16),
        label: Text(
          '${m.name.isEmpty ? '(unnamed)' : m.name}  HP ${m.hpCurrent}/${m.hpMax}  AC ${m.armorClass}',
        ),
        onPressed: () => ctrl.inspectPartyMember(isLocal ? null : m),
      );
    }

    final members = ctrl.partyMembers;
    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in members) chip(m),
                  if (members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Waiting for party members...'),
                    ),
                ],
              ),
            ),
            if (ctrl.isViewingPartyMember)
              TextButton(
                onPressed: () => ctrl.inspectPartyMember(null),
                child: const Text('Back to My Sheet'),
              ),
          ],
        ),
      ),
    );
  }
}
