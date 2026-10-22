// Reads and writes immutable library snapshots in browser preferences.
// Used by the library controller through an injectable storage contract.

import 'dart:convert';

import 'package:elseplane/library/canvas_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------- Storage contract ----------

abstract interface class LibraryStore {
  Future<CanvasLibrary?> load();

  /// Writes the whole snapshot atomically; failure preserves the previous snapshot.
  Future<void> save(CanvasLibrary snapshot);
}

// ---------- Preferences implementation ----------

class PreferencesLibraryStore implements LibraryStore {
  PreferencesLibraryStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const libraryKey = 'elseplane.canvas.library.v1';

  final SharedPreferencesAsync _preferences;

  @override
  Future<CanvasLibrary?> load() async {
    final saved = await _preferences.getString(libraryKey);
    return saved == null ? null : CanvasLibrary.fromJson(jsonDecode(saved));
  }

  @override
  Future<void> save(CanvasLibrary snapshot) async {
    // shortcut: write the whole library atomically; split storage if saves become slow.
    await _preferences.setString(libraryKey, jsonEncode(snapshot.toJson()));
  }
}
