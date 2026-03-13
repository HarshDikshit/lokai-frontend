import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/issues_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common_widgets.dart';

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
  String get label => name[0].toUpperCase() + name.substring(1);
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

// ─── Complaint pipeline stages ────────────────────────────────────────────────
// Each stage has: label, icon, a function that returns bool (reached) and bool (active)
class _PipelineStage {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool reached;
  final bool active;

  const _PipelineStage({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.reached,
    required this.active,
  });
}

List<_PipelineStage> _buildPipeline(String status, int attempts) {
  // Status order: OPEN → RESOLVED_L1 → (approve→CLOSED | reject→OPEN again)
  //                                   → RESOLVED_L2 → (approve→CLOSED | reject→ESCALATED)
  //              ESCALATED → (authority closes)

  final s = status.toUpperCase();

  bool reached(List<String> statuses) => statuses.contains(s) || _isAfter(s, statuses);
  bool active(String st) => s == st;

  return [
    _PipelineStage(
      label: 'Submitted',
      subtitle: 'Complaint registered',
      icon: Icons.assignment_turned_in_outlined,
      reached: true,
      active: s == 'OPEN' && attempts == 0,
    ),
    _PipelineStage(
      label: 'AI Analysis',
      subtitle: 'Categorized & prioritized',
      icon: Icons.auto_awesome_outlined,
      reached: true,                     // always done once submitted
      active: false,
    ),
    _PipelineStage(
      label: 'Assigned to Leader',
      subtitle: 'Leader notified',
      icon: Icons.shield_outlined,
      reached: reached(['OPEN', 'RESOLVED_L1', 'RESOLVED_L2', 'ESCALATED', 'CLOSED']),
      active: s == 'OPEN' && attempts == 0,
    ),
    _PipelineStage(
      label: 'Resolution Attempt 1',
      subtitle: attempts >= 1 ? 'Leader filed resolution' : 'Awaiting leader action',
      icon: Icons.build_outlined,
      reached: reached(['RESOLVED_L1', 'RESOLVED_L2', 'ESCALATED', 'CLOSED']) || (s == 'OPEN' && attempts >= 1),
      active: s == 'RESOLVED_L1',
    ),
    _PipelineStage(
      label: 'Citizen Review #1',
      subtitle: s == 'RESOLVED_L1' ? 'Awaiting your approval' : (attempts >= 1 ? 'Reviewed' : 'Pending'),
      icon: Icons.how_to_vote_outlined,
      reached: reached(['RESOLVED_L2', 'ESCALATED', 'CLOSED']) || (s == 'OPEN' && attempts >= 1),
      active: s == 'RESOLVED_L1',
    ),
    _PipelineStage(
      label: 'Resolution Attempt 2',
      subtitle: attempts >= 2 ? 'Leader filed 2nd resolution' : 'Pending (if needed)',
      icon: Icons.build_circle_outlined,
      reached: reached(['RESOLVED_L2', 'ESCALATED', 'CLOSED']),
      active: s == 'RESOLVED_L2',
    ),
    _PipelineStage(
      label: 'Citizen Review #2',
      subtitle: s == 'RESOLVED_L2' ? 'Awaiting your approval' : (reached(['ESCALATED', 'CLOSED']) ? 'Reviewed' : 'Pending'),
      icon: Icons.verified_user_outlined,
      reached: reached(['ESCALATED', 'CLOSED']),
      active: s == 'RESOLVED_L2',
    ),
    _PipelineStage(
      label: s == 'ESCALATED' ? 'Escalated' : 'Closed',
      subtitle: s == 'ESCALATED'
          ? 'Referred to Higher Authority'
          : s == 'CLOSED' ? 'Issue resolved ✓' : 'Final outcome',
      icon: s == 'ESCALATED' ? Icons.escalator_warning_rounded : Icons.task_alt_rounded,
      reached: s == 'CLOSED' || s == 'ESCALATED',
      active: s == 'CLOSED' || s == 'ESCALATED',
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
  bool _actionLoading = false;
  bool _imageExpanded = false;

  Future<void> _verify(bool approved) async {
    setState(() => _actionLoading = true);
    try {
      final result = await ApiService.instance.verifyResolution(
        widget.issueId, approved,
        feedback: approved ? 'Resolved!' : 'Not satisfactory',
      );
      if (!mounted) return;
      ref.invalidate(issueDetailProvider(widget.issueId));
      ref.invalidate(issuesProvider);
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
    final auth      = ref.watch(authProvider);
    final issueAsync = ref.watch(issueDetailProvider(widget.issueId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: issueAsync.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Issue Details')),
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
          final pipeline = _buildPipeline(status, attempts);

          // Image URL
          final imageUrl = issue['image_url'] as String?;
          final hasImage = imageUrl != null && imageUrl.isNotEmpty;

          return CustomScrollView(
            slivers: [
              // ── Hero app bar with optional image ─────────────────────────
              SliverAppBar(
                expandedHeight: hasImage ? 280 : 80,
                pinned: true,
                backgroundColor: AppColors.primary,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => context.go(
                      auth.role == 'leader' ? '/leader/issues' : '/citizen/issues'),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    _truncate(issue['title'] ?? '', 36),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                  titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 14),
                  background: hasImage
                      ? Stack(fit: StackFit.expand, children: [
                          Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(color: AppColors.primaryDark),
                          ),
                          // gradient overlay so title is readable
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black87],
                                stops: [0.4, 1.0],
                              ),
                            ),
                          ),
                          // tap to expand
                          Positioned(
                            top: 12, right: 12,
                            child: GestureDetector(
                              onTap: () => _showFullImage(context, imageUrl!),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(8),
                                ),
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
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
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
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Status + urgency row ───────────────────────────
                      Row(children: [
                        StatusBadge(status: status),
                        const SizedBox(width: 8),
                        _UrgencyChip(urgency: urgency),
                        const Spacer(),
                        ResolutionTicks(attempts: attempts, status: status),
                      ]),
                      const SizedBox(height: 20),

                      // ── Title + description card ───────────────────────
                      _Card(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(issue['title'] ?? '',
                              style: const TextStyle(fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 10),
                          Text(issue['description'] ?? '',
                              style: const TextStyle(fontSize: 14,
                                  color: AppColors.textSecondary, height: 1.6)),
                        ],
                      )),
                      const SizedBox(height: 16),

                      // ── Priority score bar ─────────────────────────────
                      if (score != null) ...[
                        _Card(child: _PriorityBar(score: score, urgency: urgency)),
                        const SizedBox(height: 16),
                      ],

                      // ── Meta info ──────────────────────────────────────
                      _Card(child: Column(children: [
                        _MetaRow(Icons.category_outlined, 'Category',
                            issue['category'] ?? 'AI analyzing…'),
                        const _Divider(),
                        _MetaRow(Icons.person_outline, 'Reported by',
                            issue['citizen_name'] ?? 'You'),
                        if (issue['leader_name'] != null) ...[
                          const _Divider(),
                          _MetaRow(Icons.shield_outlined, 'Assigned Leader',
                              issue['leader_name']),
                        ],
                        const _Divider(),
                        _MetaRow(Icons.calendar_today_outlined, 'Reported on',
                            DateFormat('MMM d, yyyy  •  HH:mm').format(
                              DateTime.tryParse(issue['created_at'] ?? '') ?? DateTime.now(),
                            )),
                        if (issue['location'] != null) ...[
                          const _Divider(),
                          _MetaRow(
                            Icons.location_on_outlined,
                            'Location',
                            _locationLabel(issue['location']),
                          ),
                        ],
                      ])),
                      const SizedBox(height: 24),

                      // ── Complaint pipeline tracker ─────────────────────
                      _SectionLabel(label: 'Complaint Journey', icon: Icons.route_outlined),
                      const SizedBox(height: 12),
                      _PipelineTracker(stages: pipeline),
                      const SizedBox(height: 24),

                      // ── Escalation notice ──────────────────────────────
                      if (status == 'ESCALATED') ...[
                        _EscalationBanner(),
                        const SizedBox(height: 20),
                      ],

                      // ── Closed success ─────────────────────────────────
                      if (status == 'CLOSED') ...[
                        _ClosedBanner(),
                        const SizedBox(height: 20),
                      ],

                      // ── Citizen verification panel ─────────────────────
                      if (canVerify) ...[
                        _VerifyPanel(
                          status: status,
                          loading: _actionLoading,
                          onApprove: () => _verify(true),
                          onReject:  () => _verify(false),
                        ),
                        const SizedBox(height: 20),
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
        insetPadding: const EdgeInsets.all(0),
        child: Stack(children: [
          Center(child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain),
          )),
          Positioned(top: 40, right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
        ]),
      ),
    );
  }

  String _locationLabel(Map<String, dynamic> loc) {
    final parts = <String>[
      if ((loc['town'] ?? '').toString().isNotEmpty) loc['town'],
      if ((loc['city'] ?? '').toString().isNotEmpty) loc['city'],
      if ((loc['state'] ?? '').toString().isNotEmpty) loc['state'],
    ];
    if (parts.isNotEmpty) return parts.join(', ');
    if (loc['address'] != null) return loc['address'];
    final lat = (loc['latitude'] as num?)?.toStringAsFixed(4);
    final lng = (loc['longitude'] as num?)?.toStringAsFixed(4);
    return '$lat, $lng';
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}

// ─── Urgency chip ─────────────────────────────────────────────────────────────
class _UrgencyChip extends StatelessWidget {
  final UrgencyLevel urgency;
  const _UrgencyChip({required this.urgency});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: urgency.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: urgency.color.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(urgency.icon, size: 13, color: urgency.color),
        const SizedBox(width: 5),
        Text(urgency.label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: urgency.color)),
      ]),
    );
  }
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
        const Text('AI Priority Score',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const Spacer(),
        Text('$pct / 100',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                color: urgency.color)),
      ]),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: score,
          minHeight: 8,
          backgroundColor: AppColors.borderColor,
          valueColor: AlwaysStoppedAnimation<Color>(urgency.color),
        ),
      ),
      const SizedBox(height: 8),
      // Range labels
      Row(children: [
        _rangeLabel('Low', const Color(0xFF2E7D32), score < 0.25),
        _rangeLabel('Medium', const Color(0xFFF9A825), score >= 0.25 && score < 0.50),
        _rangeLabel('High', const Color(0xFFE65100), score >= 0.50 && score < 0.75),
        _rangeLabel('Critical', const Color(0xFFB71C1C), score >= 0.75),
      ]),
    ]);
  }

  Widget _rangeLabel(String label, Color color, bool active) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.15) : AppColors.inputFill,
        borderRadius: BorderRadius.circular(6),
        border: active ? Border.all(color: color.withOpacity(0.5)) : null,
      ),
      child: Text(label,
          textAlign: TextAlign.center,
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
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: List.generate(stages.length, (i) {
          final stage  = stages[i];
          final isLast = i == stages.length - 1;
          return _PipelineRow(stage: stage, isLast: isLast);
        }),
      ),
    );
  }
}

class _PipelineRow extends StatelessWidget {
  final _PipelineStage stage;
  final bool isLast;
  const _PipelineRow({required this.stage, required this.isLast});

  @override
  Widget build(BuildContext context) {
    Color dotColor;
    Color lineColor;
    Widget dotChild;

    if (stage.active) {
      dotColor  = AppColors.primary;
      lineColor = AppColors.primary.withOpacity(0.3);
      dotChild  = Container(
        width: 10, height: 10,
        decoration: const BoxDecoration(
          shape: BoxShape.circle, color: Colors.white,
        ),
      );
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left column: dot + line ───────────────────────────────────
          SizedBox(width: 52, child: Column(
            children: [
              const SizedBox(height: 14),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                  boxShadow: stage.active ? [BoxShadow(
                    color: AppColors.primary.withOpacity(0.35),
                    blurRadius: 8, spreadRadius: 2,
                  )] : null,
                ),
                child: Center(child: dotChild),
              ),
              if (!isLast)
                Expanded(child: Center(
                  child: Container(width: 2,
                    color: lineColor),
                )),
            ],
          )),

          // ── Right column: label ───────────────────────────────────────
          Expanded(child: Padding(
            padding: EdgeInsets.fromLTRB(0, 12, 16, isLast ? 12 : 20),
            child: Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stage.label, style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: stage.active
                        ? AppColors.primary
                        : stage.reached
                            ? AppColors.textPrimary
                            : AppColors.textHint,
                  )),
                  const SizedBox(height: 2),
                  Text(stage.subtitle, style: TextStyle(
                    fontSize: 11,
                    color: stage.active ? AppColors.primary.withOpacity(0.7) : AppColors.textHint,
                  )),
                ],
              )),
              if (stage.active)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: const Text('Current',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ),
            ]),
          )),
        ],
      ),
    );
  }
}

// ─── Verify panel ─────────────────────────────────────────────────────────────
class _VerifyPanel extends StatelessWidget {
  final String status;
  final bool loading;
  final VoidCallback onApprove, onReject;
  const _VerifyPanel({required this.status, required this.loading,
      required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final isL2 = status == 'RESOLVED_L2';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.verified_user_outlined, color: AppColors.success, size: 20),
          const SizedBox(width: 8),
          Text(
            'Resolution ${isL2 ? "✔✔" : "✔"} — Awaiting Your Approval',
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          isL2
              ? 'Leader submitted a second resolution. Rejecting will escalate to Higher Authority.'
              : 'Leader submitted a resolution. Is the issue fixed?',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: loading ? null : onReject,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Reject'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton.icon(
            onPressed: loading ? null : onApprove,
            icon: loading
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 16),
            label: const Text('Approve'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          )),
        ]),
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
    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
      SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Escalated to Higher Authority',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.error)),
        SizedBox(height: 4),
        Text(
          'The assigned leader failed to resolve this issue after 2 attempts. '
          'Higher Authority will now take action.',
          style: TextStyle(fontSize: 13, color: AppColors.error, height: 1.5),
        ),
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
    child: const Row(children: [
      Icon(Icons.task_alt_rounded, color: AppColors.success, size: 20),
      SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Issue Closed', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success)),
        SizedBox(height: 4),
        Text('This complaint has been successfully resolved and closed.',
            style: TextStyle(fontSize: 13, color: AppColors.success, height: 1.5)),
      ])),
    ]),
  );
}

// ─── Small reusable widgets ───────────────────────────────────────────────────
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
  final String value;
  const _MetaRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(children: [
      Icon(icon, size: 16, color: AppColors.textHint),
      const SizedBox(width: 10),
      SizedBox(
        width: 110,
        child: Text(label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: AppColors.textPrimary))),
    ]),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: AppColors.borderColor);
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
    Text(label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
            color: AppColors.textPrimary)),
  ]);
}