// screens/authority/authority_screen.dart
// Consolidated view for Higher Authority.
// Features: Escalated Issues list, Leader Performance metrics, and reassignment logic.
// Removed: Review Queue and similarity-based pre-moderation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/issues_provider.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common_widgets.dart';
import '../../providers/social_monitor_provider.dart';


class AuthorityScreen extends ConsumerStatefulWidget {
  const AuthorityScreen({super.key});

  @override
  ConsumerState<AuthorityScreen> createState() => _AuthorityScreenState();
}

class _AuthorityScreenState extends ConsumerState<AuthorityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }


  // ── Actions ───────────────────────────────────────────────────────────────
  Future<void> _closeIssue(String issueId, String title) async {
    final confirm = await _confirmDialog(
      title:        'Close Issue',
      body:         'Permanently close "$title"?\nThis cannot be undone.',
      confirmLabel: 'Close Issue',
      color:        AppColors.success,
    );
    if (confirm != true) return;
    await _doAction(
        () => ApiService.instance.overrideIssue(issueId, 'close'),
        'Issue closed successfully');
  }

  Future<void> _reassignIssue(
      String issueId, String issueTitle,
      List<Map<String, dynamic>> leaders) async {
    String? selectedId;
    Map<String, dynamic>? selectedLeader;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReassignSheet(
        issueTitle: issueTitle,
        leaders:    leaders,
        onConfirm:  (id, leader) async {
          selectedId     = id;
          selectedLeader = leader;
        },
      ),
    );

    if (selectedId == null) return;
    await _doAction(
      () => ApiService.instance.overrideIssue(issueId, 'reassign',
          newLeaderId: selectedId),
      'Issue reassigned to ${selectedLeader?["name"] ?? "new leader"}',
    );
  }


  Future<void> _doAction(
      Future<dynamic> Function() call, String successMsg) async {
    setState(() => _actionLoading = true);
    try {
      await call();
      ref.invalidate(escalatedIssuesProvider);
      ref.invalidate(authorityDashboardProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:         Text(successMsg),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String body,
    required String confirmLabel,
    required Color  color,
  }) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title:   Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(body,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: color),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final dashAsync = ref.watch(authorityDashboardProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Higher Authority'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(authorityDashboardProvider);
              ref.invalidate(escalatedIssuesProvider);
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              context.go('/');
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor:      Colors.white,
          labelColor:          Colors.white,
          isScrollable:        true,
          unselectedLabelColor: Colors.white60,
          tabs: [
            const Tab(
              icon: Icon(Icons.warning_amber_rounded, size: 18),
              text: 'Escalated Issues',
            ),
            const Tab(
              icon: Icon(Icons.leaderboard_rounded, size: 18),
              text: 'Leader Performance',
            ),
            const Tab(
              icon: Icon(Icons.hub_rounded, size: 18),
              text: 'Social Monitor',
            ),
          ],
        ),
      ),
      body: dashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center,
              children: [
            const Icon(Icons.cloud_off_rounded, size: 60,
                color: AppColors.textHint),
            const SizedBox(height: 16),
            Text('$e',
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(authorityDashboardProvider),
              icon:  const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ]),
        ),
        data: (data) {
          final overview    = Map<String, dynamic>.from(data['overview'] ?? {});
          final leaderStats = List<Map<String, dynamic>>.from(
              (data['leader_stats'] as List? ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map)));
          final escalatedList = List<Map<String, dynamic>>.from(
              (data['escalated_list'] as List? ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map)));

          return TabBarView(
            controller: _tabCtrl,
            children: [
              // Tab 0 — Escalated Issues (unchanged)
              _EscalatedTab(
                overview:      overview,
                escalatedList: escalatedList,
                leaderStats:   leaderStats,
                actionLoading: _actionLoading,
                onClose:       _closeIssue,
                onReassign:    _reassignIssue,
              ),

              // Tab 1 — Leader Performance (unchanged)
              _LeaderPerformanceTab(
                overview:    overview,
                leaderStats: leaderStats,
              ),

              // Tab 2 — Social Monitor
              _SocialMonitorTab(
                leaderStats: leaderStats,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 — Escalated Issues  (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────
class _EscalatedTab extends StatelessWidget {
  final Map<String, dynamic>       overview;
  final List<Map<String, dynamic>> escalatedList;
  final List<Map<String, dynamic>> leaderStats;
  final bool                       actionLoading;
  final Future<void> Function(String, String) onClose;
  final Future<void> Function(String, String, List<Map<String, dynamic>>)
      onReassign;

  const _EscalatedTab({
    required this.overview,
    required this.escalatedList,
    required this.leaderStats,
    required this.actionLoading,
    required this.onClose,
    required this.onReassign,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {},
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: _OverviewBar(overview: overview)),
        if (escalatedList.isEmpty)
          const SliverFillRemaining(child: _EmptyEscalated())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _EscalatedIssueCard(
                  issue:            escalatedList[i],
                  actionLoading:    actionLoading,
                  availableLeaders: leaderStats,
                  onClose:  () => onClose(
                    escalatedList[i]['issue_id'] as String,
                    escalatedList[i]['title']    as String? ?? '',
                  ),
                  onReassign: () => onReassign(
                    escalatedList[i]['issue_id'] as String,
                    escalatedList[i]['title']    as String? ?? '',
                    leaderStats,
                  ),
                ),
                childCount: escalatedList.length,
              ),
            ),
          ),
      ]),
    );
  }
}

// ── Overview bar ──────────────────────────────────────────────────────────────
class _OverviewBar extends StatelessWidget {
  final Map<String, dynamic> overview;
  const _OverviewBar({required this.overview});

  @override
  Widget build(BuildContext context) => Container(
    color:   AppColors.white,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    margin:  const EdgeInsets.only(bottom: 14),
    child: Row(children: [
      _Stat('Total',     (overview['total_issues']    ?? 0) as int, AppColors.primary),
      _vDivider(),
      _Stat('Open',      (overview['open_issues']     ?? 0) as int, AppColors.statusOpen),
      _vDivider(),
      _Stat('Escalated', (overview['escalated']       ?? 0) as int, AppColors.statusEscalated),
      _vDivider(),
      _Stat('Awaiting',  (overview['awaiting_review'] ?? 0) as int, AppColors.info),
      _vDivider(),
      _Stat('Closed',    (overview['closed_issues']   ?? 0) as int, AppColors.success),
    ]),
  );

  Widget _vDivider() => Container(
    width: 1, height: 32, margin: const EdgeInsets.symmetric(horizontal: 6),
    color: AppColors.borderColor,
  );
}

class _Stat extends StatelessWidget {
  final String label;
  final int    value;
  final Color  color;
  const _Stat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text('$value', style: TextStyle(fontSize: 18,
          fontWeight: FontWeight.w800, color: color)),
      Text(label, style: const TextStyle(fontSize: 9,
          color: AppColors.textSecondary), textAlign: TextAlign.center),
    ]),
  );
}

// ── Escalated issue card ──────────────────────────────────────────────────────
class _EscalatedIssueCard extends StatelessWidget {
  final Map<String, dynamic>       issue;
  final bool                       actionLoading;
  final List<Map<String, dynamic>> availableLeaders;
  final VoidCallback               onClose;
  final VoidCallback               onReassign;

  const _EscalatedIssueCard({
    required this.issue,
    required this.actionLoading,
    required this.availableLeaders,
    required this.onClose,
    required this.onReassign,
  });

  @override
  Widget build(BuildContext context) {
    final score       = (issue['priority_score'] as num?)?.toDouble();
    final urgColor    = _urgencyColor(score);
    final attempts    = (issue['resolution_attempts'] as int?) ?? 0;
    final escalatedAt = issue['escalated_at'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color:        AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.statusEscalated.withOpacity(0.4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Container(height: 4, decoration: const BoxDecoration(
          color: AppColors.statusEscalated,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        )),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(issue['title'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 15, color: AppColors.textPrimary),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              if (score != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:  urgColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: urgColor.withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.local_fire_department_rounded,
                        size: 11, color: urgColor),
                    const SizedBox(width: 3),
                    Text(_urgencyLabel(score),
                        style: TextStyle(fontSize: 10,
                            fontWeight: FontWeight.w700, color: urgColor)),
                  ]),
                ),
            ]),
            const SizedBox(height: 6),
            Text(issue['description'] as String? ?? '',
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13,
                    color: AppColors.textSecondary, height: 1.4)),
            const SizedBox(height: 10),
            Wrap(spacing: 12, runSpacing: 6, children: [
              if ((issue['category'] as String?)?.isNotEmpty == true)
                _metaChip(Icons.category_outlined,
                    issue['category'] as String),
              _metaChip(Icons.person_outline,
                  issue['citizen_name'] as String? ?? 'Unknown citizen'),
              _metaChip(Icons.shield_outlined,
                  issue['leader_name'] as String? ?? 'Unknown leader',
                  color: AppColors.error),
              _metaChip(Icons.repeat_rounded,
                  '$attempts attempt${attempts != 1 ? "s" : ""}'),
              if (escalatedAt != null)
                _metaChip(Icons.schedule_rounded, _fmtDate(escalatedAt)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: actionLoading ? null : onReassign,
                icon:  const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('Reassign'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                onPressed: actionLoading ? null : onClose,
                icon: actionLoading
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.task_alt_rounded, size: 16),
                label: const Text('Close Issue'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              )),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _metaChip(IconData icon, String label, {Color? color}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color ?? AppColors.textHint),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11,
            color: color ?? AppColors.textSecondary)),
      ]);

  Color _urgencyColor(double? s) {
    if (s == null) return AppColors.textHint;
    if (s >= 0.75) return const Color(0xFFB71C1C);
    if (s >= 0.50) return const Color(0xFFE65100);
    if (s >= 0.25) return const Color(0xFFF9A825);
    return const Color(0xFF2E7D32);
  }

  String _urgencyLabel(double s) {
    if (s >= 0.75) return 'Critical';
    if (s >= 0.50) return 'High';
    if (s >= 0.25) return 'Medium';
    return 'Low';
  }

  String _fmtDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return DateFormat('dd MMM  •  HH:mm').format(dt.toLocal());
  }
}

class _EmptyEscalated extends StatelessWidget {
  const _EmptyEscalated();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
            color: AppColors.successLight, shape: BoxShape.circle),
        child: const Icon(Icons.check_circle_outline_rounded,
            size: 52, color: AppColors.success),
      ),
      const SizedBox(height: 20),
      const Text('No escalated issues!',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
              color: AppColors.success)),
      const SizedBox(height: 8),
      const Text('All issues are being handled properly.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 — Leader Performance  (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────
class _LeaderPerformanceTab extends StatelessWidget {
  final Map<String, dynamic>       overview;
  final List<Map<String, dynamic>> leaderStats;
  const _LeaderPerformanceTab(
      {required this.overview, required this.leaderStats});

  @override
  Widget build(BuildContext context) {
    if (leaderStats.isEmpty) {
      return const Center(child: Text('No leaders registered yet.',
          style: TextStyle(color: AppColors.textSecondary)));
    }

    final atRisk  = leaderStats
        .where((l) => (l['failed_cases'] as int? ?? 0) >= 2).toList();
    final healthy = leaderStats
        .where((l) => (l['failed_cases'] as int? ?? 0) < 2).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SummaryRow(leaderStats: leaderStats),
        const SizedBox(height: 20),
        if (atRisk.isNotEmpty) ...[
          _sectionLabel('⚠️  At-Risk Leaders', AppColors.error),
          const SizedBox(height: 8),
          ...atRisk.map((l) => _LeaderCard(data: l, highlight: true)),
          const SizedBox(height: 20),
        ],
        _sectionLabel('✅  All Leaders', AppColors.primary),
        const SizedBox(height: 8),
        ...leaderStats.map((l) => _LeaderCard(data: l, highlight: false)),
      ]),
    );
  }

  Widget _sectionLabel(String text, Color color) => Row(children: [
    Container(width: 3, height: 16,
        decoration: BoxDecoration(color: color,
            borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary)),
  ]);
}

class _SummaryRow extends StatelessWidget {
  final List<Map<String, dynamic>> leaderStats;
  const _SummaryRow({required this.leaderStats});

  @override
  Widget build(BuildContext context) {
    final total   = leaderStats.length;
    final atRisk  = leaderStats
        .where((l) => (l['failed_cases'] as int? ?? 0) >= 2).length;
    final avgRate = total > 0
        ? leaderStats
            .map((l) => (l['resolution_rate'] as num? ?? 0).toDouble())
            .reduce((a, b) => a + b) / total
        : 0.0;

    return Row(children: [
      _SummaryChip('$total',  'Leaders',  AppColors.primary, Icons.shield_outlined),
      const SizedBox(width: 10),
      _SummaryChip('$atRisk', 'At Risk',  AppColors.error,   Icons.warning_amber_rounded),
      const SizedBox(width: 10),
      _SummaryChip('${avgRate.toStringAsFixed(1)}%', 'Avg Rate',
          AppColors.success, Icons.analytics_outlined),
    ]);
  }
}

class _SummaryChip extends StatelessWidget {
  final String   value, label;
  final Color    color;
  final IconData icon;
  const _SummaryChip(this.value, this.label, this.color, this.icon);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 16,
              fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 10,
              color: AppColors.textSecondary)),
        ]),
      ]),
    ),
  );
}

class _LeaderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool                 highlight;
  const _LeaderCard({required this.data, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final failed    = (data['failed_cases']  as int?) ?? 0;
    final total     = (data['total_issues']  as int?) ?? 0;
    final closed    = (data['closed_issues'] as int?) ?? 0;
    final open      = (data['open_issues']   as int?) ?? 0;
    final escalated = (data['escalated']     as int?) ?? 0;
    final awaiting  = (data['awaiting_review'] as int?) ?? 0;
    final rate      = (data['resolution_rate'] as num? ?? 0).toDouble();

    Color  statusColor;
    String statusLabel;
    if (failed >= 3)     { statusColor = AppColors.error;   statusLabel = 'High Risk'; }
    else if (failed >= 2){ statusColor = AppColors.warning; statusLabel = 'At Risk';   }
    else if (rate >= 70) { statusColor = AppColors.success; statusLabel = 'Good';      }
    else                 { statusColor = AppColors.info;    statusLabel = 'Active';    }

    final loc    = data['leader_location'] as Map?;
    final locStr = loc != null
        ? [loc['town'], loc['city'], loc['state']]
            .where((v) => v != null && (v as String).isNotEmpty)
            .join(', ')
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color:        AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: failed >= 2
            ? statusColor.withOpacity(0.4) : AppColors.borderColor),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(failed >= 2
                  ? Icons.warning_amber_rounded : Icons.shield_outlined,
                  size: 18, color: statusColor),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data['name'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 14, color: AppColors.textPrimary)),
              if (locStr != null)
                Text(locStr, style: const TextStyle(fontSize: 11,
                    color: AppColors.textSecondary)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color:        statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border:       Border.all(color: statusColor.withOpacity(0.3)),
              ),
              child: Text(statusLabel, style: TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w700, color: statusColor)),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Resolution Rate',
                style: TextStyle(fontSize: 11,
                    color: AppColors.textSecondary)),
            const Spacer(),
            Text('${rate.toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: statusColor)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:           (rate / 100).clamp(0.0, 1.0),
              minHeight:       6,
              backgroundColor: AppColors.borderColor,
              valueColor:      AlwaysStoppedAnimation(statusColor),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _statBox('Total',     '$total',     AppColors.primary),
            _statBox('Closed',    '$closed',    AppColors.success),
            _statBox('Open',      '$open',      AppColors.statusOpen),
            _statBox('Awaiting',  '$awaiting',  AppColors.info),
            _statBox('Escalated', '$escalated', AppColors.statusEscalated),
            _statBox('Failed',    '$failed',    AppColors.error),
          ]),
        ]),
      ),
    );
  }

  Widget _statBox(String label, String value, Color color) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 14,
          fontWeight: FontWeight.w800, color: color)),
      Text(label, style: const TextStyle(fontSize: 9,
          color: AppColors.textHint), textAlign: TextAlign.center),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reassign bottom sheet  (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────
class _ReassignSheet extends StatefulWidget {
  final String                     issueTitle;
  final List<Map<String, dynamic>> leaders;
  final Future<void> Function(String id, Map<String, dynamic> leader) onConfirm;

  const _ReassignSheet({
    required this.issueTitle,
    required this.leaders,
    required this.onConfirm,
  });

  @override
  State<_ReassignSheet> createState() => _ReassignSheetState();
}

class _ReassignSheetState extends State<_ReassignSheet> {
  String? _selectedId;
  bool    _loading = false;

  Map<String, dynamic>? get _selected => widget.leaders.firstWhere(
      (l) => l['leader_id'] == _selectedId, orElse: () => {});

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + inset),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 18),
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:        AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.swap_horiz_rounded,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Reassign Issue',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            Text(widget.issueTitle,
                style: const TextStyle(fontSize: 12,
                    color: AppColors.textSecondary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
        ]),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.leaders.length,
            itemBuilder: (_, i) {
              final l        = widget.leaders[i];
              final id       = l['leader_id'] as String;
              final failed   = (l['failed_cases']     as int?) ?? 0;
              final rate     = (l['resolution_rate']  as num? ?? 0).toDouble();
              final open     = (l['open_issues']      as int?) ?? 0;
              final selected = _selectedId == id;

              return GestureDetector(
                onTap: () => setState(() => _selectedId = id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withOpacity(0.07)
                        : AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.borderColor,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? AppColors.primary : AppColors.borderColor,
                          width: 2,
                        ),
                        color: selected ? AppColors.primary : Colors.transparent,
                      ),
                      child: selected
                          ? const Icon(Icons.check, color: Colors.white, size: 12)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l['name'] as String? ?? '',
                          style: TextStyle(fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: selected
                                  ? AppColors.primary : AppColors.textPrimary)),
                      const SizedBox(height: 3),
                      Text(
                        '${rate.toStringAsFixed(0)}% resolved  •  '
                        '$open open  •  $failed failures',
                        style: const TextStyle(fontSize: 11,
                            color: AppColors.textSecondary),
                      ),
                    ])),
                    if (failed >= 2)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color:        AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(failed >= 3 ? 'High Risk' : 'At Risk',
                            style: const TextStyle(fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.error)),
                      ),
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_selectedId == null || _loading)
                ? null
                : () async {
                    setState(() => _loading = true);
                    await widget.onConfirm(_selectedId!, _selected ?? {});
                    if (mounted) Navigator.pop(context);
                  },
            icon: _loading
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.swap_horiz_rounded, size: 18),
            label: Text(_selectedId == null
                ? 'Select a leader first'
                : 'Reassign to ${_selected?["name"] ?? ""}'),
            style: ElevatedButton.styleFrom(
              padding:   const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3 — Social Monitor
// ─────────────────────────────────────────────────────────────────────────────
class _SocialMonitorTab extends ConsumerWidget {
  final List<Map<String, dynamic>> leaderStats;
  const _SocialMonitorTab({required this.leaderStats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final socialAsync = ref.watch(socialMonitorProvider);

    return socialAsync.when(
      loading: () => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Analyzing social patterns...',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Error: $e', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(socialMonitorProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (res) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(socialMonitorProvider),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.analytics_outlined,
                          color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Citizen Pulse',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('AI-detected social media insights',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text('${res.totalPosts}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          const Text('Total Posts',
                              style:
                                  TextStyle(color: Colors.white70, fontSize: 9)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('TRENDING CONCERNS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textHint,
                        letterSpacing: 1.2)),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: res.trendingIssues.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final entry = res.trendingIssues.entries.elementAt(i);
                    return _TrendingConcernChip(
                        label: entry.key, count: entry.value);
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _SocialPostCard(
                    post: res.posts[i],
                    leaderStats: leaderStats,
                  ),
                  childCount: res.posts.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _TrendingConcernChip extends StatelessWidget {
  final String label;
  final int count;
  const _TrendingConcernChip({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}

class _SocialPostCard extends StatefulWidget {
  final SocialPost post;
  final List<Map<String, dynamic>> leaderStats;
  const _SocialPostCard({required this.post, required this.leaderStats});

  @override
  State<_SocialPostCard> createState() => _SocialPostCardState();
}

class _SocialPostCardState extends State<_SocialPostCard> {
  bool _assigning = false;

  Future<void> _assignLeader() async {
    String? selectedId;
    Map<String, dynamic>? selectedLeader;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReassignSheet(
        issueTitle: widget.post.title,
        leaders: widget.leaderStats,
        onConfirm: (id, leader) async {
          selectedId = id;
          selectedLeader = leader;
        },
      ),
    );

    if (selectedId == null) return;

    setState(() => _assigning = true);
    try {
      await ApiService.instance.assignSocialPost(
        post: {
          'title': widget.post.title,
          'summary': widget.post.summary,
          'sentiment': widget.post.sentiment,
          'issue_category': widget.post.issueCategory,
        },
        leaderId: selectedId!,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Assigned to ${selectedLeader?["name"]}'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sentiment = widget.post.sentiment.toUpperCase();
    final isNegative = sentiment == 'NEGATIVE';
    final sentColor = isNegative ? AppColors.error : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: sentColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        widget.post.title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: sentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sentColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isNegative
                                ? Icons.sentiment_very_dissatisfied
                                : Icons.sentiment_very_satisfied,
                            size: 14,
                            color: sentColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            sentiment,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: sentColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.post.summary,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.5),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.tag, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              widget.post.issueCategory,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _assigning ? null : _assignLeader,
                        icon: _assigning
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.assignment_ind_rounded, size: 16),
                        label: const Text('Assign Leader'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

