// models/issue.dart
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

  Issue({
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

  factory Issue.fromJson(Map<String, dynamic> json) {
    return Issue(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      category: json['category'],
      priorityScore: (json['priority_score'] as num?)?.toDouble(),
      urgencyLevel: json['urgency_level'],
      location: json['location'],
      userId: json['user_id'] ?? '',
      leaderId: json['leader_id'],
      resolutionAttempts: json['resolution_attempts'] ?? 0,
      status: json['status'] ?? 'OPEN',
      imageUrls: List<String>.from(json['image_urls'] ?? []),
      audioUrl: json['audio_url'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      citizenName: json['citizen_name'],
      leaderName: json['leader_name'],
    );
  }
}

class Task {
  final String id;
  final String issueId;
  final String assignedTo;
  final DateTime deadline;
  final String status;
  final String? description;
  final DateTime createdAt;
  final String? issueTitle;
  final String? assigneeName;

  Task({
    required this.id,
    required this.issueId,
    required this.assignedTo,
    required this.deadline,
    required this.status,
    this.description,
    required this.createdAt,
    this.issueTitle,
    this.assigneeName,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] ?? '',
      issueId: json['issue_id'] ?? '',
      assignedTo: json['assigned_to'] ?? '',
      deadline: DateTime.tryParse(json['deadline'] ?? '') ?? DateTime.now(),
      status: json['status'] ?? 'pending',
      description: json['description'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      issueTitle: json['issue_title'],
      assigneeName: json['assignee_name'],
    );
  }
}

class User {
  final String id;
  final String name;
  final String email;
  final String role;
  final int failedCases;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.failedCases,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      failedCases: json['failed_cases'] ?? 0,
    );
  }
}

class LeaderMetrics {
  final int totalIssues;
  final int completedTasks;
  final int pendingTasks;
  final int escalatedCases;
  final int failedCases;
  final int activeProblems;

  LeaderMetrics({
    required this.totalIssues,
    required this.completedTasks,
    required this.pendingTasks,
    required this.escalatedCases,
    required this.failedCases,
    required this.activeProblems,
  });

  factory LeaderMetrics.fromJson(Map<String, dynamic> json) {
    return LeaderMetrics(
      totalIssues: json['total_issues'] ?? 0,
      completedTasks: json['completed_tasks'] ?? 0,
      pendingTasks: json['pending_tasks'] ?? 0,
      escalatedCases: json['escalated_cases'] ?? 0,
      failedCases: json['failed_cases'] ?? 0,
      activeProblems: json['active_problems'] ?? 0,
    );
  }
}