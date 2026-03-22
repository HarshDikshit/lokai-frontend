// models/models.dart

// ── Issue ─────────────────────────────────────────────────────────────────────
class Issue {
  final String  id;
  final String  title;
  final String  description;
  final String? category;
  final double? priorityScore;
  final String? urgencyLevel;
  final Map<String, dynamic>? location;
  final String  userId;
  final String? leaderId;
  final int     resolutionAttempts;
  final String  status;
  final List<String> imageUrls;
  final String? audioUrl;
  final DateTime createdAt;
  final String? citizenName;
  final String? leaderName;
  final String? citizenPhone;
  final String? leaderPhone;
  // ── Clustering fields ──────────────────────────────────────────────────────
  final String? issueClusterId;
  final String? matchStatus;    // "auto_merged" | "pending_review" | "new_cluster"
  final double? duplicateScore;

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
    this.citizenPhone,
    this.leaderPhone,
    this.issueClusterId,
    this.matchStatus,
    this.duplicateScore,
  });

  factory Issue.fromJson(Map<String, dynamic> json) => Issue(
    id:                 json['id']          as String? ?? '',
    title:              json['title']       as String? ?? '',
    description:        json['description'] as String? ?? '',
    category:           json['category']    as String?,
    priorityScore:      (json['priority_score']  as num?)?.toDouble(),
    urgencyLevel:       json['urgency_level']     as String?,
    location:           json['location'] != null
                            ? Map<String, dynamic>.from(json['location'] as Map)
                            : null,
    userId:             json['user_id']    as String? ?? '',
    leaderId:           json['leader_id']  as String?,
    resolutionAttempts: (json['resolution_attempts'] as num?)?.toInt() ?? 0,
    status:             json['status']     as String? ?? 'OPEN',
    imageUrls:          _parseImageUrls(json),
    audioUrl:           json['audio_url']  as String?,
    createdAt:          DateTime.tryParse(json['created_at'] as String? ?? '') ??
                            DateTime.now(),
    citizenName:        json['citizen_name']     as String?,
    leaderName:         json['leader_name']      as String?,
    citizenPhone:       (json['citizen_phone'] ?? json['phone'] ?? json['citizen_name']) as String?,
    leaderPhone:        (json['leader_phone'] ?? json['leaderPhone']) as String?,
    issueClusterId:     json['issue_cluster_id'] as String?,
    matchStatus:        json['match_status']     as String?,
    duplicateScore:     (json['duplicate_score'] as num?)?.toDouble(),
  );

  static List<String> _parseImageUrls(Map<String, dynamic> json) {
    if (json['image_urls'] != null) return List<String>.from(json['image_urls'] as List);
    if (json['image_url']  != null) return [json['image_url'] as String];
    return [];
  }

  bool get awaitingCitizenFeedback =>
      status == 'RESOLVED_L1' || status == 'RESOLVED_L2';

  bool get leaderCanResolve => status == 'OPEN';
}

// ── User ──────────────────────────────────────────────────────────────────────
class User {
  final String id;
  final String name;
  final String email;
  final String role;
  final int    failedCases;
  final String? phone;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.failedCases,
    this.phone,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id:          json['id']           as String? ?? '',
    name:        json['name']         as String? ?? '',
    email:       json['email']        as String? ?? '',
    role:        json['role']         as String? ?? '',
    failedCases: (json['failed_cases'] as num?)?.toInt() ?? 0,
    phone:       json['phone']        as String?,
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
    totalIssues:    (json['total_issues']    as num?)?.toInt() ?? 0,
    closedIssues:   (json['closed_issues']   as num?)?.toInt() ?? 0,
    escalatedCases: (json['escalated_cases'] as num?)?.toInt() ?? 0,
    failedCases:    (json['failed_cases']    as num?)?.toInt() ?? 0,
    activeProblems: (json['active_problems'] as num?)?.toInt() ?? 0,
  );
}

// ── SimilarCluster ────────────────────────────────────────────────────────────
class SimilarCluster {
  final String  clusterId;
  final String  normalizedTitle;
  final String  category;
  final int     complaintCount;
  final double  priorityScore;
  final double  similarityScore;
  final String? lastReportedAt;

  const SimilarCluster({
    required this.clusterId,
    required this.normalizedTitle,
    required this.category,
    required this.complaintCount,
    required this.priorityScore,
    required this.similarityScore,
    this.lastReportedAt,
  });

  factory SimilarCluster.fromJson(Map<String, dynamic> j) => SimilarCluster(
    clusterId:       j['cluster_id']       as String? ?? '',
    normalizedTitle: j['normalized_title'] as String? ?? '',
    category:        j['category']         as String? ?? '',
    complaintCount:  (j['complaint_count'] as num?)?.toInt()    ?? 0,
    priorityScore:   (j['priority_score']  as num?)?.toDouble() ?? 0.0,
    similarityScore: (j['similarity_score'] as num?)?.toDouble() ?? 0.0,
    lastReportedAt:  j['last_reported_at'] as String?,
  );
}

// ── IssueCreateResponse ───────────────────────────────────────────────────────
class IssueCreateResponse {
  final String  message;
  final String  issueId;
  final String? leaderId;
  final String  category;
  final double  priorityScore;
  final String? clusterId;
  final String? matchStatus;    // "auto_merged" | "pending_review" | "new_cluster"
  final double? duplicateScore;

  const IssueCreateResponse({
    required this.message,
    required this.issueId,
    this.leaderId,
    required this.category,
    required this.priorityScore,
    this.clusterId,
    this.matchStatus,
    this.duplicateScore,
  });

  factory IssueCreateResponse.fromJson(Map<String, dynamic> j) =>
      IssueCreateResponse(
        message:        j['message']         as String? ?? '',
        issueId:        j['issue_id']        as String? ?? '',
        leaderId:       j['leader_id']       as String?,
        category:       j['category']        as String? ?? '',
        priorityScore:  (j['priority_score']  as num?)?.toDouble() ?? 0.0,
        clusterId:      j['cluster_id']      as String?,
        matchStatus:    j['match_status']    as String?,
        duplicateScore: (j['duplicate_score'] as num?)?.toDouble(),
      );
}

// ── ScoreBreakdown ────────────────────────────────────────────────────────────
class ScoreBreakdown {
  final double  total;
  final double  textSim;
  final double  geoSim;
  final double  timeSim;
  final double? imgSim;
  final double  catSim;

  const ScoreBreakdown({
    required this.total,
    required this.textSim,
    required this.geoSim,
    required this.timeSim,
    this.imgSim,
    required this.catSim,
  });

  factory ScoreBreakdown.fromJson(Map<String, dynamic> j) => ScoreBreakdown(
    total:   (j['total']    as num?)?.toDouble() ?? 0.0,
    textSim: (j['text_sim'] as num?)?.toDouble() ?? 0.0,
    geoSim:  (j['geo_sim']  as num?)?.toDouble() ?? 0.0,
    timeSim: (j['time_sim'] as num?)?.toDouble() ?? 0.0,
    imgSim:  (j['img_sim']  as num?)?.toDouble(),
    catSim:  (j['cat_sim']  as num?)?.toDouble() ?? 0.0,
  );
}

// ── ReviewQueueItem ───────────────────────────────────────────────────────────
class ReviewQueueItem {
  final String  reviewId;
  final String  issueId;
  final String  clusterId;
  final double  score;
  final ScoreBreakdown? scoreBreakdown;
  final String? reason;
  final String  status;
  final String? createdAt;
  final String? issueDescription;
  final String? issueCategory;
  final String? clusterTitle;
  final int?    clusterComplaintCount;

  const ReviewQueueItem({
    required this.reviewId,
    required this.issueId,
    required this.clusterId,
    required this.score,
    this.scoreBreakdown,
    this.reason,
    required this.status,
    this.createdAt,
    this.issueDescription,
    this.issueCategory,
    this.clusterTitle,
    this.clusterComplaintCount,
  });

  factory ReviewQueueItem.fromJson(Map<String, dynamic> j) => ReviewQueueItem(
    reviewId:              j['review_id']              as String? ?? '',
    issueId:               j['issue_id']               as String? ?? '',
    clusterId:             j['cluster_id']             as String? ?? '',
    score:                 (j['score']                 as num?)?.toDouble() ?? 0.0,
    scoreBreakdown:        j['score_breakdown'] != null
        ? ScoreBreakdown.fromJson(
            j['score_breakdown'] as Map<String, dynamic>)
        : null,
    reason:                j['reason']                 as String?,
    status:                j['status']                 as String? ?? 'PENDING',
    createdAt:             j['created_at']             as String?,
    issueDescription:      j['issue_description']      as String?,
    issueCategory:         j['issue_category']         as String?,
    clusterTitle:          j['cluster_title']          as String?,
    clusterComplaintCount: (j['cluster_complaint_count'] as num?)?.toInt(),
  );
}

// ── Social Monitor ───────────────────────────────────────────────────────────
class SocialMonitorResponse {
  final int totalPosts;
  final Map<String, int> trendingIssues;
  final List<SocialPost> posts;

  const SocialMonitorResponse({
    required this.totalPosts,
    required this.trendingIssues,
    required this.posts,
  });

  factory SocialMonitorResponse.fromJson(Map<String, dynamic> json) =>
      SocialMonitorResponse(
        totalPosts:     json['total_posts']       as int? ?? 0,
        trendingIssues: Map<String, int>.from(json['trending_issues'] ?? {}),
        posts:          (json['posts'] as List? ?? [])
            .map((e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class SocialPost {
  final String title;
  final String summary;
  final String sentiment;
  final String issueCategory;

  const SocialPost({
    required this.title,
    required this.summary,
    required this.sentiment,
    required this.issueCategory,
  });

  factory SocialPost.fromJson(Map<String, dynamic> json) => SocialPost(
        title:         json['title']          as String? ?? '',
        summary:       json['summary']        as String? ?? '',
        sentiment:     json['sentiment']      as String? ?? 'NEUTRAL',
        issueCategory: json['issue_category'] as String? ?? 'General',
      );
}