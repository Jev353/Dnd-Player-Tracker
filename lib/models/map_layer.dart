import 'json_helpers.dart';

/// An alternate background image for a [MapScene] (e.g. "Day", "Night",
/// "Secret passages"). Tokens and grid are shared across a scene's layers.
class MapLayer {
  MapLayer({String? id, this.name = 'Layer', this.imageUrl = ''})
    : id = id ?? newId();

  final String id;
  final String name;

  /// Local file path or remote URL.
  final String imageUrl;

  factory MapLayer.fromJson(Map<String, dynamic> json) => MapLayer(
    id: json['id'] == null ? null : readString(json['id'], ''),
    name: readString(json['name'], 'Layer'),
    imageUrl: readString(json['imageUrl'], ''),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'imageUrl': imageUrl,
  };

  MapLayer copyWith({String? id, String? name, String? imageUrl}) => MapLayer(
    id: id ?? this.id,
    name: name ?? this.name,
    imageUrl: imageUrl ?? this.imageUrl,
  );
}
