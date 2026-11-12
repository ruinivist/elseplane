// Defines immutable, non-secret GitHub metadata stored with a library.

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
