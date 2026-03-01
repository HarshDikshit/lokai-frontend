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

class AuthorityScreen extends ConsumerStatefulWidget {
  const AuthorityScreen({super.key});

  @override
  ConsumerState<AuthorityScreen> createState() => _AuthorityScreenState();
}

class _AuthorityScreenState extends ConsumerState<AuthorityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _closeIssue(String issueId) async {
    final confirm = await _confirmDialog('Close Issue',
        'Are you sure you want to close this issue?', AppColors.success);
    if (confirm != true) return;
    try {
      await ApiService.instance.overrideIssue(issueId, 'close');
      ref.invalidate(escalatedIssuesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Issue closed by authority'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _reassignIssue(String issueId, List<User> leaders) async {
    String? selectedLeaderId;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reassign Issue'),
        content: StatefulBuilder(
          builder: (ctx, setState) => DropdownButtonFormField<String>(
            value: selectedLeaderId,
            hint: const Text('Select new leader'),
            items: leaders.map((l) => DropdownMenuItem(
              value: l.id,
              child: Text('${l.name} (${l.failedCases} failures)'),
            )).toList(),
            onChanged: (v) => setState(() => selectedLeaderId = v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: selectedLeaderId == null
                ? null
                : () async {
                    Navigator.pop(ctx);
                    try {
                      await ApiService.instance.overrideIssue(
                        issueId, 'reassign', newLeaderId: selectedLeaderId,
                      );
                      ref.invalidate(escalatedIssuesProvider);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Issue reassigned'), backgroundColor: AppColors.success),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
                      );
                    }
                  },
            child: const Text('Reassign'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDialog(String title, String message, Color color) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: color),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final escalatedAsync = ref.watch(escalatedIssuesProvider);
    final adminAsync = ref.watch(adminDashboardProvider);
    final leadersAsync = ref.watch(usersProvider('leader'));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Higher Authority'),
        actions: [
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
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Escalated Issues', icon: Icon(Icons.warning_amber, size: 18)),
            Tab(text: 'Leader Rankings', icon: Icon(Icons.bar_chart, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // ── Escalated Issues ──────────────────────────────────────────────
          escalatedAsync.when(
            data: (issues) {
              if (issues.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 72, color: AppColors.success),
                      SizedBox(height: 16),
                      Text('No escalated issues!',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.success)),
                      SizedBox(height: 8),
                      Text('All issues are being handled properly.',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                );
              }

              return leadersAsync.when(
                data: (leaders) => ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: issues.length,
                  itemBuilder: (_, i) => _EscalatedCard(
                    issue: issues[i],
                    onClose: () => _closeIssue(issues[i].id),
                    onReassign: () => _reassignIssue(issues[i].id, leaders),
                  ),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: issues.length,
                  itemBuilder: (_, i) => _EscalatedCard(
                    issue: issues[i],
                    onClose: () => _closeIssue(issues[i].id),
                    onReassign: () {},
                  ),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),

          // ── Leader Rankings ───────────────────────────────────────────────
          adminAsync.when(
            data: (data) {
              final stats = data['stats'] as Map<String, dynamic>? ?? {};
              final rankings = data['leader_rankings'] as List? ?? [];

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Admin stats
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.6,
                      children: [
                        MetricCard(label: 'Total Issues', value: stats['total_issues'] ?? 0, icon: Icons.list_alt, color: AppColors.primary),
                        MetricCard(label: 'Escalated', value: stats['escalated_issues'] ?? 0, icon: Icons.warning_amber, color: AppColors.statusEscalated),
                        MetricCard(label: 'Resolved', value: stats['resolved_issues'] ?? 0, icon: Icons.check_circle, color: AppColors.success),
                        MetricCard(label: 'Open Issues', value: stats['open_issues'] ?? 0, icon: Icons.radio_button_checked, color: AppColors.info),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Leader Performance'),
                    ...rankings.map((r) => _LeaderRankCard(data: r)),
                  ],
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ],
      ),
    );
  }
}

class _EscalatedCard extends StatelessWidget {
  final Issue issue;
  final VoidCallback onClose;
  final VoidCallback onReassign;

  const _EscalatedCard({required this.issue, required this.onClose, required this.onReassign});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: AppColors.statusEscalated,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text('ESCALATED', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 6),
                Text(issue.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (issue.citizenName != null) ...[
                      const Icon(Icons.person_outline, size: 14, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Text(issue.citizenName!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(width: 12),
                    ],
                    if (issue.leaderName != null) ...[
                      const Icon(Icons.shield_outlined, size: 14, color: AppColors.error),
                      const SizedBox(width: 4),
                      Text(issue.leaderName!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onReassign,
                        icon: const Icon(Icons.person_search, size: 15),
                        label: const Text('Reassign'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onClose,
                        icon: const Icon(Icons.lock_outline, size: 15),
                        label: const Text('Close Issue'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderRankCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _LeaderRankCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final failedCases = data['failed_cases'] as int? ?? 0;
    final isHighRisk = failedCases >= 3;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isHighRisk ? AppColors.errorLight : AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isHighRisk ? Icons.warning_amber : Icons.shield_outlined,
                color: isHighRisk ? AppColors.error : AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(data['email'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(
                    '${data['total_issues'] ?? 0} total • ${data['resolved_issues'] ?? 0} resolved',
                    style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: failedCases == 0
                        ? AppColors.successLight
                        : isHighRisk ? AppColors.errorLight : AppColors.warningLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$failedCases Failures',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: failedCases == 0
                          ? AppColors.success
                          : isHighRisk ? AppColors.error : AppColors.warning,
                    ),
                  ),
                ),
                if (isHighRisk) ...[
                  const SizedBox(height: 4),
                  const Text('⚠️ High Risk',
                      style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}