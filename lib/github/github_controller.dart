// Owns the in-memory GitHub account session and discovery state.

import 'package:elseplane/github/github_api.dart';
import 'package:flutter/foundation.dart';

class GitHubController extends ChangeNotifier {
  GitHubController(this.api);

  final GitHubApi api;
  GitHubAccount? account;
  List<GitHubInstallation> installations = const [];
  List<GitHubRepository> repositories = const [];
  String? error;
  String? discoveryError;
  bool busy = false;
  bool discoveryLoading = false;
  bool logoutNeedsRetry = false;
  bool _disposed = false;
  int _generation = 0;
  int _discoveryGeneration = 0;

  Future<void> restoreSession() async {
    // Restore before a destination is saved so the first repository selection is ready.
    if (busy || _disposed) return;
    final generation = ++_generation;
    _discoveryGeneration++;
    await _run(() async {
      try {
        final verified = await api.account();
        if (!_isCurrent(generation)) return;
        if (account?.id != null && account!.id != verified.id) _clearRepositories();
        account = verified;
        logoutNeedsRetry = false;
        error = null;
        _notifyListeners();
        await _loadRepositories(generation);
      } on GitHubApiException catch (failure) {
        if (!_isCurrent(generation)) return;
        _clearAccount(
          error: failure.kind == GitHubErrorKind.reconnect ? null : _message(failure),
        );
      } on Object catch (failure) {
        if (!_isCurrent(generation)) return;
        _clearAccount(error: _message(failure));
      }
    });
  }

  Future<void> refreshRepositories() async {
    if (account == null || _disposed) return;
    final generation = _generation;
    await _run(() => _loadRepositories(generation));
  }

  Future<void> logout() async {
    _generation++;
    _discoveryGeneration++;
    account = null;
    installations = const [];
    repositories = const [];
    discoveryLoading = false;
    discoveryError = null;
    logoutNeedsRetry = true;
    error = null;
    _notifyListeners();
    await _run(() async {
      try {
        await api.logout();
        logoutNeedsRetry = false;
        error = null;
      } on Object catch (failure) {
        error = _message(failure);
        rethrow;
      }
    });
  }

  Future<T> run<T>(Future<T> Function() operation) => _run(() async {
    final generation = _generation;
    try {
      final result = await operation();
      if (_isCurrent(generation)) error = null;
      return result;
    } on GitHubApiException catch (failure) {
      if (_isCurrent(generation) && failure.kind == GitHubErrorKind.reconnect) {
        _clearAccount(error: _message(failure));
      }
      rethrow;
    }
  });

  Future<void> _loadRepositories(int generation) async {
    final request = ++_discoveryGeneration;
    discoveryLoading = true;
    discoveryError = null;
    _notifyListeners();
    try {
      final result = await api.discoverRepositories();
      if (!_isCurrent(generation) || request != _discoveryGeneration) return;
      installations = List.unmodifiable(result.installations);
      repositories = List.unmodifiable(result.repositories);
      discoveryError = null;
    } on GitHubApiException catch (failure) {
      if (!_isCurrent(generation) || request != _discoveryGeneration) return;
      if (failure.kind == GitHubErrorKind.reconnect) {
        _clearAccount(error: _message(failure));
      } else {
        discoveryError = _message(failure);
      }
    } on Object catch (failure) {
      if (!_isCurrent(generation) || request != _discoveryGeneration) return;
      discoveryError = _message(failure);
    } finally {
      if (_isCurrent(generation) && request == _discoveryGeneration) {
        discoveryLoading = false;
        _notifyListeners();
      }
    }
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    if (busy) throw StateError('A GitHub account operation is already active');
    busy = true;
    _notifyListeners();
    try {
      return await operation();
    } finally {
      busy = false;
      _notifyListeners();
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _clearRepositories() {
    installations = const [];
    repositories = const [];
    discoveryError = null;
    discoveryLoading = false;
    _discoveryGeneration++;
  }

  void _clearAccount({required String? error}) {
    _generation++;
    account = null;
    _clearRepositories();
    this.error = error;
    _notifyListeners();
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _discoveryGeneration++;
    super.dispose();
  }

  String _message(Object failure) => switch (failure) {
    GitHubApiException(:final message) => message,
    _ => 'Could not connect to GitHub. Try again.',
  };
}
