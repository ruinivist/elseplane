// Reads and writes immutable library snapshots through an injectable contract.
import 'package:elseplane/library/canvas_library.dart';

abstract interface class LibraryStore {
  Future<CanvasLibrary?> load();

  /// Applies [next] against its last durable [previous] snapshot atomically.
  /// A null [previous] means there is no saved library yet.
  Future<void> save(CanvasLibrary next, {required CanvasLibrary? previous});
}
