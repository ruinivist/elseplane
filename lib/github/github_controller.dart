// Owns the in-memory GitHub account session and logout retry state.

import 'package:elseplane/github/github_api.dart';
import 'package:flutter/foundation.dart';

class GitHubController extends ChangeNotifier {
  GitHubController(this.api);

  final GitHubApi api;
  GitHubAccount? account;
  String? error;
  bool busy = false;
  bool logoutNeedsRetry = false;
  bool _disposed = false;

  Future<void> restoreSession({required bool shouldCheck}) async {
    if (!shouldCheck || busy) return;
    await _run(() async {
      try {
        account = await api.account();
        logoutNeedsRetry = false;
        error = null;
      } on Object catch (failure) {
        account = null;
        error = _message(failure);
      }
    });
  }

  Future<void> logout() async {
    account = null;
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
    try {
      final result = await operation();
      error = null;
      return result;
    } on GitHubApiException catch (failure) {
      if (failure.kind == GitHubErrorKind.reconnect || failure.kind == GitHubErrorKind.insufficientScope) {
        account = null;
        error = _message(failure);
      }
      rethrow;
    }
  });

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

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String _message(Object failure) => switch (failure) {
    GitHubApiException(:final message) => message,
    _ => 'Could not connect to GitHub. Try again.',
  };
}
