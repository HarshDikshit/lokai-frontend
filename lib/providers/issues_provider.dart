import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../core/app_constants.dart';

// ── Issues list (with polling) ────────────────────────────────────────────────
class IssuesNotifier extends StateNotifier<AsyncValue<List<Issue>>> {
  final _api = ApiService.instance;
  Timer? _pollingTimer;
  String? _statusFilter;
  String? _categoryFilter;

  IssuesNotifier() : super(const AsyncValue.loading()) {
    fetchIssues();
    _startPolling();
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
    super.dispose();
  }
}

final issuesProvider =
    StateNotifierProvider<IssuesNotifier, AsyncValue<List<Issue>>>(
        (ref) => IssuesNotifier());

// ── Single issue — StreamProvider so invalidate() immediately rebuilds UI ────
// Using a StateNotifierProvider so the screen can manually trigger a refresh
// AND the provider re-fetches properly on invalidate() without stale cache.
class IssueDetailNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final String issueId;
  IssueDetailNotifier(this.issueId) : super(const AsyncValue.loading()) {
    fetch();
  }

  Future<void> fetch() async {
    // Keep existing data visible while reloading (no flicker to loading spinner)
    if (state is AsyncData) {
      state = AsyncValue.data((state as AsyncData).value);
    }
    try {
      final data = await ApiService.instance.getIssue(issueId);
      state = AsyncValue.data(data);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final issueDetailProvider = StateNotifierProvider.family<
    IssueDetailNotifier, AsyncValue<Map<String, dynamic>>, String>(
  (ref, id) => IssueDetailNotifier(id),
);

// ── Escalated issues (higher authority view) ──────────────────────────────────
class EscalatedIssuesNotifier extends StateNotifier<AsyncValue<List<Issue>>> {
  final _api = ApiService.instance;
  Timer? _pollingTimer;

  EscalatedIssuesNotifier() : super(const AsyncValue.loading()) {
    _fetch();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: ApiConstants.pollingIntervalSeconds),
      (_) => _fetch(),
    );
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
    super.dispose();
  }
}

final escalatedIssuesProvider =
    StateNotifierProvider<EscalatedIssuesNotifier, AsyncValue<List<Issue>>>(
        (ref) => EscalatedIssuesNotifier());

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
class FeedNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  FeedNotifier() : super(const AsyncValue.loading()) {
    fetch();
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

  void updatePost(Map<String, dynamic> updated) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.map((p) {
      return p['id'] == updated['id'] ? updated : p;
    }).toList());
  }

  void prependPost(Map<String, dynamic> post) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([post, ...current]);
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier,
    AsyncValue<List<Map<String, dynamic>>>>((ref) => FeedNotifier());