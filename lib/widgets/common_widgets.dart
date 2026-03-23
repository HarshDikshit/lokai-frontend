import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../models/models.dart';
import '../core/localization.dart';

// ── Status Badge ────────────────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = _getStatusProps(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  (Color, String, IconData) _getStatusProps(BuildContext context, String status) {
    switch (status) {
      case 'OPEN':
        return (AppColors.statusOpen, context.translate('status_open'), Icons.radio_button_checked);
      case 'RESOLVED_L1':
        return (AppColors.success, context.translate('status_resolved_l1'), Icons.check_circle_outline);
      case 'RESOLVED_L2':
        return (AppColors.statusResolvedL2, context.translate('status_resolved_l2'), Icons.check_circle);
      case 'ESCALATED':
        return (AppColors.statusEscalated, context.translate('status_escalated'), Icons.warning_amber);
      case 'CLOSED':
        return (AppColors.statusClosed, context.translate('status_closed'), Icons.lock_outline);
      default:
        return (AppColors.textSecondary, status, Icons.circle_outlined);
    }
  }
}

// ── Resolution Ticks ─────────────────────────────────────────────────────────
class ResolutionTicks extends StatelessWidget {
  final int attempts;
  final String status;

  const ResolutionTicks({super.key, required this.attempts, required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == 'OPEN' && attempts == 0) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _tick(1, attempts >= 1 && status != 'OPEN'),
        if (attempts >= 2 || status == 'RESOLVED_L2' || status == 'CLOSED') ...[
          const SizedBox(width: 4),
          _tick(2, status == 'RESOLVED_L2' || status == 'CLOSED'),
        ],
      ],
    );
  }

  Widget _tick(int n, bool active) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: active ? AppColors.success : AppColors.borderColor,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.check,
        size: 16,
        color: active ? Colors.white : AppColors.textHint,
      ),
    );
  }
}

// ── Issue Card ────────────────────────────────────────────────────────────────
class IssueCard extends StatelessWidget {
  final Issue issue;
  final VoidCallback? onTap;

  const IssueCard({super.key, required this.issue, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge(status: issue.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                issue.description,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (issue.category != null) ...[
                    _chip(Icons.category_outlined, context.translate('cat_${_catKey(issue.category!)}')),
                    const SizedBox(width: 8),
                  ],
                  if (issue.urgencyLevel != null)
                    _chip(Icons.priority_high, context.translate('urgency_${issue.urgencyLevel!.toLowerCase()}'),
                        color: _urgencyColor(issue.urgencyLevel!)),
                  const Spacer(),
                  ResolutionTicks(
                    attempts: issue.resolutionAttempts,
                    status: issue.status,
                  ),
                ],
              ),
              if (issue.citizenName != null || issue.leaderName != null) ...[
                const SizedBox(height: 8),
                const Divider(height: 1, color: AppColors.borderColor),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (issue.citizenName != null)
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline, size: 14, color: AppColors.textHint),
                            const SizedBox(width: 4),
                            Text(issue.citizenName!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    if (issue.leaderName != null)
                      Row(
                        children: [
                          const Icon(Icons.shield_outlined, size: 14, color: AppColors.textHint),
                          const SizedBox(width: 4),
                          Text(issue.leaderName!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? AppColors.primary).withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color ?? AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color ?? AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _urgencyColor(String level) {
    switch (level.toLowerCase()) {
      case 'critical': return AppColors.error;
      case 'high': return AppColors.statusEscalated;
      case 'medium': return AppColors.warning;
      default: return AppColors.success;
    }
  }

  String _catKey(String cat) {
    final map = {
      'Infrastructure & Roads': 'infra',
      'Sanitation & Waste':    'sanitation',
      'Water Supply':          'water',
      'Electricity':           'electricity',
      'Public Safety':         'safety',
      'Healthcare':            'health',
      'Education':             'edu',
      'Transportation':        'transp',
      'Environment':           'env',
      'Government Services':   'gov',
      'General':               'gen',
    };
    return map[cat] ?? 'gen';
  }
}

// ── Metric Card ───────────────────────────────────────────────────────────────
class MetricCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value.toString(),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ── Loading Overlay ───────────────────────────────────────────────────────────
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;

  const LoadingOverlay({super.key, required this.isLoading, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          const ColoredBox(
            color: Colors.black26,
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;

  const SectionHeader({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}
