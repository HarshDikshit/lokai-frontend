import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';
import '../core/app_constants.dart';

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final String? token;
  final String? role;
  final String? userId;
  final String? userName;
  final String? error;

  AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.token,
    this.role,
    this.userId,
    this.userName,
    this.error,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    String? token,
    String? role,
    String? userId,
    String? userName,
    String? error,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      token: token ?? this.token,
      role: role ?? this.role,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final _storage = const FlutterSecureStorage();
  final _api = ApiService.instance;

  AuthNotifier() : super(AuthState()) {
    _loadStoredAuth();
  }

  Future<void> _loadStoredAuth() async {
    final token = await _storage.read(key: AppConstants.tokenKey);
    final role = await _storage.read(key: AppConstants.roleKey);
    final userId = await _storage.read(key: AppConstants.userIdKey);
    final userName = await _storage.read(key: AppConstants.userNameKey);

    if (token != null) {
      state = state.copyWith(
        isAuthenticated: true,
        token: token,
        role: role,
        userId: userId,
        userName: userName,
      );
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _api.login(email: email, password: password);
      await _saveAuthData(data);
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        token: data['access_token'],
        role: data['role'],
        userId: data['user_id'],
        userName: data['name'],
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _parseError(e),
      );
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String role,
    String? phone,                        // ← add
    Map<String, String>? leaderLocation,  // ← add
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _api.register(
        name: name, email: email, password: password, role: role, phone: phone, leaderLocation: leaderLocation,
      );
      await _saveAuthData(data);
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        token: data['access_token'],
        role: data['role'],
        userId: data['user_id'],
        userName: data['name'],
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    state = AuthState();
  }

  Future<void> _saveAuthData(Map<String, dynamic> data) async {
    await _storage.write(key: AppConstants.tokenKey, value: data['access_token']);
    await _storage.write(key: AppConstants.roleKey, value: data['role']);
    await _storage.write(key: AppConstants.userIdKey, value: data['user_id']);
    await _storage.write(key: AppConstants.userNameKey, value: data['name']);
  }

  String _parseError(dynamic e) {
    if (e.toString().contains('401')) return 'Invalid email or password';
    if (e.toString().contains('400')) return 'Email already registered';
    return 'An error occurred. Please try again.';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});