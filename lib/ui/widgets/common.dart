import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Titled card used for every dashboard section.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// Drag-to-reorder list for the short lists inside a [SectionCard].
class ReorderList<T> extends StatelessWidget {
  const ReorderList({
    super.key,
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    required this.onReorder,
  });

  final List<T> items;
  final String Function(T) idOf;
  final Widget Function(T) itemBuilder;

  /// Called with already-adjusted (oldIndex, newIndex) positions.
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: true,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        if (oldIndex == newIndex) return;
        onReorder(oldIndex, newIndex);
      },
      children: [
        for (final item in items)
          Padding(
            key: ValueKey(idOf(item)),
            // Reserve room for the drag handle drawn at the right edge.
            padding: const EdgeInsets.only(right: 40),
            child: itemBuilder(item),
          ),
      ],
    );
  }
}

/// Integer input that reports valid values as the user types.
class IntField extends StatefulWidget {
  const IntField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.width = 80,
    this.allowNegative = false,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final double width;
  final bool allowNegative;

  @override
  State<IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<IntField> {
  late final TextEditingController _c = TextEditingController(
    text: '${widget.value}',
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(IntField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && int.tryParse(_c.text) != widget.value) {
      _c.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _c,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp(widget.allowNegative ? r'^-?\d*' : r'^\d*'),
          ),
        ],
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (s) {
          final v = int.tryParse(s);
          if (v != null) widget.onChanged(v);
        },
      ),
    );
  }
}

/// Text input with an initial value that reports every change.
class TextCommitField extends StatefulWidget {
  const TextCommitField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int maxLines;

  @override
  State<TextCommitField> createState() => _TextCommitFieldState();
}

class _TextCommitFieldState extends State<TextCommitField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: widget.onChanged,
    );
  }
}
