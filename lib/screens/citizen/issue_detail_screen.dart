import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/issues_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common_widgets.dart';
import '../../models/models.dart';
import '../../core/localization.dart';

// ─── Safe extraction helpers ──────────────────────────────────────────────────
String? _strVal(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    if (v.isEmpty) return null;
    if (v.startsWith('/uploads') || v.startsWith('uploads/')) return null;
    return v;
  }
  return null;
}

List<Map<String, dynamic>> _safeListOfMaps(dynamic raw) {
  if (raw == null) return [];
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

// ─── Urgency helper ───────────────────────────────────────────────────────────
enum UrgencyLevel { critical, high, medium, low }

UrgencyLevel _urgencyFromScore(double? score) {
  if (score == null) return UrgencyLevel.low;
  if (score >= 0.75) return UrgencyLevel.critical;
  if (score >= 0.50) return UrgencyLevel.high;
  if (score >= 0.25) return UrgencyLevel.medium;
  return UrgencyLevel.low;
}

extension UrgencyExt on UrgencyLevel {
  String label(BuildContext context) => context.translate('urgency_$name');
  Color get color {
    switch (this) {
      case UrgencyLevel.critical: return const Color(0xFFB71C1C);
      case UrgencyLevel.high:     return const Color(0xFFE65100);
      case UrgencyLevel.medium:   return const Color(0xFFF9A825);
      case UrgencyLevel.low:      return const Color(0xFF2E7D32);
    }
  }
  Color get bg {
    switch (this) {
      case UrgencyLevel.critical: return const Color(0xFFFFEBEE);
      case UrgencyLevel.high:     return const Color(0xFFFBE9E7);
      case UrgencyLevel.medium:   return const Color(0xFFFFFDE7);
      case UrgencyLevel.low:      return const Color(0xFFE8F5E9);
    }
  }
  IconData get icon {
    switch (this) {
      case UrgencyLevel.critical: return Icons.local_fire_department_rounded;
      case UrgencyLevel.high:     return Icons.warning_amber_rounded;
      case UrgencyLevel.medium:   return Icons.info_rounded;
      case UrgencyLevel.low:      return Icons.check_circle_outline_rounded;
    }
  }
}

// ─── Pipeline ─────────────────────────────────────────────────────────────────
class _PipelineStage {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool reached;
  final bool active;
  const _PipelineStage({
    required this.label, required this.subtitle, required this.icon,
    required this.reached, required this.active,
  });
}

List<_PipelineStage> _buildPipeline(BuildContext context, String status, int attempts) {
  final s = status.toUpperCase();
  String t(String k) => context.translate(k);
  bool reached(List<String> ss) => ss.contains(s) || _isAfter(s, ss);

  return [
    _PipelineStage(
      label: t('stage_submitted'), subtitle: 'Complaint registered',
      icon: Icons.assignment_turned_in_outlined,
      reached: true, active: s == 'OPEN' && attempts == 0,
    ),
    _PipelineStage(
      label: t('stage_ai_analysis'), subtitle: 'Categorized & prioritized',
      icon: Icons.auto_awesome_outlined,
      reached: true, active: false,
    ),
    _PipelineStage(
      label: t('stage_assigned'), subtitle: 'Leader notified',
      icon: Icons.shield_outlined,
      reached: reached(['OPEN', 'RESOLVED_L1', 'RESOLVED_L2', 'ESCALATED', 'CLOSED']),
      active: s == 'OPEN' && attempts == 0,
    ),
    _PipelineStage(
      label: t('stage_attempt1'),
      subtitle: attempts >= 1 ? 'Leader filed resolution' : 'Awaiting leader action',
      icon: Icons.build_outlined,
      reached: reached(['RESOLVED_L1', 'RESOLVED_L2', 'ESCALATED', 'CLOSED']) ||
               (s == 'OPEN' && attempts >= 1),
      active: s == 'RESOLVED_L1',
    ),
    _PipelineStage(
      label: t('stage_review1'),
      subtitle: s == 'RESOLVED_L1'
          ? 'Awaiting your approval'
          : (attempts >= 1 ? 'Reviewed' : 'Pending'),
      icon: Icons.how_to_vote_outlined,
      reached: reached(['RESOLVED_L2', 'ESCALATED', 'CLOSED']) ||
               (s == 'OPEN' && attempts >= 1),
      active: s == 'RESOLVED_L1',
    ),
    _PipelineStage(
      label: t('stage_attempt2'),
      subtitle: attempts >= 2 ? 'Leader filed 2nd resolution' : 'Pending (if needed)',
      icon: Icons.build_circle_outlined,
      reached: reached(['RESOLVED_L2', 'ESCALATED', 'CLOSED']),
      active: s == 'RESOLVED_L2',
    ),
    _PipelineStage(
      label: t('stage_review2'),
      subtitle: s == 'RESOLVED_L2'
          ? 'Awaiting your approval'
          : reached(['ESCALATED', 'CLOSED']) ? 'Reviewed' : 'Pending',
      icon: Icons.verified_user_outlined,
      reached: reached(['ESCALATED', 'CLOSED']),
      active: s == 'RESOLVED_L2',
    ),
    _PipelineStage(
      label: s == 'ESCALATED' ? t('stage_escalated') : t('stage_closed'),
      subtitle: s == 'ESCALATED'
          ? 'Referred to Higher Authority'
          : s == 'CLOSED' ? 'Issue resolved ✓' : 'Final outcome',
      icon: s == 'ESCALATED'
          ? Icons.escalator_warning_rounded
          : Icons.task_alt_rounded,
      reached: s == 'CLOSED' || s == 'ESCALATED',
      active:  s == 'CLOSED' || s == 'ESCALATED',
    ),
  ];
}

bool _isAfter(String current, List<String> targets) {
  const order = ['OPEN', 'RESOLVED_L1', 'RESOLVED_L2', 'ESCALATED', 'CLOSED'];
  final ci = order.indexOf(current);
  return targets.any((t) => order.indexOf(t) <= ci);
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class IssueDetailScreen extends ConsumerStatefulWidget {
  final String issueId;
  const IssueDetailScreen({super.key, required this.issueId});

  @override
  ConsumerState<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends ConsumerState<IssueDetailScreen> {
  bool   _actionLoading = false;
  Timer? _pollTimer;

  final _feedbackCtrls = [TextEditingController(), TextEditingController()];

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) {
        ref.invalidate(issueDetailProvider(widget.issueId));
      }
    });
  }

  void _manualRefresh() {
    ref.invalidate(issueDetailProvider(widget.issueId));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final c in _feedbackCtrls) c.dispose();
    super.dispose();
  }

  Future<void> _showSimilarIssuesSheet(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            const SizedBox(height: 12),
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Icon(Icons.hub_outlined, color: AppColors.primary),
                const SizedBox(width: 12),
                Text(context.translate('similar_issues_nearby'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: ApiService.instance.getSimilarIssuesForLeader(widget.issueId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  final items = (snapshot.data ?? [])
                      .map((e) => SimilarIssueItem.fromJson(e as Map<String, dynamic>))
                      .toList();

                  if (items.isEmpty) {
                    return Center(
                        child: Text(context.translate('no_similar_found')));
                  }

                  return ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final item = items[i];
                      final score = (item.overlapScore * 100).round();
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.inputFill,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$score% Match',
                                  style: const TextStyle(fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary),
                                ),
                              ),
                              const Spacer(),
                              StatusBadge(status: item.status),
                            ]),
                            const SizedBox(height: 12),
                            Text(
                              item.description,
                              style: const TextStyle(fontSize: 13, height: 1.4),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            Row(children: [
                              const Icon(Icons.person_outline,
                                  size: 14, color: AppColors.textHint),
                              const SizedBox(width: 6),
                              Text(item.citizenName ?? 'Citizen',
                                  style: const TextStyle(fontSize: 12,
                                      color: AppColors.textSecondary)),
                              const Spacer(),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  context.push('/issue/${item.id}');
                                },
                                child: Text('${context.translate('view_details')} →'),
                              ),
                            ]),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _verify(bool approved, String status) async {
    final attemptIdx = status == 'RESOLVED_L1' ? 0 : 1;
    final feedback   = _feedbackCtrls[attemptIdx].text.trim();

    setState(() => _actionLoading = true);
    try {
      final result = await ApiService.instance.verifyResolution(
        widget.issueId, approved,
        feedback: feedback.isNotEmpty
            ? feedback
            : (approved ? 'Resolved!' : 'Not satisfactory'),
      );
      if (!mounted) return;
      ref.invalidate(issueDetailProvider(widget.issueId));
      ref.read(issuesProvider.notifier).fetchIssues();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['message'] ?? 'Done'),
        backgroundColor: approved ? AppColors.success : AppColors.warning,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth       = ref.watch(authProvider);
    final issueAsync = ref.watch(issueDetailProvider(widget.issueId));
    final isLeader   = auth.role == 'leader' || auth.role == 'admin';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: issueAsync.when(
        loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: Text(context.translate('issue_details'))),
          body: Center(child: Text('Error: $e')),
        ),
        data: (issue) {
          final status   = (issue['status'] ?? 'OPEN') as String;
          final attempts = (issue['resolution_attempts'] ?? 0) as int;
          final isCitizen = auth.role == 'citizen';
          final canVerify = isCitizen &&
              (status == 'RESOLVED_L1' || status == 'RESOLVED_L2');

          final score    = (issue['priority_score'] as num?)?.toDouble();
          final urgency  = _urgencyFromScore(score);
          final pipeline = _buildPipeline(context, status, attempts);

          final imageUrl = _strVal(issue['image_url']);
          final hasImage = imageUrl != null && imageUrl.isNotEmpty;

          final resNotes      = _safeListOfMaps(issue['resolution_notes']);
          final verifications = _safeListOfMaps(issue['verifications']);

          return CustomScrollView(
            slivers: [
              // ── Hero app bar ────────────────────────────────────────
              SliverAppBar(
                expandedHeight: hasImage ? 280 : 80,
                pinned: true,
                backgroundColor: AppColors.primary,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(isLeader
                          ? '/leader/issues'
                          : '/citizen/issues');
                    }
                  },
                ),
                actions: [
                  IconButton(
                    onPressed: () {
                      final currentLocale = ref.read(localeProvider);
                      ref.read(localeProvider.notifier).setLocale(currentLocale.languageCode == 'en' 
                              ? const Locale('hi') 
                              : const Locale('en'));
                    },
                    icon: const Icon(Icons.language, color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    tooltip: context.translate('refresh'),
                    onPressed: _manualRefresh,
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    _truncate(issue['title'] ?? issue['description'] ?? '', 36),
                    style: const TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 14),
                  background: hasImage
                      ? Stack(fit: StackFit.expand, children: [
                          Image.network(imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: AppColors.primaryDark)),
                          Container(decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                              stops: [0.4, 1.0],
                            ),
                          )),
                          Positioned(
                            top: 12, right: 12,
                            child: GestureDetector(
                              onTap: () => _showFullImage(context, imageUrl!),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.fullscreen,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ])
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.primaryDark, AppColors.primary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.report_problem_outlined,
                                color: Colors.white38, size: 64),
                          ),
                        ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Status + urgency + ticks
                      Row(children: [
                        StatusBadge(status: status),
                        const SizedBox(width: 8),
                        _UrgencyChip(urgency: urgency),
                        const Spacer(),
                        ResolutionTicks(attempts: attempts, status: status),
                      ]),
                      const SizedBox(height: 20),

                      // Title + description
                      _Card(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(issue['title'] ?? issue['description'] ?? '',
                            style: const TextStyle(fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 10),
                        Text(issue['description'] ?? '',
                            style: const TextStyle(fontSize: 14,
                                color: AppColors.textSecondary, height: 1.6)),
                      ])),
                      const SizedBox(height: 16),

                      // Priority bar
                      if (score != null) ...[
                        _Card(child: _PriorityBar(score: score, urgency: urgency)),
                        const SizedBox(height: 16),
                      ],

                      // Meta
                      _Card(child: Column(children: [
                        _MetaRow(Icons.category_outlined, context.translate('category'),
                            issue['category'] ?? 'AI analyzing…'),
                        const _HDivider(),
                        _MetaRow(
                          Icons.person_outline,
                          context.translate('reported_by'),
                          issue['citizen_name'] ?? 'You',
                          trailing: (isLeader &&
                                  (issue['citizen_phone'] != null ||
                                   issue['phone'] != null))
                               ? IconButton(
                                   icon: const Icon(Icons.call,
                                       size: 18, color: AppColors.success),
                                   onPressed: () => launchUrl(Uri.parse(
                                       'tel:${issue['citizen_phone'] ?? issue['phone']}')),
                                 )
                               : null,
                        ),
                        if (issue['leader_name'] != null) ...[
                          const _HDivider(),
                          _MetaRow(
                            Icons.shield_outlined,
                            context.translate('assigned_leader'),
                            issue['leader_name'],
                            trailing: (isCitizen &&
                                    (issue['leader_phone'] != null ||
                                     issue['leaderPhone'] != null))
                                ? IconButton(
                                    icon: const Icon(Icons.call,
                                        size: 18, color: AppColors.success),
                                    onPressed: () => launchUrl(Uri.parse(
                                        'tel:${issue['leader_phone'] ?? issue['leaderPhone']}')),
                                  )
                                : null,
                          ),
                        ],
                        const _HDivider(),
                        _MetaRow(
                          Icons.calendar_today_outlined,
                          context.translate('reported_on'),
                          DateFormat('MMM d, yyyy  •  HH:mm').format(
                            DateTime.tryParse(issue['created_at'] ?? '') ??
                                DateTime.now(),
                          ),
                        ),
                        if (issue['location'] != null) ...[
                          const _HDivider(),
                          _MetaRow(Icons.location_on_outlined, context.translate('location'),
                              _locationLabel(issue['location'])),
                        ],
                      ])),
                      const SizedBox(height: 16),

                      // ── Show Similar Issues — leader only ─────────────
                      if (isLeader) ...[
                        OutlinedButton.icon(
                          onPressed: () => _showSimilarIssuesSheet(context),
                          icon: const Icon(Icons.search_rounded, size: 18),
                          label: Text(context.translate('similar_issues_nearby')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(double.infinity, 0),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // ── Resolution evidence cards ─────────────────────
                      if (resNotes.isNotEmpty) ...[
                        _SectionLabel(
                            label: context.translate('resolution_evidence'),
                            icon: Icons.fact_check_outlined),
                        const SizedBox(height: 12),
                        ...List.generate(resNotes.length, (i) {
                          final note = resNotes[i];
                          final ver  = verifications.length > i
                              ? verifications[i]
                              : null;
                          final thisAttemptPendingVerify = canVerify &&
                              ((i == 0 && status == 'RESOLVED_L1') ||
                               (i == 1 && status == 'RESOLVED_L2'));
                          return _ResolutionEvidenceCard(
                            attempt:        (note['attempt'] as num?)?.toInt() ?? i + 1,
                            notes:          _strVal(note['notes']) ?? '',
                            resolvedAt:     _strVal(note['resolved_at']),
                            beforeImageUrl: ver != null
                                ? _strVal(ver['before_image_url'])
                                : null,
                            afterImageUrl:  ver != null
                                ? _strVal(ver['after_image_url'])
                                : null,
                            isFinal:         resNotes.length > 1 &&
                                             i == resNotes.length - 1,
                            isPendingVerify: thisAttemptPendingVerify,
                            feedbackCtrl:    _feedbackCtrls[i],
                            loading:         _actionLoading,
                            onApprove:       thisAttemptPendingVerify
                                ? () => _verify(true, status)
                                : null,
                            onReject:        thisAttemptPendingVerify
                                ? () => _verify(false, status)
                                : null,
                            onImageTap: (url) => _showFullImage(context, url),
                          );
                        }),
                        const SizedBox(height: 24),
                      ],

                      // ── Pipeline ──────────────────────────────────────
                      _SectionLabel(
                          label: context.translate('complaint_journey'),
                          icon: Icons.route_outlined),
                      const SizedBox(height: 12),
                      _PipelineTracker(stages: pipeline),
                      const SizedBox(height: 24),

                      // Banners
                      if (status == 'ESCALATED') ...[
                        _EscalationBanner(), const SizedBox(height: 20),
                      ],
                      if (status == 'CLOSED') ...[
                        _ClosedBanner(), const SizedBox(height: 20),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFullImage(BuildContext ctx, String url) {
    showDialog(
      context: ctx,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(children: [
          Center(child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain))),
          Positioned(
            top: 40, right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
        ]),
      ),
    );
  }

  String _locationLabel(dynamic loc) {
    if (loc == null) return '';
    final m = Map<String, dynamic>.from(loc as Map);
    final parts = <String>[
      if ((m['town']  ?? '').toString().isNotEmpty) m['town'].toString(),
      if ((m['city']  ?? '').toString().isNotEmpty) m['city'].toString(),
      if ((m['state'] ?? '').toString().isNotEmpty) m['state'].toString(),
    ];
    if (parts.isNotEmpty) return parts.join(', ');
    if (m['address'] != null) return m['address'].toString();
    final lat = (m['latitude']  as num?)?.toStringAsFixed(4);
    final lng = (m['longitude'] as num?)?.toStringAsFixed(4);
    return '$lat, $lng';
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}

// ─────────────────────────────────────────────────────────────────────────────
// Resolution evidence card
// ─────────────────────────────────────────────────────────────────────────────
class _ResolutionEvidenceCard extends StatelessWidget {
  final int    attempt;
  final String notes;
  final String? resolvedAt;
  final String? beforeImageUrl;
  final String? afterImageUrl;
  final bool   isFinal;
  final bool   isPendingVerify;
  final TextEditingController feedbackCtrl;
  final bool         loading;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final void Function(String url) onImageTap;

  const _ResolutionEvidenceCard({
    required this.attempt,
    required this.notes,
    this.resolvedAt,
    this.beforeImageUrl,
    this.afterImageUrl,
    required this.isFinal,
    required this.isPendingVerify,
    required this.feedbackCtrl,
    required this.loading,
    required this.onApprove,
    required this.onReject,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor  = isFinal ? AppColors.warning : AppColors.success;
    final attemptLabel = isFinal
        ? '${context.translate('final_resolution')}  ✔✔'
        : '${context.translate('resolution_attempt')} $attempt  ✔';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPendingVerify
              ? accentColor.withOpacity(0.5)
              : AppColors.borderColor,
          width: isPendingVerify ? 1.5 : 1,
        ),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8, offset: const Offset(0, 2),
        )],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(
                isFinal ? Icons.build_circle_outlined : Icons.build_outlined,
                size: 16, color: accentColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(attemptLabel, style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w700, color: accentColor)),
              if (resolvedAt != null)
                Text(_fmtDate(resolvedAt!),
                    style: const TextStyle(fontSize: 11,
                        color: AppColors.textHint)),
            ])),
            if (isPendingVerify)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.info.withOpacity(0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.hourglass_top_rounded, size: 11, color: AppColors.info),
                  const SizedBox(width: 4),
                  _AwaitingReviewText(),
                ]),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Before / After photos
            if (beforeImageUrl != null || afterImageUrl != null) ...[
              Row(children: [
                const Icon(Icons.photo_library_outlined, size: 14,
                    color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(context.translate('verification_photos'), style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                if (beforeImageUrl != null)
                  Expanded(child: _VerifPhoto(
                    url: beforeImageUrl!, label: 'BEFORE',
                    color: AppColors.info,
                    onTap: () => onImageTap(beforeImageUrl!),
                  )),
                const SizedBox(width: 10),
                if (afterImageUrl != null)
                  Expanded(child: _VerifPhoto(
                    url: afterImageUrl!, label: 'AFTER',
                    color: AppColors.success,
                    onTap: () => onImageTap(afterImageUrl!),
                  )),
                if (beforeImageUrl == null || afterImageUrl == null)
                  const Expanded(child: SizedBox()),
              ]),
              const SizedBox(height: 16),
            ],

            // Leader notes
            Row(children: [
              const Icon(Icons.description_outlined, size: 14,
                  color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(context.translate('leader_action_desc'), style: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ]),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderColor),
              ),
              child: Text(
                notes.isNotEmpty ? notes : context.translate('no_notes'),
                style: const TextStyle(fontSize: 13,
                    color: AppColors.textPrimary, height: 1.5),
              ),
            ),

            // Citizen verify panel
            if (isPendingVerify) ...[
              const SizedBox(height: 20),
              const _SectionDivider(),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.info.withOpacity(0.3)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline, color: AppColors.info, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    isFinal
                        ? 'This is the leader\'s final attempt. '
                          'If you reject, the issue will be escalated to Higher Authority.'
                        : 'Review the leader\'s work above. Has the issue been resolved to your satisfaction?',
                    style: const TextStyle(fontSize: 12,
                        color: AppColors.info, height: 1.4),
                  )),
                ]),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: feedbackCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Write your feedback (optional)…\n'
                      'e.g. "Road repaired but minor cracks remain"',
                  hintStyle: TextStyle(fontSize: 12),
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 40),
                    child: Icon(Icons.edit_note_rounded,
                        color: AppColors.textHint, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: (loading || onReject == null) ? null : onReject,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text(context.translate('reject')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(
                  onPressed: (loading || onApprove == null) ? null : onApprove,
                  icon: loading
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 16),
                  label: Text(context.translate('approve')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                )),
              ]),
            ] else if (afterImageUrl != null || notes.isNotEmpty) ...[
              const SizedBox(height: 14),
              const _SectionDivider(),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.check_circle_outline_rounded,
                    size: 14, color: AppColors.textHint),
                const SizedBox(width: 6),
                Text(context.translate('citizen_reviewed'),
                    style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  String _fmtDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return DateFormat('dd MMM yyyy  •  HH:mm').format(dt.toLocal());
  }
}

// ─── Verification photo tile ──────────────────────────────────────────────────
class _VerifPhoto extends StatelessWidget {
  final String url;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _VerifPhoto({
    required this.url, required this.label,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5), width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(fit: StackFit.expand, children: [
            Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.inputFill,
                  child: const Icon(Icons.broken_image_outlined,
                      color: AppColors.textHint, size: 32),
                )),
            // Gradient
            Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.55), Colors.transparent],
                stops: const [0, 0.5],
              ),
            )),
            // Label
            Positioned(bottom: 8, left: 8, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(6)),
              child: Text(label, style: const TextStyle(color: Colors.white,
                  fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            )),
            // Fullscreen hint
            Positioned(top: 6, right: 6, child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: Colors.black45, borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.fullscreen, color: Colors.white, size: 14),
            )),
          ]),
        ),
      ),
    );
  }
}

// ─── Urgency chip ─────────────────────────────────────────────────────────────
class _UrgencyChip extends StatelessWidget {
  final UrgencyLevel urgency;
  const _UrgencyChip({required this.urgency});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: urgency.bg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: urgency.color.withOpacity(0.35)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(urgency.icon, size: 13, color: urgency.color),
      const SizedBox(width: 5),
      Text(urgency.label(context),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: urgency.color)),
    ]),
  );
}

// ─── Priority bar ─────────────────────────────────────────────────────────────
class _PriorityBar extends StatelessWidget {
  final double score;
  final UrgencyLevel urgency;
  const _PriorityBar({required this.score, required this.urgency});
  @override
  Widget build(BuildContext context) {
    final pct = (score * 100).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.analytics_outlined, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(context.translate('ai_priority_score'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const Spacer(),
        Text('$pct / 100', style: TextStyle(fontSize: 14,
            fontWeight: FontWeight.w800, color: urgency.color)),
      ]),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: score, minHeight: 8,
          backgroundColor: AppColors.borderColor,
          valueColor: AlwaysStoppedAnimation<Color>(urgency.color),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        _rangeLabel('Low',      const Color(0xFF2E7D32), score < 0.25),
        _rangeLabel('Medium',   const Color(0xFFF9A825), score >= 0.25 && score < 0.50),
        _rangeLabel('High',     const Color(0xFFE65100), score >= 0.50 && score < 0.75),
        _rangeLabel('Critical', const Color(0xFFB71C1C), score >= 0.75),
      ]),
    ]);
  }
  Widget _rangeLabel(String label, Color color, bool active) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color:  active ? color.withOpacity(0.15) : AppColors.inputFill,
        borderRadius: BorderRadius.circular(6),
        border: active ? Border.all(color: color.withOpacity(0.5)) : null,
      ),
      child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
              color: active ? color : AppColors.textHint)),
    ),
  );
}

// ─── Pipeline tracker ─────────────────────────────────────────────────────────
class _PipelineTracker extends StatelessWidget {
  final List<_PipelineStage> stages;
  const _PipelineTracker({required this.stages});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.borderColor),
    ),
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(children: List.generate(stages.length, (i) =>
        _PipelineRow(stage: stages[i], isLast: i == stages.length - 1))),
  );
}

class _PipelineRow extends StatelessWidget {
  final _PipelineStage stage;
  final bool           isLast;
  const _PipelineRow({required this.stage, required this.isLast});
  @override
  Widget build(BuildContext context) {
    Color  dotColor;
    Widget dotChild;
    Color  lineColor;
    if (stage.active) {
      dotColor  = AppColors.primary;
      lineColor = AppColors.primary.withOpacity(0.3);
      dotChild  = Container(width: 10, height: 10,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Colors.white));
    } else if (stage.reached) {
      dotColor  = AppColors.success;
      lineColor = AppColors.success.withOpacity(0.4);
      dotChild  = const Icon(Icons.check, color: Colors.white, size: 12);
    } else {
      dotColor  = AppColors.borderColor;
      lineColor = AppColors.borderColor;
      dotChild  = const SizedBox.shrink();
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 52, child: Column(children: [
          const SizedBox(height: 14),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 28, height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: dotColor,
              boxShadow: stage.active ? [BoxShadow(
                  color: AppColors.primary.withOpacity(0.35),
                  blurRadius: 8, spreadRadius: 2)] : null,
            ),
            child: Center(child: dotChild),
          ),
          if (!isLast)
            Expanded(child: Center(
                child: Container(width: 2, color: lineColor))),
        ])),
        Expanded(child: Padding(
          padding: EdgeInsets.fromLTRB(0, 12, 16, isLast ? 12 : 20),
          child: Row(children: [
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(stage.label, style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: stage.active
                      ? AppColors.primary
                      : stage.reached
                          ? AppColors.textPrimary
                          : AppColors.textHint)),
              const SizedBox(height: 2),
              Text(stage.subtitle, style: TextStyle(fontSize: 11,
                  color: stage.active
                      ? AppColors.primary.withOpacity(0.7)
                      : AppColors.textHint)),
            ])),
            if (stage.active)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Text(context.translate('current_status'), style: const TextStyle(fontSize: 10,
                    fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
          ]),
        )),
      ]),
    );
  }
}

// ─── Banners ──────────────────────────────────────────────────────────────────
class _EscalationBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.errorLight,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.error.withOpacity(0.3)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text(context.translate('escalated_banner_title'),
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.error)),
        const SizedBox(height: 4),
        Text(context.translate('escalated_banner_desc'),
            style: const TextStyle(fontSize: 13, color: AppColors.error, height: 1.5)),
      ])),
    ]),
  );
}

class _ClosedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.successLight,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.success.withOpacity(0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.task_alt_rounded, color: AppColors.success, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text(context.translate('closed_banner_title'), style: const TextStyle(fontWeight: FontWeight.w700,
            color: AppColors.success)),
        const SizedBox(height: 4),
        Text(context.translate('closed_banner_desc'),
            style: const TextStyle(fontSize: 13, color: AppColors.success, height: 1.5)),
      ])),
    ]),
  );
}

// ─── Small reusables ──────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.borderColor),
    ),
    child: child,
  );
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final Widget? trailing;
  const _MetaRow(this.icon, this.label, this.value, {this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(children: [
      Icon(icon, size: 16, color: AppColors.textHint),
      const SizedBox(width: 10),
      SizedBox(width: 110, child: Text(label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
      Expanded(child: Text(value ?? '—',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: AppColors.textPrimary))),
      if (trailing != null) trailing!,
    ]),
  );
}

class _HDivider extends StatelessWidget {
  const _HDivider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: AppColors.borderColor);
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: AppColors.borderColor);
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel({required this.label, required this.icon});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: AppColors.primary),
    ),
    const SizedBox(width: 10),
    Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary)),
  ]);
}

class _AwaitingReviewText extends StatelessWidget {
  const _AwaitingReviewText();
  @override
  Widget build(BuildContext context) => Text(
    context.translate('awaiting_citizen_review'),
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.info),
  );
}
