import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/character.dart';

/// Local file I/O for character JSON files. One character = one .json file.
class StorageService {
  StorageService({Directory? overrideDirectory})
    : _overrideDirectory = overrideDirectory;

  final Directory? _overrideDirectory;
  Directory? _dir;

  /// `<Documents>/DnDPlayerTracker/characters/`
  Future<Directory> get charactersDir async {
    if (_dir != null) return _dir!;
    Directory dir;
    if (_overrideDirectory != null) {
      dir = _overrideDirectory;
    } else {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory(
        '${docs.path}${Platform.pathSeparator}DnDPlayerTracker${Platform.pathSeparator}characters',
      );
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  String _safeId(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  Future<File> _fileFor(String id) async {
    final dir = await charactersDir;
    return File('${dir.path}${Platform.pathSeparator}${_safeId(id)}.json');
  }

  /// Loads every readable character. Corrupt files fall back to their .bak.
  Future<List<Character>> loadAll() async {
    final dir = await charactersDir;
    final result = <Character>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      final c =
          await _readCharacter(entity) ??
          await _readCharacter(File('${entity.path}.bak'));
      if (c != null) result.add(c);
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<Character?> _readCharacter(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return Character.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  /// Atomic save: write .tmp, keep previous as .bak, rename .tmp to .json.
  Future<void> save(Character character) async {
    final file = await _fileFor(character.id);
    final tmp = File('${file.path}.tmp');
    final bak = File('${file.path}.bak');
    final content = const JsonEncoder.withIndent(
      '  ',
    ).convert(character.toJson());

    await tmp.writeAsString(content, flush: true);
    if (await file.exists()) {
      try {
        await file.copy(bak.path);
      } catch (_) {}
    }
    try {
      await tmp.rename(file.path);
    } on FileSystemException {
      // Windows may refuse to overwrite; remove target then retry.
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    }
  }

  Future<void> delete(Character character) async {
    final file = await _fileFor(character.id);
    for (final f in [
      file,
      File('${file.path}.bak'),
      File('${file.path}.tmp'),
    ]) {
      if (await f.exists()) await f.delete();
    }
  }

  /// Reads an external JSON file, assigns a fresh id if it collides, saves it
  /// into the workspace and returns it. Throws FormatException if invalid.
  Future<Character> importFrom(String path, Set<String> existingIds) async {
    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is! Map) {
      throw const FormatException('Not a character JSON object');
    }
    final c = Character.fromJson(decoded.cast<String, dynamic>());
    if (existingIds.contains(c.id)) {
      final fresh = Character.fromJson(c.toJson());
      fresh.id = Character.blank().id;
      await save(fresh);
      return fresh;
    }
    await save(c);
    return c;
  }

  Future<void> exportTo(Character character, String path) async {
    final target = path.toLowerCase().endsWith('.json') ? path : '$path.json';
    final content = const JsonEncoder.withIndent(
      '  ',
    ).convert(character.toJson());
    await File(target).writeAsString(content, flush: true);
  }
}
