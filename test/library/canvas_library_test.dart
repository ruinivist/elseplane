import 'package:elseplane/library/canvas_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('derives root-relative canvas parent and serialized paths', () {
    final library = CanvasLibrary(
      currentId: 'map',
      files: [
        CanvasFile(id: 'root', name: 'Root', document: CanvasLibrary.emptyDocument),
        const CanvasFile(id: 'school', name: 'School'),
        const CanvasFile(id: 'room', name: 'Room 2', parentId: 'school'),
        CanvasFile(id: 'map', name: 'Map', parentId: 'room', document: CanvasLibrary.emptyDocument),
      ],
    );

    expect(library.parentDirectory('root'), '');
    expect(library.parentDirectory('map'), 'School/Room 2');
    expect(library.serializedPath('map'), 'School/Room 2/Map.canvas.json');
    expect(() => library.serializedPath('school'), throwsArgumentError);
    library.validatePaths();
  });

  test('allows literal case variants and reserved words as canvas titles', () {
    final library = CanvasLibrary(
      currentId: 'canvas',
      files: [
        CanvasFile(id: 'canvas', name: 'attachments', document: CanvasLibrary.emptyDocument),
        const CanvasFile(id: 'folder1', name: 'School'),
        const CanvasFile(id: 'folder2', name: 'school'),
      ],
    )..validatePaths();
    expect(library.serializedPath('canvas'), 'attachments.canvas.json');
    expect(library.nameError('attachments', null, isFolder: true), isNotNull);
    expect(library.nameError('.git', null, isFolder: true), isNotNull);
  });

  test('path validation preserves literal imported whitespace while local names trim', () {
    final literalLibrary = CanvasLibrary(
      currentId: 'canvas',
      files: [CanvasFile(id: 'canvas', name: '  Map  ', document: CanvasLibrary.emptyDocument)],
    );
    final localLibrary = CanvasLibrary(
      currentId: 'canvas',
      files: [CanvasFile(id: 'canvas', name: 'Map', document: CanvasLibrary.emptyDocument)],
    );

    literalLibrary.validatePaths();
    expect(literalLibrary.serializedPath('canvas'), '  Map  .canvas.json');
    expect(localLibrary.nameError('  Map  ', null), 'This name is already in use');
  });

  test('rejects unsafe literal names and serialized file-directory collisions', () {
    final library = CanvasLibrary(
      currentId: 'canvas',
      files: [CanvasFile(id: 'canvas', name: 'Map', document: CanvasLibrary.emptyDocument)],
    );

    for (final name in ['', '.', '..', 'School/Room', r'School\Room', 'https:Map', 'C:Map']) {
      expect(library.nameError(name, null), isNotNull, reason: name);
    }
    expect(library.nameError('Map.canvas.json', null, isFolder: true), isNotNull);
    expect(
      () => CanvasLibrary(
        currentId: 'map',
        files: [
          CanvasFile(id: 'map', name: 'Map', document: CanvasLibrary.emptyDocument),
          const CanvasFile(id: 'folder', name: 'Map.canvas.json'),
        ],
      ).validatePaths(),
      throwsFormatException,
    );
  });

  test('rejects slashes in directly constructed names', () {
    final library = CanvasLibrary(
      currentId: 'canvas',
      files: [CanvasFile(id: 'canvas', name: 'School/Room', document: CanvasLibrary.emptyDocument)],
    );

    expect(library.nameError('School/Room', null), isNotNull);
    expect(library.validatePaths, throwsFormatException);
  });

  test('rejects reserved folders anywhere in a hierarchy and canvas path prefixes', () {
    expect(
      () => CanvasLibrary(
        currentId: 'canvas',
        files: [
          const CanvasFile(id: 'folder', name: 'Projects'),
          const CanvasFile(id: 'reserved', name: '.git', parentId: 'folder'),
          CanvasFile(id: 'canvas', name: 'Map', parentId: 'reserved', document: CanvasLibrary.emptyDocument),
        ],
      ).validatePaths(),
      throwsFormatException,
    );

    final library = CanvasLibrary(
      currentId: 'canvas',
      files: [
        CanvasFile(id: 'canvas', name: 'Project', document: CanvasLibrary.emptyDocument),
        const CanvasFile(id: 'folder', name: 'Destination'),
        const CanvasFile(id: 'collision', name: 'Project.canvas.json', parentId: 'folder'),
      ],
    );
    expect(() => library.move('canvas', parentId: 'folder'), throwsFormatException);
  });
}
