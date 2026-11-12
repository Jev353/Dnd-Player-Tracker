/// Tolerant JSON readers so imported files with missing/odd keys never crash.
int readInt(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

String readString(dynamic v, String fallback) {
  if (v == null) return fallback;
  return v is String ? v : v.toString();
}

bool readBool(dynamic v, bool fallback) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  if (v is num) return v != 0;
  return fallback;
}

Map<String, dynamic> readMap(dynamic v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return <String, dynamic>{};
}

List<dynamic> readList(dynamic v) => v is List ? v : <dynamic>[];

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
int _counter = 0;
