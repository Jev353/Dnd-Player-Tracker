import 'package:flutter/material.dart';

import '../../models/item.dart';
import '../../state/character_controller.dart';
import '../widgets/common.dart';

/// Opens the item dialog. Pass [item] to view it, or null to create one.
Future<void> showItemModal(BuildContext context, CharacterController ctrl,
    {InventoryItem? item}) {
  return showDialog(
    context: context,
    builder: (_) => _ItemDialog(ctrl: ctrl, item: item),
  );
}

class _ItemDialog extends StatefulWidget {
  const _ItemDialog({required this.ctrl, this.item});
  final CharacterController ctrl;
  final InventoryItem? item;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late bool _editing = widget.item == null;
  late String _name = widget.item?.name ?? '';
  late int _amount = widget.item?.amount ?? 1;
  late String _desc = widget.item?.description ?? '';
  String? _error;

  void _save() {
    if (_name.trim().isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final existing = widget.item;
    widget.ctrl.mutate((c) {
      if (existing == null) {
        c.items.add(InventoryItem(
            name: _name.trim(), amount: _amount, description: _desc));
      } else {
        existing
          ..name = _name.trim()
          ..amount = _amount
          ..description = _desc;
      }
    });
    if (existing == null) {
      Navigator.pop(context);
    } else {
      setState(() => _editing = false);
    }
  }

  void _step(int delta) {
    final item = widget.item!;
    widget.ctrl.mutate((_) {
      item.amount = (item.amount + delta).clamp(0, 999999);
    });
    setState(() => _amount = item.amount);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AlertDialog(
      title: Text(item == null
          ? 'Add Item'
          : (_editing ? 'Edit Item' : item.name)),
      content: SizedBox(
        width: 460,
        child: _editing ? _form() : _view(item!),
      ),
      actions: _editing
          ? [
              TextButton(
                onPressed: () {
                  if (item == null) {
                    Navigator.pop(context);
                  } else {
                    setState(() {
                      _editing = false;
                      _name = item.name;
                      _amount = item.amount;
                      _desc = item.description;
                      _error = null;
                    });
                  }
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                  onPressed: _save,
                  child: Text(item == null ? 'Save' : 'Save Changes')),
            ]
          : [
              TextButton(
                onPressed: () {
                  widget.ctrl.mutate((c) => c.items.remove(item));
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

  Widget _form() => SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 4),
          TextCommitField(
              label: 'Name', value: _name, onChanged: (v) => _name = v),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: IntField(
                label: 'Amount', value: _amount, onChanged: (v) => _amount = v),
          ),
          const SizedBox(height: 12),
          TextCommitField(
              label: 'Description',
              value: _desc,
              maxLines: 6,
              onChanged: (v) => _desc = v),
        ]),
      );

  Widget _view(InventoryItem item) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Amount:'),
            IconButton(
                icon: const Icon(Icons.remove), onPressed: () => _step(-1)),
            Text('${item.amount}',
                style: Theme.of(context).textTheme.titleMedium),
            IconButton(icon: const Icon(Icons.add), onPressed: () => _step(1)),
          ]),
          const Divider(),
          Flexible(
            child: SingleChildScrollView(
              child: SelectableText(
                  item.description.isEmpty ? 'No description.' : item.description),
            ),
          ),
        ],
      );
}
