import 'package:flutter/material.dart';

import '../../models/map_scene.dart';
import '../../models/map_token.dart';
import '../../state/character_controller.dart';
import '../../state/map_controller.dart';
import '../widgets/map_canvas.dart';
import 'map_dialogs.dart';
import 'map_token_dialog.dart';

/// Opens the Party Map as a ~90% viewport dialog.
Future<void> showMapModal(
  BuildContext context, {
  required MapController mapController,
  required CharacterController characterController,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => MapModal(
      mapController: mapController,
      characterController: characterController,
    ),
  );
}

class MapModal extends StatefulWidget {
  const MapModal({
    super.key,
    required this.mapController,
    required this.characterController,
  });

  final MapController mapController;
  final CharacterController characterController;

  @override
  State<MapModal> createState() => _MapModalState();
}

class _MapModalState extends State<MapModal> {
  late MapCategory _tab;
  String? _selectedSceneId;

  MapController get _map => widget.mapController;
  CharacterController get _chars => widget.characterController;

  @override
  void initState() {
    super.initState();
    _tab = _map.activeScene?.category ?? MapCategory.world;
    _selectedSceneId = _map.activeScene?.id;
    // Defer: notifying listeners during initState would assert. Always
    // re-sync the session to the current room (it may have changed).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final code = _currentCode;
      if (_map.partyCode != code) {
        _map.setPartySession(partyCode: code, isGM: _map.isGM);
      }
    });
  }

  String get _currentCode =>
      _chars.currentRoomCode ?? MapController.localPartyCode;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _toggleRole(bool gm) {
    _map.setPartySession(partyCode: _currentCode, isGM: gm);
  }

  void _dropMyCharacter() {
    final scene = _map.activeScene;
    final c = _chars.active;
    if (scene == null) {
      _toast('No active scene yet.');
      return;
    }
    if (c == null) return;
    if (scene.tokens.any((t) => t.characterId == c.id)) {
      _toast('${c.name} is already on this map.');
      return;
    }
    _map.addToken(
      MapToken(
        characterId: c.id,
        label: c.name,
        x: scene.gridSize,
        y: scene.gridSize,
      ),
      currentCharacterId: c.id,
    );
  }

  Future<void> _addScene() async {
    final scene = await showDialog<MapScene>(
      context: context,
      builder: (_) => AddSceneDialog(initialCategory: _tab),
    );
    if (scene == null) return;
    // In a synced party, local files are uploaded so players can load them.
    final url = await _map.resolveImageUrl(scene.imageUrl);
    if (!mounted) return;
    final isLocalFile =
        url.trim().isNotEmpty &&
        !url.startsWith('http://') &&
        !url.startsWith('https://');
    if (_map.isSynced && isLocalFile) {
      _toast('Image upload failed; players will not see this map image.');
    }
    _map.addScene(scene.copyWith(imageUrl: url));
    setState(() {
      _tab = scene.category;
      _selectedSceneId = scene.id;
    });
  }

  Future<void> _addNpc() async {
    final token = await showDialog<MapToken>(
      context: context,
      builder: (_) => const AddTokenDialog(),
    );
    if (token == null) return;
    final g = _map.activeScene?.gridSize ?? 50;
    _map.addToken(token.copyWith(x: g * 2, y: g * 2));
  }

  Future<void> _tokenMenu(MapToken token, Offset pos) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(
          value: 'toggle',
          child: Text(
            token.visibleToPlayers ? 'Hide from players' : 'Show to players',
          ),
        ),
        const PopupMenuItem(value: 'delete', child: Text('Delete token')),
      ],
    );
    if (choice == 'toggle') _map.toggleTokenVisibility(token.id);
    if (choice == 'delete') _map.removeToken(token.id);
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Party Map',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            SegmentedButton<MapCategory>(
              showSelectedIcon: false,
              segments: [
                for (final c in MapCategory.values)
                  ButtonSegment(value: c, label: Text(categoryLabel(c))),
              ],
              // Connected players are locked to the GM's scene, so the tabs
              // just mirror its category and cannot be changed.
              selected: {
                _map.isSynced && !_map.isGM
                    ? (_map.activeScene?.category ?? _tab)
                    : _tab,
              },
              onSelectionChanged: _map.isSynced && !_map.isGM
                  ? null
                  : (s) => setState(() {
                      _tab = s.first;
                      final inTab = _map.scenes.where(
                        (x) => x.category == _tab,
                      );
                      if (!inTab.any((x) => x.id == _selectedSceneId)) {
                        _selectedSceneId = inTab.isEmpty
                            ? null
                            : inTab.first.id;
                        final id = _selectedSceneId;
                        if (id != null) _map.viewScene(id);
                      }
                    }),
            ),
            Chip(
              avatar: const Icon(Icons.vpn_key, size: 16),
              label: Text('Party: ${_map.partyCode ?? '-'}'),
            ),
            if (_map.syncError != null)
              Tooltip(
                message: _map.syncError!,
                child: Chip(
                  avatar: Icon(
                    Icons.sync_problem,
                    size: 16,
                    color: scheme.error,
                  ),
                  label: const Text('Sync issue'),
                ),
              ),
            Chip(
              avatar: Icon(_map.isGM ? Icons.shield : Icons.person, size: 16),
              label: Text(_map.isGM ? 'GM Mode' : 'Player Mode'),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('GM'),
                Switch(value: _map.isGM, onChanged: _toggleRole),
              ],
            ),
            FilledButton.icon(
              onPressed: _dropMyCharacter,
              icon: const Icon(Icons.place),
              label: const Text('Drop My Character Token'),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gmToolbar(BuildContext context) {
    final scene = _map.activeScene;
    final inTab = _map.scenes.where((s) => s.category == _tab).toList();
    final selected = inTab.any((s) => s.id == _selectedSceneId)
        ? _selectedSceneId
        : null;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _addScene,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Add Map Scene'),
            ),
            DropdownButton<String>(
              hint: Text('${categoryLabel(_tab)} scenes'),
              value: selected,
              items: [
                for (final s in inTab)
                  DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      s.id == _map.activeSceneId ? '${s.name} (live)' : s.name,
                    ),
                  ),
              ],
              // Switching only changes the GM's own view; players keep seeing
              // the pushed scene until "Push Scene to Party" is pressed.
              onChanged: (id) {
                if (id == null) return;
                setState(() => _selectedSceneId = id);
                _map.viewScene(id);
              },
            ),
            FilledButton.icon(
              onPressed: selected == null || selected == _map.activeSceneId
                  ? null
                  : () {
                      _map.setActiveScene(selected);
                      _toast('Scene pushed to party.');
                    },
              icon: const Icon(Icons.send),
              label: const Text('Push Scene to Party'),
            ),
            if (scene != null) ..._sceneControls(scene),
          ],
        ),
      ),
    );
  }

  List<Widget> _sceneControls(MapScene scene) => [
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Grid'),
        Switch(
          value: scene.gridEnabled,
          onChanged: (v) => _map.updateSceneSettings(scene.id, gridEnabled: v),
        ),
      ],
    ),
    SizedBox(
      width: 220,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              min: 25,
              max: 120,
              value: scene.gridSize.clamp(25, 120).toDouble(),
              onChanged: (v) => _map.updateSceneSettings(
                scene.id,
                gridSize: v.roundToDouble(),
              ),
            ),
          ),
          Text('${scene.gridSize.round()}px'),
        ],
      ),
    ),
    OutlinedButton.icon(
      onPressed: _addNpc,
      icon: const Icon(Icons.pets),
      label: const Text('Add Monster/NPC Token'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width * 0.05,
        vertical: size.height * 0.05,
      ),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: Listenable.merge([_map, _chars]),
        builder: (context, _) {
          final scene = _map.activeScene;
          return Column(
            children: [
              _header(context),
              if (_map.isGM) _gmToolbar(context),
              Expanded(
                child: ClipRect(
                  child: scene == null
                      ? Center(
                          child: Text(
                            _map.isGM
                                ? 'No scenes yet. Add a map scene to begin.'
                                : 'Waiting for the GM to push a scene...',
                          ),
                        )
                      : MapCanvas(
                          key: ValueKey(scene.id),
                          scene: scene,
                          mapController: _map,
                          currentCharacterId: _chars.active?.id,
                          onTokenMenu: _tokenMenu,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
