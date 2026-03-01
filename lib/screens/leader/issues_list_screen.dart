import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../providers/issues_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common_widgets.dart';

class LeaderIssuesListScreen extends ConsumerStatefulWidget {
  const LeaderIssuesListScreen({super.key});

  @override
  ConsumerState<LeaderIssuesListScreen> createState() => _LeaderIssuesListScreenState();
}

class _LeaderIssuesListScreenState extends ConsumerState<LeaderIssuesListScreen> {
  final _resolveCtrl = TextEditingController();

  @override
  void dispose() {
    _resolveCtrl.dispose();
    super.dispose();
  }

  Future<void> _showResolveDialog(String issueId, String currentStatus, int attempts) async {
    _resolveCtrl.clear();

    final attemptNum = attempts + 1;
    final isSecondAttempt = attemptNum == 2;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isSecondAttempt ? Icons.warning_amber : Icons.check_circle_outline,
              color: isSecondAttempt ? AppColors.warning : AppColors.success,
            ),
            const SizedBox(width: 8),
            Text('Submit Resolution ${isSecondAttempt ? "(Final)" : ""}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSecondAttempt)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '⚠️ This is your final attempt. If the citizen rejects this, the issue will be escalated and counted as a failure.',
                  style: TextStyle(fontSize: 13, color: AppColors.warning),
                ),
              ),
            TextField(
              controller: _resolveCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Describe what was done to resolve the issue...',
                hintStyle: const TextStyle(fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_resolveCtrl.text.trim().length < 5) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please add resolution notes (min 5 chars)')),
                );
                return;
              }
              Navigator.pop(ctx);
              await _submitResolution(issueId, _resolveCtrl.text.trim());
            },
            child: Text('Submit Resolution ${isSecondAttempt ? "✔✔" : "✔"}'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitResolution(String issueId, String notes) async {
    try {
      final result = await ApiService.instance.resolveIssue(issueId, notes);
      if (!mounted) return;
      ref.invalidate(issuesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Resolved!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final issuesAsync = ref.watch(issuesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assigned Issues'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/leader'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(issuesProvider.notifier).fetchIssues(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), label: 'Issues'),
          NavigationDestination(icon: Icon(Icons.task_outlined), label: 'Tasks'),
        ],
        selectedIndex: 1,
        onDestinationSelected: (i) {
          if (i == 0) context.go('/leader');
          if (i == 2) context.go('/leader/tasks');
        },
      ),
      body: issuesAsync.when(
        data: (issues) {
          if (issues.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 72, color: AppColors.textHint),
                  SizedBox(height: 16),
                  Text('No issues assigned to you',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: issues.length,
            itemBuilder: (_, i) {
              final issue = issues[i];
              final canResolve = issue.status == 'OPEN' || issue.status == 'RESOLVED_L1';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () => context.go('/issue/${issue.id}'),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    issue.title,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                  ),
                                ),
                                StatusBadge(status: issue.status),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              issue.description,
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                if (issue.category != null)
                                  _chip(issue.category!),
                                const Spacer(),
                                ResolutionTicks(attempts: issue.resolutionAttempts, status: issue.status),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (canResolve) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => context.go('/leader/tasks'),
                                icon: const Icon(Icons.task_alt, size: 16),
                                label: const Text('Create Task'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _showResolveDialog(
                                  issue.id, issue.status, issue.resolutionAttempts,
                                ),
                                icon: const Icon(Icons.check, size: 16),
                                label: Text(issue.resolutionAttempts == 0 ? 'Resolve ✔' : 'Resolve ✔✔'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: issue.resolutionAttempts == 0
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w500)),
    );
  }
}