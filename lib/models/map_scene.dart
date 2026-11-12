import 'json_helpers.dart';
import 'map_layer.dart';
import 'map_token.dart';

enum MapCategory { world, town, battle }

class MapScene {
  MapScene({
    String? id,
    this.name = 'New Map',
    this.category = MapCategory.world,
    this.imageUrl = '',
    this.gridEnabled = false,
    this.gridSize = 50.0,
    List<MapToken>? tokens,
    List<List<Map<String, double>>>? fogPolygons,
    List<MapLayer>? layers,
    this.activeLayerId = baseLayerId,
  }) : id = id ?? newId(),
       layers = layers ?? [],
       tokens = tokens ?? [],
       fogPolygons = fogPolygons ?? [];

  /// Id of the implicit base layer, which uses [imageUrl].
  static const String baseLayerId = 'base';

  final String id;
  final String name;
  final MapCategory category;

  /// Local file path or remote URL.
  final String imageUrl;
  final bool gridEnabled;
  final double gridSize;
  final List<MapToken> tokens;

  /// Reserved for future Fog of War: each polygon is a list of {x, y} points.
  final List<List<Map<String, double>>> fogPolygons;

  /// Extra background layers; the base map ([imageUrl]) is always available.
  final List<MapLayer> layers;

  /// The layer players currently see (set when the GM pushes a layer).
  final String activeLayerId;

  bool hasLayer(String layerId) =>
      layerId == baseLayerId || layers.any((l) => l.id == layerId);

  /// Image for [layerId]; falls back to the base map for unknown ids.
  String imageUrlFor(String layerId) {
    for (final l in layers) {
      if (l.id == layerId) return l.imageUrl;
    }
    return imageUrl;
  }

  static MapCategory _categoryFrom(dynamic v) {
    final s = readString(v, '');
    for (final c in MapCategory.values) {
      if (c.name == s) return c;
    }
    return MapCategory.world;
  }

  factory MapScene.fromJson(Map<String, dynamic> json) {
    return MapScene(
      id: json['id'] == null ? null : readString(json['id'], ''),
      name: readString(json['name'], 'New Map'),
      category: _categoryFrom(json['category']),
      imageUrl: readString(json['imageUrl'], ''),
      gridEnabled: readBool(json['gridEnabled'], false),
      gridSize: readDouble(json['gridSize'], 50.0),
      tokens: readList(
        json['tokens'],
      ).map((t) => MapToken.fromJson(readMap(t))).toList(),
      fogPolygons: readList(json['fogPolygons'])
          .map(
            (poly) => readList(poly).map((pt) {
              final m = readMap(pt);
              return <String, double>{
                'x': readDouble(m['x'], 0),
                'y': readDouble(m['y'], 0),
              };
            }).toList(),
          )
          .toList(),
      layers: readList(
        json['layers'],
      ).map((l) => MapLayer.fromJson(readMap(l))).toList(),
      activeLayerId: readString(json['activeLayerId'], baseLayerId),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'imageUrl': imageUrl,
    'gridEnabled': gridEnabled,
    'gridSize': gridSize,
    'tokens': tokens.map((t) => t.toJson()).toList(),
    'fogPolygons': fogPolygons
        .map((poly) => poly.map((pt) => Map<String, double>.of(pt)).toList())
        .toList(),
    'layers': layers.map((l) => l.toJson()).toList(),
    'activeLayerId': activeLayerId,
  };

  MapScene copyWith({
    String? id,
    String? name,
    MapCategory? category,
    String? imageUrl,
    bool? gridEnabled,
    double? gridSize,
    List<MapToken>? tokens,
    List<List<Map<String, double>>>? fogPolygons,
    List<MapLayer>? layers,
    String? activeLayerId,
  }) => MapScene(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    imageUrl: imageUrl ?? this.imageUrl,
    gridEnabled: gridEnabled ?? this.gridEnabled,
    gridSize: gridSize ?? this.gridSize,
    tokens: tokens ?? this.tokens,
    fogPolygons: fogPolygons ?? this.fogPolygons,
    layers: layers ?? this.layers,
    activeLayerId: activeLayerId ?? this.activeLayerId,
  );
}
