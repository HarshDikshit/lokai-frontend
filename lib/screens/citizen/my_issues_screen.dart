// screens/citizen/my_issues_screen.dart
// Adds duplicate-detection badges to the existing filter/sort/urgency UI.
// All existing logic (filter chips, sort pills, responsive grid, empty states)
// is preserved exactly. New: _MatchStatusBadge row inside _IssueCardWrapper.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../providers/issues_provider.dart';
import '../../widgets/common_widgets.dart';

// ── Urgency helpers ───────────────────────────────────────────────────────────

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

// ── Sort type ─────────────────────────────────────────────────────────────────

enum SortType { latest, urgency }

// ── Screen ────────────────────────────────────────────────────────────────────

class MyIssuesScreen extends ConsumerStatefulWidget {
  const MyIssuesScreen({super.key});

  @override
  ConsumerState<MyIssuesScreen> createState() => _MyIssuesScreenState();
}

class _MyIssuesScreenState extends ConsumerState<MyIssuesScreen> {
  String   _selectedStatus = 'All';
  SortType _sortType       = SortType.latest;

  static const _statuses = [
    'All', 'OPEN', 'RESOLVED_L1', 'RESOLVED_L2', 'CLOSED', 'ESCALATED',
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

  List<dynamic> _process(List<dynamic> issues) {
    final filtered = _selectedStatus == 'All'
        ? issues
        : issues.where((i) => i.status == _selectedStatus).toList();

    final sorted = List<dynamic>.from(filtered);
    if (_sortType == SortType.latest) {
      sorted.sort((a, b) {
        final ta = (a.createdAt as DateTime?) ?? DateTime(0);
        final tb = (b.createdAt as DateTime?) ?? DateTime(0);
        return tb.compareTo(ta);
      });
    } else {
      sorted.sort((a, b) {
        final pa = (a.priorityScore as double?) ?? 0.0;
        final pb = (b.priorityScore as double?) ?? 0.0;
        return pb.compareTo(pa);
      });
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final issuesAsync = ref.watch(issuesProvider);
    final sw   = MediaQuery.of(context).size.width;
    final isWide = sw > 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: _buildAppBar(context),
      floatingActionButton: _buildFab(context, isWide),
      body: issuesAsync.when(
        data:    (issues) => issues.isEmpty
            ? _buildEmpty(isWide)
            : _buildContent(issues, isWide),
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => _buildError(e),
      ),
    );
  }

  void _handleBack(BuildContext context) {
    if (context.canPop()) context.pop();
    else context.go('/citizen');
  }

  AppBar _buildAppBar(BuildContext context) => AppBar(
    elevation: 0,
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.black),
      onPressed: () => _handleBack(context),
    ),
    title: const Text('My Issues',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20,
            color: Color(0xFF1A1A2E))),
    actions: [
      IconButton(
        icon: const Icon(Icons.refresh_rounded),
        tooltip: 'Refresh',
        onPressed: () => ref.read(issuesProvider.notifier).fetchIssues(),
      ),
    ],
  );

  Widget _buildFab(BuildContext context, bool isWide) =>
      FloatingActionButton.extended(
        onPressed: () => context.go('/citizen/submit'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_rounded),
        label: Text('Report New',
            style: TextStyle(fontWeight: FontWeight.w600,
                fontSize: isWide ? 15 : 14)),
      );

  Widget _buildContent(List<dynamic> issues, bool isWide) {
    final processed = _process(issues);
    final hPad = isWide ? 32.0 : 16.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildFilterAndSort(issues, hPad),
      const SizedBox(height: 4),
      _buildResultCount(processed.length, hPad),
      Expanded(
        child: processed.isEmpty
            ? _buildNoMatch()
            : isWide
                ? GridView.builder(
                    padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 100),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 0,
                      childAspectRatio: 2.4,   // slightly taller to fit badge
                    ),
                    itemCount: processed.length,
                    itemBuilder: (_, i) => _IssueCardWrapper(
                      issue: processed[i],
                      onTap: () => context.push('/issue/${processed[i].id}'),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 100),
                    itemCount: processed.length,
                    itemBuilder: (_, i) => _IssueCardWrapper(
                      issue: processed[i],
                      onTap: () => context.push('/issue/${processed[i].id}'),
                    ),
                  ),
      ),
    ]);
  }

  Widget _buildFilterAndSort(List<dynamic> allIssues, double hPad) =>
      Container(
        color: Colors.white,
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: hPad),
              itemCount: _statuses.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s        = _statuses[i];
                final selected = s == _selectedStatus;
                final count    = s == 'All'
                    ? allIssues.length
                    : allIssues.where((x) => x.status == s).length;
                return _StatusChip(
                  label:    _labelFor(s),
                  count:    count,
                  selected: selected,
                  onTap:    () => setState(() => _selectedStatus = s),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: Row(children: [
              const Text('Sort by:', style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w500, color: Color(0xFF6B7280))),
              const SizedBox(width: 10),
              _SortPill(
                label:    'Latest',
                icon:     Icons.access_time_rounded,
                selected: _sortType == SortType.latest,
                onTap:    () => setState(() => _sortType = SortType.latest),
              ),
              const SizedBox(width: 8),
              _SortPill(
                label:    'Urgency',
                icon:     Icons.local_fire_department_rounded,
                selected: _sortType == SortType.urgency,
                onTap:    () => setState(() => _sortType = SortType.urgency),
              ),
            ]),
          ),
        ]),
      );

  Widget _buildResultCount(int count, double hPad) => Padding(
    padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 6),
    child: Text('$count issue${count == 1 ? '' : 's'}',
        style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF),
            fontWeight: FontWeight.w500)),
  );

  Widget _buildEmpty(bool isWide) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: EdgeInsets.all(isWide ? 32 : 24),
        decoration: const BoxDecoration(
            color: Color(0xFFF3F4F6), shape: BoxShape.circle),
        child: Icon(Icons.inbox_outlined,
            size: isWide ? 72 : 56, color: const Color(0xFF9CA3AF)),
      ),
      SizedBox(height: isWide ? 28 : 20),
      Text('No issues reported yet',
          style: TextStyle(fontSize: isWide ? 22 : 18,
              fontWeight: FontWeight.w700, color: const Color(0xFF374151))),
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
    ]),
  );

  Widget _buildNoMatch() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.filter_list_off_rounded,
          size: 48, color: Color(0xFFD1D5DB)),
      const SizedBox(height: 12),
      Text('No "${_labelFor(_selectedStatus)}" issues',
          style: const TextStyle(fontSize: 16,
              fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
    ]),
  );

  Widget _buildError(Object e) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.cloud_off_rounded, size: 56, color: Color(0xFFD1D5DB)),
      const SizedBox(height: 16),
      const Text('Could not load issues',
          style: TextStyle(fontSize: 16,
              fontWeight: FontWeight.w600, color: Color(0xFF374151))),
      const SizedBox(height: 6),
      Text(e.toString(),
          style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
          textAlign: TextAlign.center),
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: () => ref.read(issuesProvider.notifier).fetchIssues(),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Retry'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ]),
  );
}

// ── _StatusChip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String       label;
  final int          count;
  final bool         selected;
  final VoidCallback onTap;
  const _StatusChip({
    required this.label, required this.count,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color:  selected ? AppColors.primary : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFE5E7EB)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF374151))),
        if (count > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withOpacity(0.25)
                  : const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count', style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF6B7280))),
          ),
        ],
      ]),
    ),
  );
}

// ── _SortPill ─────────────────────────────────────────────────────────────────

class _SortPill extends StatelessWidget {
  final String       label;
  final IconData     icon;
  final bool         selected;
  final VoidCallback onTap;
  const _SortPill({
    required this.label, required this.icon,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFD1D5DB)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14,
            color: selected ? AppColors.primary : const Color(0xFF6B7280)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : const Color(0xFF6B7280))),
      ]),
    ),
  );
}

// ── _IssueCardWrapper ─────────────────────────────────────────────────────────
// Wraps IssueCard, places urgency chip below it, and adds the
// duplicate-detection match-status badge when present.

class _IssueCardWrapper extends StatelessWidget {
  final dynamic      issue;
  final VoidCallback onTap;
  const _IssueCardWrapper({required this.issue, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final score   = (issue.priorityScore as double?) ?? 0.0;
    final urgency = urgencyFromScore(score);

    // Match status from duplicate pipeline (nullable — safe on old data)
    final String? matchStatus = issue.matchStatus as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8, offset: const Offset(0, 2),
        )],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Existing card content
          IssueCard(issue: issue, onTap: onTap),

          // Urgency chip row (unchanged)
          Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, matchStatus != null ? 4 : 10),
            child: Row(children: [
              const Icon(Icons.local_fire_department_rounded,
                  size: 13, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 4),
              const Text('Urgency:', style: TextStyle(fontSize: 11,
                  color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500)),
              const SizedBox(width: 6),
              _UrgencyChip(urgency: urgency),
            ]),
          ),

          // ── NEW: match status row ────────────────────────────────────
          if (matchStatus != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _MatchStatusBadge(matchStatus: matchStatus),
            ),
        ]),
      ),
    );
  }
}

// ── _MatchStatusBadge ─────────────────────────────────────────────────────────

class _MatchStatusBadge extends StatelessWidget {
  final String matchStatus;
  const _MatchStatusBadge({required this.matchStatus});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final String   label;
    final Color    color;

    if (matchStatus == 'auto_merged') {
      icon  = Icons.merge_rounded;
      label = 'Merged with similar reports';
      color = const Color(0xFF2E7D32);
    } else if (matchStatus == 'pending_review') {
      icon  = Icons.hourglass_top_rounded;
      label = 'Under duplicate review';
      color = const Color(0xFFF9A825);
    } else {
      icon  = Icons.fiber_new_rounded;
      label = 'First report in this area';
      color = AppColors.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11,
            fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

// ── _UrgencyChip ─────────────────────────────────────────────────────────────

class _UrgencyChip extends StatelessWidget {
  final Urgency urgency;
  const _UrgencyChip({required this.urgency});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color:  urgency.bgColor,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: urgency.color.withOpacity(0.4)),
    ),
    child: Text(urgency.label, style: TextStyle(fontSize: 11,
        fontWeight: FontWeight.w700, color: urgency.color)),
  );
}