import 'package:elseplane/attachments/attachment_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reference = 'attachments/123e4567-e89b-42d3-a456-426614174000.png';

  test('canvas references stay strict and resolver preserves literal paths', () {
    expect(isCanvasAttachmentReference(reference), isTrue);
    expect(isCanvasAttachmentReference('School/$reference'), isFalse);
    expect(isCanvasAttachmentReference('https://example.com/$reference'), isFalse);
    expect(resolveAttachmentPath('', reference), reference);
    expect(resolveAttachmentPath('School/Room 2/Å', reference), 'School/Room 2/Å/$reference');
    expect(resolveAttachmentPath('School', reference), isNot(resolveAttachmentPath('Work', reference)));
  });

  test('full keys validate and filename keeps the exact leaf', () {
    const path = ' School /Folder %/café/attachments/123e4567-e89b-42d3-a456-426614174000.webp';
    validateAttachmentPath(path);
    expect(attachmentFileName(path), '123e4567-e89b-42d3-a456-426614174000.webp');
  });

  test('full keys reject unsafe structure and filenames', () {
    for (final path in <String>[
      '',
      '/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'attachments/123e4567-e89b-42d3-a456-426614174000.png/',
      'Folder//attachments/123e4567-e89b-42d3-a456-426614174000.png',
      './attachments/123e4567-e89b-42d3-a456-426614174000.png',
      '../attachments/123e4567-e89b-42d3-a456-426614174000.png',
      r'Folder\attachments\123e4567-e89b-42d3-a456-426614174000.png',
      'Folder\u0000/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'Folder\u007f/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'Folder\u0085/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'C:/Folder/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'Folder/C:/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'file:attachments/123e4567-e89b-42d3-a456-426614174000.png',
      '//host/attachments/123e4567-e89b-42d3-a456-426614174000.png',
      'attachments/123E4567-e89b-42d3-a456-426614174000.png',
      'attachments/123e4567-e89b-42d3-a456-426614174000.PNG',
      'attachments/123e4567-e89b-42d3-a456-426614174000.svg',
      'Folder/attachments/123e4567-e89b-42d3-a456-426614174000.png/more',
    ]) {
      expect(() => validateAttachmentPath(path), throwsFormatException, reason: path);
    }
  });

  test('resolver validates relative references and directory spelling', () {
    for (final directory in <String>[
      '/',
      'School/',
      'School//Room',
      '../School',
      r'School\Room',
      'C:/School',
      'https:School',
    ]) {
      expect(() => resolveAttachmentPath(directory, reference), throwsFormatException, reason: directory);
    }
    for (final value in <String>['School/$reference', 'attachments/not-a-uuid.png', 'file:///$reference']) {
      expect(() => resolveAttachmentPath('', value), throwsFormatException, reason: value);
    }
  });
}
