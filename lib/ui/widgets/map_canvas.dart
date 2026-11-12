import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/map_scene.dart';
import '../../models/map_token.dart';
import '../../state/map_controller.dart';
import 'grid_painter.dart';

/// Parses '#RRGGBB' (or 'RRGGBB'); falls back to the theme gold.
Color parseHexColor(String hex) {
  final cleaned = hex.replaceAll('#', '').trim();
  final value = int.tryParse(
    cleaned.length == 6 ? 'FF$cleaned' : cleaned,
    radix: 16,
  );
  return value == null ? const Color(0xFFD4AF37) : Color(value);
}

String _initials(String label) {
  final parts = label.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

/// Pan/zoom map surface: background, grid, then draggable tokens.
class MapCanvas extends StatefulWidget {
  const MapCanvas({
    super.key,
    required this.scene,
    required this.mapController,
    required this.currentCharacterId,
    this.onTokenMenu,
  });

  final MapScene scene;
  final MapController mapController;
  final String? currentCharacterId;

  /// GM context menu hook (right-click / long-press) with global position.
  final void Function(MapToken token, Offset globalPosition)? onTokenMenu;

  @override
  State<MapCanvas> createState() => _MapCanvasState();
}

class _MapCanvasState extends State<MapCanvas> {
  final TransformationController _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 1600,
      height: 1200,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child: Text(
        widget.scene.name,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: scheme.primary.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _background(BuildContext context) {
    final url = widget.scene.imageUrl.trim();
    if (url.isEmpty) return _placeholder(context);
    final isRemote = url.startsWith('http://') || url.startsWith('https://');
    Widget error(BuildContext c, Object e, StackTrace? s) => _placeholder(c);
    return isRemote
        ? Image.network(url, errorBuilder: error)
        : Image.file(File(url), errorBuilder: error);
  }

  void _drag(MapToken token, Offset delta) {
    // The delta is reported in the token's local (scene) coordinates, which
    // already account for the InteractiveViewer's zoom; do not rescale it.
    widget.mapController.moveToken(
      token.id,
      token.x + delta.dx,
      token.y + delta.dy,
      currentCharacterId: widget.currentCharacterId,
    );
  }

  Widget _tokenWidget(BuildContext context, MapToken token) {
    final scene = widget.scene;
    final mc = widget.mapController;
    final diameter = scene.gridSize * token.size;
    final color = parseHexColor(token.colorHex);
    final canMove =
        mc.isGM ||
        (token.characterId != null &&
            token.characterId == widget.currentCharacterId);
    final ghost = !token.visibleToPlayers;
    final menu = mc.isGM ? widget.onTokenMenu : null;

    return Positioned(
      key: ValueKey(token.id),
      left: token.x,
      top: token.y,
      child: GestureDetector(
        onPanStart: canMove
            ? (_) => mc.beginTokenDrag(
                token.id,
                currentCharacterId: widget.currentCharacterId,
              )
            : null,
        onPanUpdate: canMove ? (d) => _drag(token, d.delta) : null,
        onPanEnd: canMove
            ? (_) {
                if (scene.gridEnabled) mc.snapTokenToGrid(token.id);
                mc.endTokenDrag();
              }
            : null,
        onPanCancel: canMove ? mc.endTokenDrag : null,
        onLongPressStart: menu == null
            ? null
            : (d) => menu(token, d.globalPosition),
        onSecondaryTapUp: menu == null
            ? null
            : (d) => menu(token, d.globalPosition),
        child: Tooltip(
          message: token.label,
          child: Opacity(
            opacity: ghost ? 0.5 : 1,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: diameter,
                  height: diameter,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.25),
                    border: Border.all(color: color, width: 3),
                  ),
                  child: Text(
                    _initials(token.label),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: (diameter * 0.35).clamp(10, 48).toDouble(),
                      shadows: const [Shadow(blurRadius: 3)],
                    ),
                  ),
                ),
                if (ghost)
                  const Positioned(
                    right: -2,
                    top: -2,
                    child: Icon(Icons.visibility_off, size: 16),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget.scene;
    final mc = widget.mapController;
    final tokens = scene.tokens.where((t) => t.visibleToPlayers || mc.isGM);
    return InteractiveViewer(
      transformationController: _transform,
      constrained: false,
      minScale: 0.1,
      maxScale: 4.0,
      boundaryMargin: const EdgeInsets.all(400),
      child: Stack(
        children: [
          _background(context),
          if (scene.gridEnabled)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: GridPainter(
                    gridSize: scene.gridSize,
                    transform: _transform,
                  ),
                ),
              ),
            ),
          // TODO: Phase 4 Fog of War CustomPainter Layer
          for (final token in tokens) _tokenWidget(context, token),
        ],
      ),
    );
  }
}
