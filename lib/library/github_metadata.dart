// Defines immutable, non-secret GitHub metadata stored with a library.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:elseplane/attachments/attachment_store.dart';
import 'package:elseplane/canvas/document/attachment_references.dart';
import 'package:elseplane/canvas/document/canvas_document.dart';

final class GitHubDestination {
  const GitHubDestination({
    required this.accountId,
    required this.repositoryId,
    required this.owner,
    required this.repository,
    required this.branch,
  });

  factory GitHubDestination.fromJson(Object? source) {
    final json = _object(source, 'GitHub destination');
    _checkKeys(json, const ['accountId', 'repositoryId', 'owner', 'repository', 'branch']);
    final accountId = json['accountId'];
    final repositoryId = json['repositoryId'];
    if (accountId is! int || accountId <= 0 || repositoryId is! int || repositoryId <= 0) {
      throw const FormatException('Invalid GitHub account or repository id');
    }
    return GitHubDestination(
      accountId: accountId,
      repositoryId: repositoryId,
      owner: _string(json['owner'], 'owner'),
      repository: _string(json['repository'], 'repository'),
      branch: _string(json['branch'], 'branch'),
    );
  }

  final int accountId;
  final int repositoryId;
  final String owner;
  final String repository;
  final String branch;

  Map<String, Object?> toJson() => {
    'accountId': accountId,
    'repositoryId': repositoryId,
    'owner': owner,
    'repository': repository,
    'branch': branch,
  };
}

/// The last confirmed GitHub version of one local canvas.
final class GitHubBaseline {
  GitHubBaseline.capture(
    this.destination,
    this.path,
    CanvasDocument document,
    Map<String, Uint8List> files,
  ) : documentHash = hashDocument(document),
      attachmentHashes = Map.unmodifiable({
        for (final key in attachmentKeys(path, document))
          if (files[key] case final bytes?) key: sha256.convert(bytes).toString(),
      });

  GitHubBaseline._(this.destination, this.path, this.documentHash, this.attachmentHashes);

  factory GitHubBaseline.fromJson(Object? source) {
    final json = _object(source, 'GitHub baseline');
    _checkKeys(json, const ['destination', 'path', 'document', 'attachments']);
    final path = _string(json['path'], 'path');
    validateAttachmentDirectory(path);
    if (!path.endsWith('.canvas.json')) throw const FormatException('Invalid GitHub baseline canvas path');
    final attachments = _object(json['attachments'], 'GitHub baseline attachments');
    attachments.keys.forEach(validateAttachmentPath);
    return GitHubBaseline._(
      GitHubDestination.fromJson(json['destination']),
      path,
      _hash(json['document']),
      Map.unmodifiable({
        for (final entry in attachments.entries) entry.key: _hash(entry.value),
      }),
    );
  }

  final GitHubDestination destination;
  final String path;
  final String documentHash;
  final Map<String, String> attachmentHashes;

  bool isFor(GitHubDestination current) =>
      destination.accountId == current.accountId &&
      destination.repositoryId == current.repositoryId &&
      destination.branch == current.branch;

  static String hashDocument(CanvasDocument document) =>
      sha256.convert(utf8.encode(jsonEncode(document.toJson()))).toString();

  static Iterable<String> attachmentKeys(String path, CanvasDocument document) {
    final slash = path.lastIndexOf('/');
    final parent = slash < 0 ? '' : path.substring(0, slash);
    return canvasAttachmentPaths(document.elements).map((reference) => resolveAttachmentPath(parent, reference));
  }

  Future<bool> matchesAttachments(CanvasDocument document, AttachmentStore store) async {
    for (final key in attachmentKeys(path, document)) {
      final bytes = await store.readIfExists(key);
      if ((bytes == null ? null : sha256.convert(bytes).toString()) != attachmentHashes[key]) return false;
    }
    return true;
  }

  Map<String, Object?> toJson() => {
    'destination': destination.toJson(),
    'path': path,
    'document': documentHash,
    'attachments': attachmentHashes,
  };
}

String _hash(Object? value) {
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException('Invalid GitHub baseline hash');
  }
  return value;
}

Map<String, dynamic> _object(Object? source, String field) {
  if (source is! Map || source.keys.any((key) => key is! String)) {
    throw FormatException('$field must be an object with string keys');
  }
  return source.cast<String, dynamic>();
}

void _checkKeys(Map<String, dynamic> json, List<String> keys) {
  if (json.length != keys.length || json.keys.any((key) => !keys.contains(key))) {
    throw const FormatException('Invalid GitHub metadata fields');
  }
}

String _string(Object? value, String field) {
  if (value is! String || value.isEmpty) throw FormatException('Invalid GitHub metadata $field');
  return value;
}
