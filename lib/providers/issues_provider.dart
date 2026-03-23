import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../core/app_constants.dart';

// ── Issues list (with polling) ────────────────────────────────────────────────
class IssuesNotifier extends Notifier<AsyncValue<List<Issue>>> {
  final _api = ApiService.instance;
  Timer? _pollingTimer;
  String? _statusFilter;
  String? _categoryFilter;

  @override
  AsyncValue<List<Issue>> build() {
    // Start polling and fetch initial data after first build
    Future.microtask(() {
      fetchIssues();
      _startPolling();
    });
    return const AsyncValue.loading();
  }

  void setFilters({String? status, String? category}) {
    _statusFilter  = status;
    _categoryFilter = category;
    fetchIssues();
  }

  Future<void> fetchIssues() async {
    try {
      final data   = await _api.getIssues(
        status:   _statusFilter,
        category: _categoryFilter,
      );
      final issues = data.map((j) => Issue.fromJson(j)).toList();
      state = AsyncValue.data(issues);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(
      const Duration(seconds: ApiConstants.pollingIntervalSeconds),
      (_) => fetchIssues(),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    // In Notifier, dispose logic might need to be handled differently 
    // but many side effects are cleaned up by the provider.
  }
}

final issuesProvider = NotifierProvider<IssuesNotifier, AsyncValue<List<Issue>>>(() {
  return IssuesNotifier();
});

// ── Single issue — StreamProvider so invalidate() immediately rebuilds UI ────
// Using a StateNotifierProvider so the screen can manually trigger a refresh
// AND the provider re-fetches properly on invalidate() without stale cache.
final issueDetailProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return await ApiService.instance.getIssue(id);
});

// ── Escalated issues (higher authority view) ──────────────────────────────────
class EscalatedIssuesNotifier extends Notifier<AsyncValue<List<Issue>>> {
  final _api = ApiService.instance;
  Timer? _pollingTimer;

  @override
  AsyncValue<List<Issue>> build() {
    Future.microtask(() {
      _fetch();
      _pollingTimer = Timer.periodic(
        const Duration(seconds: ApiConstants.pollingIntervalSeconds),
        (_) => _fetch(),
      );
    });
    return const AsyncValue.loading();
  }

  Future<void> _fetch() async {
    try {
      final data   = await _api.getEscalatedIssues();
      final issues = data.map((j) => Issue.fromJson(j)).toList();
      state = AsyncValue.data(issues);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
  }
}

final escalatedIssuesProvider = NotifierProvider<EscalatedIssuesNotifier, AsyncValue<List<Issue>>>(() {
  return EscalatedIssuesNotifier();
});

// ── Dashboards ────────────────────────────────────────────────────────────────
final authorityDashboardProvider = FutureProvider<Map<String, dynamic>>(
    (ref) => ApiService.instance.getAuthorityDashboard());

final leaderDashboardProvider = FutureProvider<Map<String, dynamic>>(
    (ref) => ApiService.instance.getLeaderDashboard());

final citizenDashboardProvider = FutureProvider<Map<String, dynamic>>(
    (ref) => ApiService.instance.getCitizenDashboard());

final adminDashboardProvider = FutureProvider<Map<String, dynamic>>(
    (ref) => ApiService.instance.getAdminDashboard());

// ── Users ─────────────────────────────────────────────────────────────────────
final usersProvider = FutureProvider.family<List<User>, String?>((ref, role) async {
  final data = await ApiService.instance.getUsers(role: role);
  return data.map((j) => User.fromJson(j)).toList();
});


// ── Feed provider ─────────────────────────────────────────────────────────────
class FeedNotifier extends Notifier<AsyncValue<List<Map<String, dynamic>>>> {
  @override
  AsyncValue<List<Map<String, dynamic>>> build() {
    Future.microtask(() => fetch());
    return const AsyncValue.loading();
  }

  Future<void> fetch() async {
    try {
      final data = await ApiService.instance.getFeed();
      state = AsyncValue.data(List<Map<String, dynamic>>.from(
          data.map((e) => Map<String, dynamic>.from(e))));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  List<Map<String, dynamic>> _current() {
    return switch (state) {
      AsyncData(value: final v) => v,
      _ => [],
    };
  }

  void updatePost(Map<String, dynamic> updated) {
    final current = _current();
    state = AsyncValue.data(current.map((p) {
      return p['id'] == updated['id'] ? updated : p;
    }).toList());
  }

  void prependPost(Map<String, dynamic> post) {
    final current = _current();
    state = AsyncValue.data([post, ...current]);
  }
}

final feedProvider = NotifierProvider<FeedNotifier,
    AsyncValue<List<Map<String, dynamic>>>>(() => FeedNotifier());

