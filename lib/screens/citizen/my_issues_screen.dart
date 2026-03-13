import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../providers/issues_provider.dart';
import '../../widgets/common_widgets.dart';

// ── Urgency helpers ──────────────────────────────────────────────────────────

enum Urgency { critical, high, medium, low }

extension UrgencyExt on Urgency {
  String get label {
    switch (this) {
      case Urgency.critical: return '🔴 Critical';
      case Urgency.high:     return '🟠 High';
      case Urgency.medium:   return '🟡 Medium';
      case Urgency.low:      return '🟢 Low';
    }
  }

  Color get color {
    switch (this) {
      case Urgency.critical: return const Color(0xFFB71C1C);
      case Urgency.high:     return const Color(0xFFE65100);
      case Urgency.medium:   return const Color(0xFFF9A825);
      case Urgency.low:      return const Color(0xFF2E7D32);
    }
  }

  Color get bgColor => color.withOpacity(0.12);
}

Urgency urgencyFromScore(double score) {
  if (score >= 0.75) return Urgency.critical;
  if (score >= 0.50) return Urgency.high;
  if (score >= 0.25) return Urgency.medium;
  return Urgency.low;
}

// ── Sort type ────────────────────────────────────────────────────────────────

enum SortType { latest, urgency }

// ── Screen ───────────────────────────────────────────────────────────────────

class MyIssuesScreen extends ConsumerStatefulWidget {
  const MyIssuesScreen({super.key});

  @override
  ConsumerState<MyIssuesScreen> createState() => _MyIssuesScreenState();
}

class _MyIssuesScreenState extends ConsumerState<MyIssuesScreen> {
  String _selectedStatus = 'All';
  SortType _sortType = SortType.latest;

  static const _statuses = [
    'All',
    'OPEN',
    'RESOLVED_L1',
    'RESOLVED_L2',
    'CLOSED',
    'ESCALATED',
  ];

  String _labelFor(String status) {
    switch (status) {
      case 'All':         return 'All';
      case 'RESOLVED_L1': return 'Resolved ✔';
      case 'RESOLVED_L2': return 'Resolved ✔✔';
      default:
        return status[0] + status.substring(1).toLowerCase();
    }
  }

  /// Filter + sort the raw list
  List<dynamic> _process(List<dynamic> issues) {
    // 1. Filter
    final filtered = _selectedStatus == 'All'
        ? issues
        : issues.where((i) => i.status == _selectedStatus).toList();

    // 2. Sort
    final sorted = List<dynamic>.from(filtered);
    if (_sortType == SortType.latest) {
      sorted.sort((a, b) {
        final ta = (a.createdAt as DateTime?) ?? DateTime(0);
        final tb = (b.createdAt as DateTime?) ?? DateTime(0);
        return tb.compareTo(ta);                      // newest first
      });
    } else {
      sorted.sort((a, b) {
        final pa = (a.priorityScore as double?) ?? 0.0;
        final pb = (b.priorityScore as double?) ?? 0.0;
        return pb.compareTo(pa);                      // highest urgency first
      });
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final issuesAsync = ref.watch(issuesProvider);
    // Responsive: use screen width to scale paddings & font sizes
    final sw = MediaQuery.of(context).size.width;
    final isWide = sw > 600;

    return PopScope(
      // Intercept Android hardware back button too
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        appBar: _buildAppBar(context),
        floatingActionButton: _buildFab(context, isWide),
        body: issuesAsync.when(
          data: (issues) => issues.isEmpty
              ? _buildEmpty(isWide)
              : _buildContent(issues, isWide),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _buildError(e),
        ),
      ),
    );
  }

  void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      // Navigate explicitly to citizen dashboard instead of exiting
      context.go('/citizen');
    }
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  AppBar _buildAppBar(BuildContext context) => AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.black),
          onPressed: () => _handleBack(context),
        ),
        title: const Text(
          'My Issues',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Color(0xFF1A1A2E),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.read(issuesProvider.notifier).fetchIssues(),
          ),
        ],
      );

  // ── FAB ───────────────────────────────────────────────────────────────────

  Widget _buildFab(BuildContext context, bool isWide) =>
      FloatingActionButton.extended(
        onPressed: () => context.go('/citizen/submit'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Report New',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: isWide ? 15 : 14,
          ),
        ),
      );

  // ── Main content ──────────────────────────────────────────────────────────

  Widget _buildContent(List<dynamic> issues, bool isWide) {
    final processed = _process(issues);
    // Responsive horizontal padding: wider on tablets/desktops
    final hPad = isWide ? 32.0 : 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFilterAndSort(issues, hPad),
        const SizedBox(height: 4),
        _buildResultCount(processed.length, hPad),
        Expanded(
          child: processed.isEmpty
              ? _buildNoMatch()
              : isWide
                  // 2-column grid on wide screens
                  ? GridView.builder(
                      padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 100),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 0,
                        childAspectRatio: 2.6,
                      ),
                      itemCount: processed.length,
                      itemBuilder: (_, i) => _IssueCardWrapper(
                        issue: processed[i],
                        onTap: () =>
                            context.go('/issue/${processed[i].id}'),
                      ),
                    )
                  : ListView.builder(
                      padding:
                          EdgeInsets.fromLTRB(hPad, 4, hPad, 100),
                      itemCount: processed.length,
                      itemBuilder: (_, i) => _IssueCardWrapper(
                        issue: processed[i],
                        onTap: () =>
                            context.go('/issue/${processed[i].id}'),
                      ),
                    ),
        ),
      ],
    );
  }

  // ── Filter row + sort pill ────────────────────────────────────────────────

  Widget _buildFilterAndSort(List<dynamic> allIssues, double hPad) =>
      Container(
        color: Colors.white,
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status filter chips
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: hPad),
                itemCount: _statuses.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final s = _statuses[i];
                  final selected = s == _selectedStatus;
                  final count = s == 'All'
                      ? allIssues.length
                      : allIssues.where((x) => x.status == s).length;

                  return _StatusChip(
                    label: _labelFor(s),
                    count: count,
                    selected: selected,
                    onTap: () => setState(() => _selectedStatus = s),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            // Sort row
            Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              child: Row(
                children: [
                  const Text(
                    'Sort by:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _SortPill(
                    label: 'Latest',
                    icon: Icons.access_time_rounded,
                    selected: _sortType == SortType.latest,
                    onTap: () =>
                        setState(() => _sortType = SortType.latest),
                  ),
                  const SizedBox(width: 8),
                  _SortPill(
                    label: 'Urgency',
                    icon: Icons.local_fire_department_rounded,
                    selected: _sortType == SortType.urgency,
                    onTap: () =>
                        setState(() => _sortType = SortType.urgency),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildResultCount(int count, double hPad) => Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 6),
        child: Text(
          '$count issue${count == 1 ? '' : 's'}',
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF9CA3AF),
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  // ── Empty / error states ──────────────────────────────────────────────────

  Widget _buildEmpty(bool isWide) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(isWide ? 32 : 24),
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inbox_outlined,
                size: isWide ? 72 : 56,
                color: const Color(0xFF9CA3AF),
              ),
            ),
            SizedBox(height: isWide ? 28 : 20),
            Text(
              'No issues reported yet',
              style: TextStyle(
                fontSize: isWide ? 22 : 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isWide ? 120 : 40),
              child: const Text(
                'Tap "Report New" below to raise your first civic issue',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      );

  Widget _buildNoMatch() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.filter_list_off_rounded,
                size: 48, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            Text(
              'No "${_labelFor(_selectedStatus)}" issues',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      );

  Widget _buildError(Object e) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 56, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 16),
            Text(
              'Could not load issues',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              e.toString(),
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.read(issuesProvider.notifier).fetchIssues(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      );
}

// ── _StatusChip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF374151),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withOpacity(0.25)
                      : const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color:
                        selected ? Colors.white : const Color(0xFF6B7280),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── _SortPill ─────────────────────────────────────────────────────────────────

class _SortPill extends StatelessWidget {
  const _SortPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : const Color(0xFFD1D5DB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? AppColors.primary
                  : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AppColors.primary
                    : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _IssueCardWrapper  ────────────────────────────────────────────────────────
// Wraps IssueCard and places the urgency chip BELOW the card in a Column
// so it never overlaps the status badge rendered inside IssueCard.

class _IssueCardWrapper extends StatelessWidget {
  const _IssueCardWrapper({required this.issue, required this.onTap});

  final dynamic issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final score = (issue.priorityScore as double?) ?? 0.0;
    final urgency = urgencyFromScore(score);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The existing card — rendered without its own margin/shadow
            // since we're wrapping it here
            IssueCard(issue: issue, onTap: onTap),
            // Urgency chip row — always below the card content, no overlap
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_fire_department_rounded,
                    size: 13,
                    color: Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Urgency:',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _UrgencyChip(urgency: urgency),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _UrgencyChip ──────────────────────────────────────────────────────────────

class _UrgencyChip extends StatelessWidget {
  const _UrgencyChip({required this.urgency});

  final Urgency urgency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: urgency.bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: urgency.color.withOpacity(0.4)),
      ),
      child: Text(
        urgency.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: urgency.color,
        ),
      ),
    );
  }
}