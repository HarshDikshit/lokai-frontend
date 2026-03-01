import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/models.dart';

// Issues list provider with polling
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
    _statusFilter = status;
    _categoryFilter = category;
    fetchIssues();
  }

  Future<void> fetchIssues() async {
    try {
      final data = await _api.getIssues(
        status: _statusFilter,
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
      const Duration(seconds: 10),
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
    StateNotifierProvider<IssuesNotifier, AsyncValue<List<Issue>>>((ref) {
  return IssuesNotifier();
});

// Single issue provider
final issueDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return ApiService.instance.getIssue(id);
});

// Tasks provider with polling
class TasksNotifier extends StateNotifier<AsyncValue<List<Task>>> {
  final _api = ApiService.instance;
  Timer? _pollingTimer;

  TasksNotifier() : super(const AsyncValue.loading()) {
    fetchTasks();
    _startPolling();
  }

  Future<void> fetchTasks({String? status}) async {
    try {
      final data = await _api.getTasks(status: status);
      final tasks = data.map((j) => Task.fromJson(j)).toList();
      state = AsyncValue.data(tasks);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => fetchTasks(),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}

final tasksProvider =
    StateNotifierProvider<TasksNotifier, AsyncValue<List<Task>>>((ref) {
  return TasksNotifier();
});

// Leader dashboard provider
final leaderDashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ApiService.instance.getLeaderDashboard();
});

// Citizen dashboard provider
final citizenDashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ApiService.instance.getCitizenDashboard();
});

// Admin dashboard provider
final adminDashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ApiService.instance.getAdminDashboard();
});

// Users provider
final usersProvider = FutureProvider.family<List<User>, String?>((ref, role) async {
  final data = await ApiService.instance.getUsers(role: role);
  return data.map((j) => User.fromJson(j)).toList();
});

// Escalated issues provider
class EscalatedIssuesNotifier extends StateNotifier<AsyncValue<List<Issue>>> {
  final _api = ApiService.instance;
  Timer? _pollingTimer;

  EscalatedIssuesNotifier() : super(const AsyncValue.loading()) {
    fetchEscalated();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => fetchEscalated(),
    );
  }

  Future<void> fetchEscalated() async {
    try {
      final data = await _api.getEscalatedIssues();
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
    StateNotifierProvider<EscalatedIssuesNotifier, AsyncValue<List<Issue>>>((ref) {
  return EscalatedIssuesNotifier();
});