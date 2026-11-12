import 'json_helpers.dart';

double readDouble(dynamic v, double fallback) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? fallback;
  return fallback;
}

/// A single piece (character or NPC/monster) placed on a [MapScene].
class MapToken {
  MapToken({
    String? id,
    this.characterId,
    this.label = '',
    this.x = 0,
    this.y = 0,
    this.size = 1.0,
    this.colorHex = '#D4AF37',
    this.visibleToPlayers = true,
  }) : id = id ?? newId();

  final String id;
  final String? characterId;
  final String label;
  final double x;
  final double y;
  final double size;
  final String colorHex;
  final bool visibleToPlayers;

  factory MapToken.fromJson(Map<String, dynamic> json) {
    final charId = json['characterId'];
    return MapToken(
      id: json['id'] == null ? null : readString(json['id'], ''),
      characterId: charId == null ? null : readString(charId, ''),
      label: readString(json['label'], ''),
      x: readDouble(json['x'], 0),
      y: readDouble(json['y'], 0),
      size: readDouble(json['size'], 1.0),
      colorHex: readString(json['colorHex'], '#D4AF37'),
      visibleToPlayers: readBool(json['visibleToPlayers'], true),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'characterId': characterId,
    'label': label,
    'x': x,
    'y': y,
    'size': size,
    'colorHex': colorHex,
    'visibleToPlayers': visibleToPlayers,
  };

  MapToken copyWith({
    String? id,
    String? characterId,
    String? label,
    double? x,
    double? y,
    double? size,
    String? colorHex,
    bool? visibleToPlayers,
  }) => MapToken(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    label: label ?? this.label,
    x: x ?? this.x,
    y: y ?? this.y,
    size: size ?? this.size,
    colorHex: colorHex ?? this.colorHex,
    visibleToPlayers: visibleToPlayers ?? this.visibleToPlayers,
  );
}
