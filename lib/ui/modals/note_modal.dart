import 'package:flutter/material.dart';

import '../../models/character.dart';
import '../../models/feature_note.dart';
import '../../state/character_controller.dart';
import '../widgets/common.dart';

/// Opens the note dialog. Pass [note] to view it, or null to create one.
Future<void> showNoteModal(
  BuildContext context,
  CharacterController ctrl, {
  FeatureNote? note,
  bool proficiency = false,
}) {
  return showDialog(
    context: context,
    builder: (_) =>
        _NoteDialog(ctrl: ctrl, note: note, proficiency: proficiency),
  );
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.ctrl, this.note, this.proficiency = false});
  final CharacterController ctrl;
  final FeatureNote? note;
  final bool proficiency;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late bool _editing = widget.note == null;
  late String _name = widget.note?.name ?? '';
  late String _desc = widget.note?.description ?? '';
  String? _error;

  List<FeatureNote> _list(Character c) =>
      widget.proficiency ? c.proficiencies : c.featuresAndNotes;
  String get _noun => widget.proficiency ? 'Proficiency' : 'Note';

  void _save() {
    if (_name.trim().isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final existing = widget.note;
    widget.ctrl.mutate((c) {
      if (existing == null) {
        _list(c).add(FeatureNote(name: _name.trim(), description: _desc));
      } else {
        existing
          ..name = _name.trim()
          ..description = _desc;
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
    final note = widget.note;
    return AlertDialog(
      title: Text(
        note == null ? 'Add $_noun' : (_editing ? 'Edit $_noun' : note.name),
      ),
      content: SizedBox(
        width: 460,
        child: _editing
            ? SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    TextCommitField(
                      label: 'Name',
                      value: _name,
                      onChanged: (v) => _name = v,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextCommitField(
                      label: 'Description',
                      value: _desc,
                      maxLines: 8,
                      onChanged: (v) => _desc = v,
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: SelectableText(
                  note!.description.isEmpty
                      ? 'No description.'
                      : note.description,
                ),
              ),
      ),
      actions: _editing
          ? [
              TextButton(
                onPressed: () {
                  if (note == null) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      _editing = false;
                      _name = note.name;
                      _desc = note.description;
                      _error = null;
                    });
                  }
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _save,
                child: Text(note == null ? 'Save' : 'Save Changes'),
              ),
            ]
          : [
              TextButton(
                onPressed: () {
                  widget.ctrl.mutate((c) => _list(c).remove(note));
                  Navigator.pop(context);
                },
                child: const Text('Delete'),
              ),
              OutlinedButton(
                onPressed: () => setState(() => _editing = true),
                child: const Text('Edit'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
    );
  }
}
