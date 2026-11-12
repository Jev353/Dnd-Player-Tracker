import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/map_scene.dart';

String categoryLabel(MapCategory c) =>
    '${c.name[0].toUpperCase()}${c.name.substring(1)}';

/// Collects name, category and image (URL or local file) for a new scene.
class AddSceneDialog extends StatefulWidget {
  const AddSceneDialog({super.key, required this.initialCategory});

  final MapCategory initialCategory;

  @override
  State<AddSceneDialog> createState() => _AddSceneDialogState();
}

class _AddSceneDialogState extends State<AddSceneDialog> {
  final _name = TextEditingController();
  final _image = TextEditingController();
  late MapCategory _category = widget.initialCategory;

  @override
  void dispose() {
    _name.dispose();
    _image.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Choose map image',
        type: FileType.image,
      );
      final path = result?.files.single.path;
      if (path != null) setState(() => _image.text = path);
    } catch (e) {
      debugPrint('Map image pick failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Map Scene'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MapCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in MapCategory.values)
                  DropdownMenuItem(value: c, child: Text(categoryLabel(c))),
              ],
              onChanged: (c) => setState(() => _category = c ?? _category),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _image,
                    decoration: const InputDecoration(
                      labelText: 'Image URL or file path (optional)',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Browse...',
                  onPressed: _pick,
                  icon: const Icon(Icons.folder_open),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            MapScene(
              name: _name.text.trim().isEmpty ? 'New Map' : _name.text.trim(),
              category: _category,
              imageUrl: _image.text.trim(),
            ),
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
