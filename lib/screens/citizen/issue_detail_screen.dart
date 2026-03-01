import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/issues_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common_widgets.dart';

class IssueDetailScreen extends ConsumerStatefulWidget {
  final String issueId;
  const IssueDetailScreen({super.key, required this.issueId});

  @override
  ConsumerState<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends ConsumerState<IssueDetailScreen> {
  bool _actionLoading = false;

  Future<void> _verify(bool approved) async {
    setState(() => _actionLoading = true);
    try {
      final result = await ApiService.instance.verifyResolution(
        widget.issueId,
        approved,
        feedback: approved ? 'Resolved!' : 'Not satisfactory',
      );
      if (!mounted) return;
      ref.invalidate(issueDetailProvider(widget.issueId));
      ref.invalidate(issuesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Done'),
          backgroundColor: approved ? AppColors.success : AppColors.warning,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final issueAsync = ref.watch(issueDetailProvider(widget.issueId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Issue Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(auth.role == 'leader' ? '/leader/issues' : '/citizen/issues'),
        ),
      ),
      body: issueAsync.when(
        data: (issue) {
          final status = issue['status'] ?? 'OPEN';
          final attempts = issue['resolution_attempts'] ?? 0;
          final isCitizen = auth.role == 'citizen';
          final canVerify = isCitizen && (status == 'RESOLVED_L1' || status == 'RESOLVED_L2');

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status & resolution ticks header
                Row(
                  children: [
                    StatusBadge(status: status),
                    const Spacer(),
                    ResolutionTicks(attempts: attempts, status: status),
                  ],
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  issue['title'] ?? '',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 12),

                // Description
                Text(
                  issue['description'] ?? '',
                  style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.5),
                ),

                const SizedBox(height: 20),

                // Info cards
                _InfoRow(icon: Icons.category_outlined, label: 'Category', value: issue['category'] ?? 'Analyzing...'),
                _InfoRow(
                  icon: Icons.priority_high,
                  label: 'Urgency',
                  value: (issue['urgency_level'] ?? 'Analyzing...').toString().toUpperCase(),
                ),
                _InfoRow(
                  icon: Icons.score,
                  label: 'Priority Score',
                  value: issue['priority_score'] != null
                      ? '${((issue['priority_score'] as num) * 100).toStringAsFixed(0)}%'
                      : 'Analyzing...',
                ),
                if (issue['citizen_name'] != null)
                  _InfoRow(icon: Icons.person_outline, label: 'Reported by', value: issue['citizen_name']),
                if (issue['leader_name'] != null)
                  _InfoRow(icon: Icons.shield_outlined, label: 'Assigned Leader', value: issue['leader_name']),
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Reported',
                  value: DateFormat('MMM d, yyyy HH:mm').format(
                    DateTime.tryParse(issue['created_at'] ?? '') ?? DateTime.now(),
                  ),
                ),

                // Location
                if (issue['location'] != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            issue['location']['address'] ??
                                '${issue['location']['latitude']?.toStringAsFixed(4)}, ${issue['location']['longitude']?.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Images
                if (issue['image_urls'] != null && (issue['image_urls'] as List).isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Photos', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: (issue['image_urls'] as List).length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            'http://10.0.2.2:8000${issue['image_urls'][i]}',
                            width: 120, height: 120, fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                // Escalation notice
                if (status == 'ESCALATED') ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.warning_amber, color: AppColors.error),
                          SizedBox(width: 8),
                          Text('Escalated to Higher Authority',
                              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.error)),
                        ]),
                        SizedBox(height: 8),
                        Text(
                          'The assigned leader failed to resolve this issue after 2 attempts. '
                          'It has been escalated to the Higher Authority for action.',
                          style: TextStyle(fontSize: 13, color: AppColors.error),
                        ),
                      ],
                    ),
                  ),
                ],

                // Citizen verification panel
                if (canVerify) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.success.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.verified_user_outlined, color: AppColors.success),
                            const SizedBox(width: 8),
                            Text(
                              'Resolution ${status == "RESOLVED_L1" ? "✔" : "✔✔"} Pending Your Approval',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          status == 'RESOLVED_L1'
                              ? 'Leader submitted first resolution. Is the issue fixed?'
                              : 'Leader submitted second resolution. Final chance – reject escalates to Higher Authority.',
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _actionLoading ? null : () => _verify(false),
                                icon: const Icon(Icons.close, color: AppColors.error),
                                label: const Text('Reject', style: TextStyle(color: AppColors.error)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.error),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _actionLoading ? null : () => _verify(true),
                                icon: const Icon(Icons.check),
                                label: const Text('Approve'),
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textHint),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}