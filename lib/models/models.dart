// ── Issue ─────────────────────────────────────────────────────────────────────
class Issue {
  final String id;
  final String title;
  final String description;
  final String? category;
  final double? priorityScore;
  final String? urgencyLevel;
  final Map<String, dynamic>? location;
  final String userId;
  final String? leaderId;
  final int resolutionAttempts;
  final String status;
  final List<String> imageUrls;
  final String? audioUrl;
  final DateTime createdAt;
  final String? citizenName;
  final String? leaderName;

  const Issue({
    required this.id,
    required this.title,
    required this.description,
    this.category,
    this.priorityScore,
    this.urgencyLevel,
    this.location,
    required this.userId,
    this.leaderId,
    required this.resolutionAttempts,
    required this.status,
    required this.imageUrls,
    this.audioUrl,
    required this.createdAt,
    this.citizenName,
    this.leaderName,
  });

  factory Issue.fromJson(Map<String, dynamic> json) => Issue(
        id:                  json['id']          ?? '',
        title:               json['title']        ?? '',
        description:         json['description']  ?? '',
        category:            json['category'],
        priorityScore:       (json['priority_score'] as num?)?.toDouble(),
        urgencyLevel:        json['urgency_level'],
        location:            json['location'] != null
                               ? Map<String, dynamic>.from(json['location'])
                               : null,
        userId:              json['user_id']    ?? '',
        leaderId:            json['leader_id'],
        resolutionAttempts:  json['resolution_attempts'] ?? 0,
        status:              json['status']     ?? 'OPEN',
        // Backend may return image_url (single str) or image_urls (list)
        imageUrls:           _parseImageUrls(json),
        audioUrl:            json['audio_url'],
        createdAt:           DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        citizenName:         json['citizen_name'],
        leaderName:          json['leader_name'],
      );

  static List<String> _parseImageUrls(Map<String, dynamic> json) {
    if (json['image_urls'] != null) {
      return List<String>.from(json['image_urls']);
    }
    if (json['image_url'] != null) {
      return [json['image_url'] as String];
    }
    return [];
  }

  /// True when the issue is waiting for citizen feedback after a resolution.
  /// Leader must NOT push another resolution while this is true.
  bool get awaitingCitizenFeedback =>
      status == 'RESOLVED_L1' || status == 'RESOLVED_L2';

  /// True when the leader can act (submit a new resolution).
  bool get leaderCanResolve => status == 'OPEN';
}

// ── User ──────────────────────────────────────────────────────────────────────
class User {
  final String id;
  final String name;
  final String email;
  final String role;
  final int failedCases;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.failedCases,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id:          json['id']           ?? '',
        name:        json['name']         ?? '',
        email:       json['email']        ?? '',
        role:        json['role']         ?? '',
        failedCases: json['failed_cases'] ?? 0,
      );
}

// ── LeaderMetrics ─────────────────────────────────────────────────────────────
class LeaderMetrics {
  final int totalIssues;
  final int closedIssues;
  final int escalatedCases;
  final int failedCases;
  final int activeProblems;

  const LeaderMetrics({
    required this.totalIssues,
    required this.closedIssues,
    required this.escalatedCases,
    required this.failedCases,
    required this.activeProblems,
  });

  factory LeaderMetrics.fromJson(Map<String, dynamic> json) => LeaderMetrics(
        totalIssues:    json['total_issues']    ?? 0,
        closedIssues:   json['closed_issues']   ?? 0,
        escalatedCases: json['escalated_cases'] ?? 0,
        failedCases:    json['failed_cases']    ?? 0,
        activeProblems: json['active_problems'] ?? 0,
      );
}