import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../main.dart' show isCloudSyncConfigured;
import '../../models/character.dart';
import '../../state/character_controller.dart';
import '../../state/map_controller.dart';
import '../modals/dice_roller_dialog.dart';
import '../modals/map_modal.dart';

class TopActionBar extends StatelessWidget {
  const TopActionBar({super.key, required this.ctrl, this.mapController});

  final CharacterController ctrl;
  final MapController? mapController;

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
    final result = await showDialog<_JoinResult>(
      context: context,
      builder: (dialogContext) =>
          _JoinPartyDialog(ctrl: ctrl, connectedRoom: room),
    );
    if (result == null) return;
    // The dialog is fully popped; only now mutate controller state so the
    // Party Bar is inserted outside of the dialog's teardown.
    if (result.disconnect) {
      ctrl.leaveRoom();
      return;
    }
    final code = result.roomCode;
    if (code == null) return;
    try {
      await ctrl.joinRoom(code, skipPush: true);
    } catch (e) {
      debugPrint('Join party failed: $e');
      if (context.mounted) _toast(context, e.toString());
    }
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
                  if (mapController != null)
                    OutlinedButton.icon(
                      onPressed: () => showMapModal(
                        context,
                        mapController: mapController!,
                        characterController: ctrl,
                      ),
                      icon: const Icon(Icons.map),
                      label: const Text('Party Map'),
                    ),
                  if (mapController != null)
                    OutlinedButton.icon(
                      onPressed: () => showDiceRollerDialog(
                        context,
                        mapController: mapController!,
                        rollerName: ctrl.active?.name ?? '',
                      ),
                      icon: const Icon(Icons.casino_outlined),
                      label: const Text('Roll Dice'),
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

class _JoinResult {
  const _JoinResult.join(String this.roomCode) : disconnect = false;
  const _JoinResult.disconnect() : roomCode = null, disconnect = true;

  final String? roomCode;
  final bool disconnect;
}

class _JoinPartyDialog extends StatefulWidget {
  const _JoinPartyDialog({required this.ctrl, required this.connectedRoom});

  final CharacterController ctrl;
  final String? connectedRoom;

  @override
  State<_JoinPartyDialog> createState() => _JoinPartyDialogState();
}

class _JoinPartyDialogState extends State<_JoinPartyDialog> {
  final TextEditingController _field = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    final code = _field.text.trim();
    if (!RegExp(r'^[a-zA-Z0-9]{4,8}$').hasMatch(code)) {
      setState(() => _errorText = 'Use 4-8 letters or numbers.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      await widget.ctrl.verifyRoom(code);
    } catch (e) {
      debugPrint('Join party failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorText = e.toString();
        });
      }
      return;
    }
    if (!mounted) return;
    // Pop first; the caller updates controller state after the dialog closes.
    Navigator.of(context).pop(_JoinResult.join(code));
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.connectedRoom;
    return AlertDialog(
      title: Text(room == null ? 'Join Party' : 'Room: $room'),
      content: room != null
          ? const Text('You are connected. Disconnect to leave this room.')
          : TextField(
              controller: _field,
              autofocus: true,
              enabled: !_isLoading,
              maxLength: 8,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Room Code (4-8 characters)',
                errorText: _errorText,
                errorMaxLines: 12,
                counterText: '',
              ),
              onSubmitted: (_) => _submit(),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (room != null)
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(const _JoinResult.disconnect()),
            child: const Text('Disconnect'),
          )
        else
          FilledButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Join'),
          ),
      ],
    );
  }
}
