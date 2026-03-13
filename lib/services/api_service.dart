import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/app_constants.dart';

class ApiService {
  static ApiService? _instance;
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  ApiService._() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: AppConstants.tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) => handler.next(error),
    ));
  }

  static ApiService get instance {
    _instance ??= ApiService._();
    return _instance!;
  }

  Dio get dio => _dio;

  // ── Auth ──────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String role,
    String? phone,
    Map<String, String>? leaderLocation,
  }) async {
    final res = await _dio.post(ApiConstants.register, data: {
      'name': name,
      'email': email,
      'password': password,
      'role': role,
      if (phone != null) 'phone': phone,
      if (leaderLocation != null) 'leader_location': leaderLocation,
    });
    return res.data;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await _dio.post(ApiConstants.login, data: {
      'email': email,
      'password': password,
    });
    return res.data;
  }

  Future<Map<String, dynamic>> getMe() async {
    final res = await _dio.get(ApiConstants.me);
    return res.data;
  }

  // ── Issues ────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> createIssue(FormData formData) async {
    final res = await _dio.post(
      ApiConstants.issues,
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return res.data;
  }

  Future<List<dynamic>> getIssues({String? status, String? category}) async {
    final params = <String, dynamic>{};
    if (status != null)   params['status']   = status;
    if (category != null) params['category'] = category;
    final res = await _dio.get(ApiConstants.issues, queryParameters: params);
    return res.data;
  }

  Future<Map<String, dynamic>> getIssue(String id) async {
    final res = await _dio.get('${ApiConstants.issues}/$id');
    return res.data;
  }

  /// Resolves an issue.
  /// Sends multipart/form-data so before/after images and GPS can be
  /// included alongside resolution_notes in a single request.
  Future<Map<String, dynamic>> resolveIssue(
    String id,
    String notes, {
    String? beforeImagePath,
    String? afterImagePath,
    double? latitude,
    double? longitude,
  }) async {
    final fields = <String, dynamic>{
      'resolution_notes': notes,
      if (latitude != null)       'latitude':     latitude,
      if (longitude != null)      'longitude':    longitude,
      if (beforeImagePath != null)
        'before_image': await MultipartFile.fromFile(
            beforeImagePath, filename: 'before.jpg'),
      if (afterImagePath != null)
        'after_image': await MultipartFile.fromFile(
            afterImagePath, filename: 'after.jpg'),
    };
    final res = await _dio.post(
      '${ApiConstants.issues}/$id/resolve',
      data: FormData.fromMap(fields),
      options: Options(contentType: 'multipart/form-data'),
    );
    return res.data;
  }

  Future<Map<String, dynamic>> verifyResolution(
    String id,
    bool approved, {
    String? feedback,
  }) async {
    final res = await _dio.post('${ApiConstants.issues}/$id/verify', data: {
      'approved': approved,
      if (feedback != null) 'feedback': feedback,
    });
    return res.data;
  }

  Future<Map<String, dynamic>> overrideIssue(
    String id,
    String action, {
    String? newLeaderId,
  }) async {
    final params = <String, dynamic>{'action': action};
    if (newLeaderId != null) params['new_leader_id'] = newLeaderId;
    final res = await _dio.post(
      '${ApiConstants.issues}/$id/override',
      queryParameters: params,
    );
    return res.data;
  }

  Future<List<dynamic>> getEscalatedIssues() async {
    final res = await _dio.get(ApiConstants.escalatedIssues);
    return res.data;
  }

  // ── Tasks ─────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> createTask({
    required String issueId,
    required String assignedTo,
    required DateTime deadline,
    String? description,
  }) async {
    final res = await _dio.post(ApiConstants.tasks, data: {
      'issue_id':    issueId,
      'assigned_to': assignedTo,
      'deadline':    deadline.toIso8601String(),
      if (description != null) 'description': description,
    });
    return res.data;
  }

  Future<List<dynamic>> getTasks({String? status}) async {
    final params = <String, dynamic>{};
    if (status != null) params['status'] = status;
    final res = await _dio.get(ApiConstants.tasks, queryParameters: params);
    return res.data;
  }

  Future<Map<String, dynamic>> updateTask(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.put('${ApiConstants.tasks}/$id', data: data);
    return res.data;
  }

  // ── Dashboard ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getLeaderDashboard() async {
    final res = await _dio.get(ApiConstants.leaderDashboard);
    return res.data;
  }

  Future<Map<String, dynamic>> getAdminDashboard() async {
    final res = await _dio.get(ApiConstants.adminDashboard);
    return res.data;
  }

  Future<Map<String, dynamic>> getCitizenDashboard() async {
    final res = await _dio.get(ApiConstants.citizenDashboard);
    return res.data;
  }

  Future<List<dynamic>> getUsers({String? role}) async {
    final params = <String, dynamic>{};
    if (role != null) params['role'] = role;
    final res = await _dio.get(ApiConstants.users, queryParameters: params);
    return res.data;
  }
}