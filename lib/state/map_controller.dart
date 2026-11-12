import 'package:flutter/foundation.dart';

import '../models/map_scene.dart';
import '../models/map_token.dart';

/// Holds the party's map scenes, the active scene, and token permissions.
class MapController extends ChangeNotifier {
  String? partyCode;
  bool isGM = false;
  String? activeSceneId;
  final List<MapScene> _scenes = [];

  List<MapScene> get scenes => List.unmodifiable(_scenes);

  MapScene? get activeScene {
    final id = activeSceneId;
    if (id == null) return null;
    final i = _scenes.indexWhere((s) => s.id == id);
    return i < 0 ? null : _scenes[i];
  }

  void setPartySession({required String partyCode, required bool isGM}) {
    this.partyCode = partyCode;
    this.isGM = isGM;
    notifyListeners();
  }

  /// GM only. The first scene added becomes active automatically.
  void addScene(MapScene scene) {
    if (!isGM) return;
    _scenes.add(scene);
    activeSceneId ??= scene.id;
    notifyListeners();
  }

  /// GM only.
  void setActiveScene(String sceneId) {
    if (!isGM) return;
    if (!_scenes.any((s) => s.id == sceneId)) return;
    activeSceneId = sceneId;
    notifyListeners();
  }

  /// GM only.
  void updateSceneSettings(
    String sceneId, {
    bool? gridEnabled,
    double? gridSize,
    String? imageUrl,
  }) {
    if (!isGM) return;
    final i = _scenes.indexWhere((s) => s.id == sceneId);
    if (i < 0) return;
    _scenes[i] = _scenes[i].copyWith(
      gridEnabled: gridEnabled,
      gridSize: gridSize,
      imageUrl: imageUrl,
    );
    notifyListeners();
  }

  /// GM may add any token. A player may only add a token for their own
  /// character ([currentCharacterId]) that is not already on the active scene.
  void addToken(MapToken token, {String? currentCharacterId}) {
    final scene = activeScene;
    if (scene == null) return;
    if (!isGM) {
      final own = currentCharacterId;
      if (own == null || token.characterId != own) return;
      if (scene.tokens.any((t) => t.characterId == own)) return;
    }
    _replaceActive(scene.copyWith(tokens: [...scene.tokens, token]));
  }

  /// Allowed if [isGM] or the token belongs to [currentCharacterId].
  void moveToken(
    String tokenId,
    double newX,
    double newY, {
    required String? currentCharacterId,
  }) {
    final scene = activeScene;
    if (scene == null) return;
    final token = _findToken(scene, tokenId);
    if (token == null) return;
    final owns = token.characterId != null &&
        token.characterId == currentCharacterId;
    if (!isGM && !owns) return;
    _updateToken(scene, token.copyWith(x: newX, y: newY));
  }

  /// Snaps the token to the nearest grid intersection when the active
  /// scene has its grid enabled. No-op otherwise.
  void snapTokenToGrid(String tokenId) {
    final scene = activeScene;
    if (scene == null || !scene.gridEnabled || scene.gridSize <= 0) return;
    final token = _findToken(scene, tokenId);
    if (token == null) return;
    final g = scene.gridSize;
    _updateToken(
      scene,
      token.copyWith(
        x: (token.x / g).roundToDouble() * g,
        y: (token.y / g).roundToDouble() * g,
      ),
    );
  }

  /// GM only.
  void toggleTokenVisibility(String tokenId) {
    if (!isGM) return;
    final scene = activeScene;
    if (scene == null) return;
    final token = _findToken(scene, tokenId);
    if (token == null) return;
    _updateToken(
      scene,
      token.copyWith(visibleToPlayers: !token.visibleToPlayers),
    );
  }

  /// GM only.
  void removeToken(String tokenId) {
    if (!isGM) return;
    final scene = activeScene;
    if (scene == null) return;
    _replaceActive(
      scene.copyWith(
        tokens: scene.tokens.where((t) => t.id != tokenId).toList(),
      ),
    );
  }

  MapToken? _findToken(MapScene scene, String tokenId) {
    for (final t in scene.tokens) {
      if (t.id == tokenId) return t;
    }
    return null;
  }

  void _updateToken(MapScene scene, MapToken updated) {
    _replaceActive(
      scene.copyWith(
        tokens: [for (final t in scene.tokens) t.id == updated.id ? updated : t],
      ),
    );
  }

  void _replaceActive(MapScene updated) {
    final i = _scenes.indexWhere((s) => s.id == updated.id);
    if (i < 0) return;
    _scenes[i] = updated;
    notifyListeners();
  }
}
