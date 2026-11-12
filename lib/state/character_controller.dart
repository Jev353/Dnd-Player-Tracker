import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/dnd_constants.dart';
import '../models/character.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';

enum SaveStatus { saved, saving, error }

/// Holds all characters and the single active one; debounced auto-save.
class CharacterController extends ChangeNotifier {
  CharacterController(
    this._storage, {
    this.saveDelay = const Duration(milliseconds: 300),
    this.syncDelay = const Duration(milliseconds: 500),
    SyncService? syncService,
  }) : _syncService = syncService ?? SyncService();

  final StorageService _storage;
  final SyncService _syncService;
  final Duration syncDelay;
  Timer? _syncDebounce;

  String? currentRoomCode;
  List<Character> partyMembers = [];
  Character? inspectedPartyMember;
  String? syncError;
  bool get isViewingPartyMember => inspectedPartyMember != null;

  final Duration saveDelay;

  final List<Character> _characters = [];
  Character? _active;
  Timer? _debounce;
  SaveStatus _status = SaveStatus.saved;
  bool _loaded = false;
  String? lastError;

  List<Character> get characters => List.unmodifiable(_characters);
  Character? get active => _active;
  SaveStatus get saveStatus => _status;
  bool get isLoaded => _loaded;

  /// Loads all characters; creates a starter character if none exist.
  Future<void> load() async {
    _characters
      ..clear()
      ..addAll(await _storage.loadAll());
    if (_characters.isEmpty) {
      final starter = defaultCharacter(name: 'New Character');
      _characters.add(starter);
      await _storage.save(starter);
    }
    _active = _characters.first;
    _loaded = true;
    notifyListeners();
  }

  Future<void> selectCharacter(String id) async {
    await flush();
    final match = _characters.where((c) => c.id == id);
    if (match.isEmpty) return;
    _active = match.first;
    notifyListeners();
  }

  /// Call after any mutation to the active character.
  void mutate([void Function(Character c)? change]) {
    final c = _active;
    if (c == null || isViewingPartyMember) return;
    change?.call(c);
    _scheduleSync(c);
    _status = SaveStatus.saving;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(saveDelay, () => _persist(c));
  }

  void _scheduleSync(Character c) {
    if (currentRoomCode == null) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(syncDelay, () => _push(c));
  }

  Future<void> _push(Character c) async {
    final room = currentRoomCode;
    if (room == null) return;
    try {
      await _syncService.pushCharacter(roomCode: room, character: c);
      syncError = null;
    } catch (e) {
      syncError = e.toString();
      notifyListeners();
    }
  }

  Future<void> joinRoom(String roomCode) async {
    final room = SyncService.normalizeRoom(roomCode);
    currentRoomCode = room;
    partyMembers = [];
    inspectedPartyMember = null;
    syncError = null;
    notifyListeners();
    final c = _active;
    if (c != null) await _push(c);
    _syncService.listenToParty(
      roomCode: room,
      onPartyUpdated: (members) {
        if (currentRoomCode != room) return;
        partyMembers = members;
        final inspected = inspectedPartyMember;
        if (inspected != null) {
          final fresh = members.where((m) => m.id == inspected.id);
          if (fresh.isNotEmpty) inspectedPartyMember = fresh.first;
        }
        notifyListeners();
      },
      onError: (e) {
        syncError = e.toString();
        notifyListeners();
      },
    );
  }

  void leaveRoom() {
    _syncService.disconnect();
    _syncDebounce?.cancel();
    currentRoomCode = null;
    partyMembers = [];
    inspectedPartyMember = null;
    notifyListeners();
  }

  void inspectPartyMember(Character? member) {
    inspectedPartyMember = (member == null || member.id == _active?.id)
        ? null
        : member;
    notifyListeners();
  }

  Future<void> _persist(Character c) async {
    try {
      await _storage.save(c);
      _status = SaveStatus.saved;
      lastError = null;
    } catch (e) {
      _status = SaveStatus.error;
      lastError = e.toString();
    }
    notifyListeners();
  }

  /// Immediately writes any pending change.
  Future<void> flush() async {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      if (_active != null) await _persist(_active!);
    }
  }

  void _sortCharacters() => _characters.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );

  Future<void> createCharacter() async {
    await flush();
    final c = defaultCharacter();
    _characters.add(c);
    _sortCharacters();
    _active = c;
    await _persist(c);
  }

  Future<void> duplicateActive() async {
    final current = _active;
    if (current == null) return;
    await flush();
    final copy = current.duplicate();
    _characters.add(copy);
    _sortCharacters();
    _active = copy;
    await _persist(copy);
  }

  Future<void> deleteActive() async {
    final current = _active;
    if (current == null) return;
    _debounce?.cancel();
    await _storage.delete(current);
    _characters.remove(current);
    if (_characters.isEmpty) {
      final starter = defaultCharacter();
      _characters.add(starter);
      await _storage.save(starter);
    }
    _active = _characters.first;
    _status = SaveStatus.saved;
    notifyListeners();
  }

  Future<void> importCharacter(String path) async {
    await flush();
    final c = await _storage.importFrom(
      path,
      _characters.map((e) => e.id).toSet(),
    );
    _characters.add(c);
    _sortCharacters();
    _active = c;
    notifyListeners();
  }

  Future<void> exportActive(String path) async {
    final current = _active;
    if (current == null) return;
    await _storage.exportTo(current, path);
  }

  void longRest() => mutate((c) => c.longRest());

  @override
  void dispose() {
    _debounce?.cancel();
    _syncDebounce?.cancel();
    _syncService.disconnect();
    super.dispose();
  }
}
