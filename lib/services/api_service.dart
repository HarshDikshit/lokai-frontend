import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart';
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

  /// Step 1 of resolution — upload before/after photos to /verifications.
  /// Backend stores them in Cloudinary and returns the image URLs.
  /// Always call this BEFORE [resolveIssue] when photos are present.
  Future<Map<String, dynamic>> uploadVerification({
    required String issueId,
    String? beforeImagePath,
    String? afterImagePath,
    double? latitude,
    double? longitude,
  }) async {
    final formData = FormData();
    formData.fields.add(MapEntry('issue_id', issueId));
    if (latitude != null) formData.fields.add(MapEntry('latitude', latitude.toString()));
    if (longitude != null) formData.fields.add(MapEntry('longitude', longitude.toString()));

    if (beforeImagePath != null) {
      final ext = beforeImagePath.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      formData.files.add(MapEntry(
        'before_image',
        await MultipartFile.fromFile(
          beforeImagePath,
          filename: 'before.$ext',
          contentType: MediaType('image', ext),
        ),
      ));
    }

    if (afterImagePath != null) {
      final ext = afterImagePath.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      formData.files.add(MapEntry(
        'after_image',
        await MultipartFile.fromFile(
          afterImagePath,
          filename: 'after.$ext',
          contentType: MediaType('image', ext),
        ),
      ));
    }

    final res = await _dio.post(
      ApiConstants.verifications,
      data: formData,
      options: Options(
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    return res.data as Map<String, dynamic>;
  }

  /// Step 2 of resolution — mark issue as resolved with plain JSON notes.
  /// Backend updates status to RESOLVED_L1 / RESOLVED_L2.
  Future<Map<String, dynamic>> resolveIssue(
    String id,
    String notes,
  ) async {
    final res = await _dio.post(
      '${ApiConstants.issues}/$id/resolve',
      data: {'resolution_notes': notes},
    );
    return res.data;
  }

  Future<Map<String, dynamic>> getVerification(String issueId) async {
    final res = await _dio.get('${ApiConstants.verifications}/$issueId');
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

  // ── Dashboard ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getLeaderDashboard() async {
    final res = await _dio.get(ApiConstants.leaderDashboard);
    return res.data;
  }

  // ── Feed ─────────────────────────────────────────────────────────────────
  Future<List<dynamic>> getFeed({int skip = 0, int limit = 20}) async {
    final res = await _dio.get(ApiConstants.feed,
        queryParameters: {'skip': skip, 'limit': limit});
    return res.data;
  }

  Future<Map<String, dynamic>> createPost({
    required String content,
    String? imageUrl,
    String? tag,
  }) async {
    final res = await _dio.post(ApiConstants.feed, data: {
      'content': content,
      if (imageUrl != null) 'image_url': imageUrl,
      if (tag != null) 'tag': tag,
    });
    return res.data;
  }

  Future<Map<String, dynamic>> togglePostLike(String postId) async {
    final res = await _dio.post('${ApiConstants.feed}/$postId/like');
    return res.data;
  }

  Future<void> sharePost(String postId) async {
    await _dio.post('${ApiConstants.feed}/$postId/share');
  }

  Future<Map<String, dynamic>> addComment(
      String postId, String text, {String? parentId}) async {
    final res = await _dio.post('${ApiConstants.feed}/$postId/comments', data: {
      'text': text,
      if (parentId != null) 'parent_id': parentId,
    });
    return res.data;
  }

  Future<Map<String, dynamic>> toggleCommentLike(
      String postId, String commentId) async {
    final res = await _dio.post(
        '${ApiConstants.feed}/$postId/comments/$commentId/like');
    return res.data;
  }


  // ── Duplicate / Cluster ───────────────────────────────────────────────────
  Future<Map<String, dynamic>> getSimilarIssues({
    required String description,
    required double latitude,
    required double longitude,
    String? category,
  }) async {
    final res = await _dio.get('/issues/similar', queryParameters: {
      'description': description,
      'latitude':    latitude,
      'longitude':   longitude,
      if (category != null) 'category': category,
    });
    return res.data;
  }

  Future<Map<String, dynamic>> supportIssue(String issueId) async {
    final res = await _dio.post('/issues/$issueId/support');
    return res.data;
  }

  Future<List<dynamic>> getReviewQueue() async {
    final res = await _dio.get('/issues/review/queue');
    return (res.data['items'] as List?) ?? [];
  }

  Future<Map<String, dynamic>> decideReview(
      String reviewId, String decision) async {
    final res = await _dio.post(
        '/issues/review/$reviewId/decide',
        queryParameters: {'decision': decision});
    return res.data;
  }

  Future<Map<String, dynamic>> getAuthorityDashboard() async {
    final res = await _dio.get(ApiConstants.authorityDashboard);
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

  // ── Social Monitor ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getSocialMonitor() async {
    // 1. Try to read from local cache first
    try {
      final cachedJson = await _storage.read(key: 'social_monitor_cache');
      final cachedTime = await _storage.read(key: 'social_monitor_timestamp');

      if (cachedJson != null && cachedTime != null) {
        final timestamp = DateTime.tryParse(cachedTime);
        if (timestamp != null) {
          final diff = DateTime.now().difference(timestamp);
          // If less than 12 hours old, return cached data
          if (diff.inHours < 12) {
            return jsonDecode(cachedJson) as Map<String, dynamic>;
          }
        }
      }
    } catch (_) {
      // If cache reading fails, just proceed to fetch fresh
    }

    // 2. Fetch fresh data from backend
    final res = await _dio.get(ApiConstants.socialMonitor);

    // 3. Save to persistent cache for 12 hours
    try {
      await _storage.write(key: 'social_monitor_cache', value: jsonEncode(res.data));
      await _storage.write(key: 'social_monitor_timestamp', value: DateTime.now().toIso8601String());
    } catch (_) {
      // If cache writing fails, it's fine, we still return the fresh data
    }

    return res.data;
  }

  Future<Map<String, dynamic>> assignSocialPost({
    required Map<String, dynamic> post,
    required String leaderId,
  }) async {
    final res = await _dio.post(ApiConstants.socialAssign, data: {
      'post': post,
      'leader_id': leaderId,
    });
    return res.data;
  }
}