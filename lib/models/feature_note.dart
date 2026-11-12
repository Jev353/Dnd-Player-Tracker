import 'json_helpers.dart';

class FeatureNote {
  String id;
  String name;
  String description;

  FeatureNote({String? id, this.name = '', this.description = ''})
      : id = id ?? newId();

  factory FeatureNote.fromJson(Map<String, dynamic> json) => FeatureNote(
        id: readString(json['id'], newId()),
        name: readString(json['name'], 'Untitled'),
        description: readString(json['description'], ''),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
      };
}
