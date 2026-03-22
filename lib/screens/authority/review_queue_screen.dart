// screens/authority/review_queue_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

String _priorityLabel(double s) {
  if (s >= 0.8) return 'CRITICAL';
  if (s >= 0.6) return 'HIGH';
  if (s >= 0.4) return 'MEDIUM';
  return 'LOW';
}

Color _priorityColor(double s) {
  if (s >= 0.8) return const Color(0xFFB71C1C);
  if (s >= 0.6) return const Color(0xFFE65100);
  if (s >= 0.4) return const Color(0xFFF9A825);
  return const Color(0xFF2E7D32);
}

// ─────────────────────────────────────────────────────────────────────────────
// Standalone screen (navigated to via /authority/review-queue)
// ─────────────────────────────────────────────────────────────────────────────
class ReviewQueueScreen extends StatefulWidget {
  const ReviewQueueScreen({super.key});
  @override
  State<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends State<ReviewQueueScreen> {
  List<ReviewQueueItem> _items    = [];
  bool                  _loading  = true;
  String?               _error;
  Timer?                _pollTimer;
  final Set<String>     _removing = {};

  @override
  void initState() {
    super.initState();
    _fetch();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => _fetch());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    try {
      final raw = await ApiService.instance.getReviewQueue();
      if (!mounted) return;
      setState(() {
        _items   = raw.map((e) =>
            ReviewQueueItem.fromJson(e as Map<String, dynamic>)).toList();
        _loading = false;
        _error   = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _decide(ReviewQueueItem item, String decision) async {
    setState(() => _removing.add(item.reviewId));
    try {
      await ApiService.instance.decideReview(item.reviewId, decision);
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() {
        _items.removeWhere((i) => i.reviewId == item.reviewId);
        _removing.remove(item.reviewId);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(decision == 'merge'
            ? 'Merged into cluster ✓' : 'Created as new separate issue ✓'),
        backgroundColor:
            decision == 'merge' ? AppColors.success : AppColors.primary,
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _removing.remove(item.reviewId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        title: const Text('Review Queue'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _items.isEmpty
                      ? Colors.white.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _items.isEmpty ? 'All clear' : '${_items.length} pending',
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700, color: Colors.white),
                ),
              )),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () { setState(() => _loading = true); _fetch(); },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(error: _error!, onRetry: _fetch)
              : _items.isEmpty
                  ? const _EmptyState()
                  : RefreshIndicator(
                      onRefresh: _fetch,
                      color: AppColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final item = _items[i];
                          return AnimatedSlide(
                            offset: _removing.contains(item.reviewId)
                                ? const Offset(1, 0) : Offset.zero,
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeInBack,
                            child: AnimatedOpacity(
                              opacity: _removing.contains(item.reviewId) ? 0 : 1,
                              duration: const Duration(milliseconds: 280),
                              child: _ReviewCard(
                                item:     item,
                                onMerge:  () => _decide(item, 'merge'),
                                onReject: () => _decide(item, 'reject'),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Embeddable tab body — used inside AuthorityScreen TabBarView.
// onCountChanged fires every time the list is refreshed so the parent
// can update the tab badge count.
// ─────────────────────────────────────────────────────────────────────────────
class ReviewQueueTabBody extends StatefulWidget {
  /// Called after every fetch with the current pending item count.
  final void Function(int count)? onCountChanged;

  const ReviewQueueTabBody({super.key, this.onCountChanged});

  @override
  State<ReviewQueueTabBody> createState() => _ReviewQueueTabBodyState();
}

class _ReviewQueueTabBodyState extends State<ReviewQueueTabBody> {
  List<ReviewQueueItem> _items    = [];
  bool                  _loading  = true;
  String?               _error;
  Timer?                _pollTimer;
  final Set<String>     _removing = {};

  @override
  void initState() {
    super.initState();
    _fetch();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => _fetch());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    try {
      final raw = await ApiService.instance.getReviewQueue();
      if (!mounted) return;
      setState(() {
        _items   = raw.map((e) =>
            ReviewQueueItem.fromJson(e as Map<String, dynamic>)).toList();
        _loading = false;
        _error   = null;
      });
      // Notify parent (AuthorityScreen) so it can update the tab badge
      widget.onCountChanged?.call(_items.length);
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _decide(ReviewQueueItem item, String decision) async {
    setState(() => _removing.add(item.reviewId));
    try {
      await ApiService.instance.decideReview(item.reviewId, decision);
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() {
        _items.removeWhere((i) => i.reviewId == item.reviewId);
        _removing.remove(item.reviewId);
      });
      // Update badge after item removed
      widget.onCountChanged?.call(_items.length);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(decision == 'merge'
            ? 'Merged into cluster ✓' : 'Created as new separate issue ✓'),
        backgroundColor:
            decision == 'merge' ? AppColors.success : AppColors.primary,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _removing.remove(item.reviewId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorState(error: _error!, onRetry: _fetch);
    if (_items.isEmpty) return const _EmptyState();

    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final item = _items[i];
          return AnimatedSlide(
            offset: _removing.contains(item.reviewId)
                ? const Offset(1, 0) : Offset.zero,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInBack,
            child: AnimatedOpacity(
              opacity: _removing.contains(item.reviewId) ? 0 : 1,
              duration: const Duration(milliseconds: 280),
              child: _ReviewCard(
                item:     item,
                onMerge:  () => _decide(item, 'merge'),
                onReject: () => _decide(item, 'reject'),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Review Card
// ─────────────────────────────────────────────────────────────────────────────
class _ReviewCard extends StatefulWidget {
  final ReviewQueueItem item;
  final VoidCallback    onMerge;
  final VoidCallback    onReject;
  const _ReviewCard(
      {required this.item, required this.onMerge, required this.onReject});
  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item       = widget.item;
    final scorePct   = (item.score * 100).round();
    final scoreColor = item.score >= 0.75
        ? AppColors.error
        : item.score >= 0.5
            ? AppColors.warning
            : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: const Color(0xFFE53935).withOpacity(0.25)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 14, offset: const Offset(0, 3),
        )],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          height: 4,
          decoration: const BoxDecoration(
            color: Color(0xFFE53935),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [

            // Header: status badge + score bubble
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:  const Color(0xFFE53935).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFFE53935).withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                  Icon(Icons.pending_rounded, size: 12,
                      color: Color(0xFFE53935)),
                  SizedBox(width: 5),
                  Text('PENDING REVIEW',
                      style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE53935))),
                ]),
              ),
              const Spacer(),
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color:  scoreColor.withOpacity(0.1),
                  shape:  BoxShape.circle,
                  border: Border.all(
                      color: scoreColor.withOpacity(0.3), width: 2),
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('$scorePct%', style: TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w800, color: scoreColor)),
                  Text('match', style: TextStyle(fontSize: 8,
                      color: scoreColor)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),

            // Complaint
            _sectionLabel('Complaint'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:  const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderColor),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (item.issueDescription != null)
                  Text('"${item.issueDescription}"',
                      style: const TextStyle(fontSize: 13,
                          color: AppColors.textPrimary,
                          fontStyle: FontStyle.italic, height: 1.4)),
                if (item.issueCategory != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.category_outlined, size: 13,
                        color: AppColors.textHint),
                    const SizedBox(width: 5),
                    Text(item.issueCategory!,
                        style: const TextStyle(fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 14),

            // Potential duplicate cluster
            _sectionLabel('Potential duplicate of'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:  const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.hub_outlined, size: 16,
                    color: Colors.orange),
                const SizedBox(width: 10),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (item.clusterTitle != null)
                    Text(item.clusterTitle!,
                        style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (item.clusterComplaintCount != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${item.clusterComplaintCount} existing '
                      'complaint${item.clusterComplaintCount! > 1 ? "s" : ""} '
                      'in this cluster',
                      style: const TextStyle(fontSize: 11,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ])),
              ]),
            ),
            const SizedBox(height: 14),

            // Score breakdown (expandable)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(children: [
                _sectionLabel('Match breakdown'),
                const Spacer(),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20, color: AppColors.textSecondary,
                ),
              ]),
            ),

            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _expanded && item.scoreBreakdown != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _ScoreBreakdownWidget(
                          breakdown: item.scoreBreakdown!),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(
                        value: item.score.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: AppColors.borderColor,
                        valueColor:
                            AlwaysStoppedAnimation(scoreColor),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
            ),

            if (item.reason != null && item.reason!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: AppColors.info),
                  const SizedBox(width: 6),
                  Expanded(child: Text(item.reason!,
                      style: const TextStyle(fontSize: 11,
                          color: AppColors.info, height: 1.4))),
                ]),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(color: AppColors.borderColor, height: 1),
            const SizedBox(height: 14),

            // Action buttons
            Row(children: [
              Expanded(child: ElevatedButton.icon(
                onPressed: widget.onMerge,
                icon:  const Icon(Icons.merge_rounded, size: 16),
                label: const Text('Confirm Duplicate',
                    style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(
                onPressed: widget.onReject,
                icon:  const Icon(Icons.call_split_rounded, size: 16),
                label: const Text('Keep Separate',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(
                      color: AppColors.error.withOpacity(0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  textStyle:
                      const TextStyle(fontWeight: FontWeight.w700),
                ),
              )),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary, letterSpacing: 0.5));
}

// ─────────────────────────────────────────────────────────────────────────────
// Score breakdown bars
// ─────────────────────────────────────────────────────────────────────────────
class _ScoreBreakdownWidget extends StatelessWidget {
  final ScoreBreakdown breakdown;
  const _ScoreBreakdownWidget({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, double)>[
      ('Text similarity', breakdown.textSim),
      ('Location match',  breakdown.geoSim),
      ('Time proximity',  breakdown.timeSim),
      ('Category match',  breakdown.catSim),
      if (breakdown.imgSim != null) ('Image similarity', breakdown.imgSim!),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        children: rows.map((row) {
          final (label, value) = row;
          final pct   = (value * 100).round();
          final color = value >= 0.75
              ? AppColors.success
              : value >= 0.5
                  ? AppColors.warning
                  : AppColors.error;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              SizedBox(
                width: 110,
                child: Text(label, style: const TextStyle(fontSize: 12,
                    color: AppColors.textSecondary)),
              ),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value:           value.clamp(0.0, 1.0),
                  minHeight:       8,
                  backgroundColor: AppColors.borderColor,
                  valueColor:      AlwaysStoppedAnimation(color),
                ),
              )),
              const SizedBox(width: 8),
              SizedBox(
                width: 34,
                child: Text('$pct%',
                    style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700, color: color),
                    textAlign: TextAlign.right),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / Error states
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
              color: AppColors.successLight, shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_outline_rounded,
              size: 52, color: AppColors.success),
        ),
        const SizedBox(height: 20),
        const Text('No pending reviews!',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                color: AppColors.success)),
        const SizedBox(height: 8),
        const Text('All complaints have been processed.\nCheck back later.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13,
                color: AppColors.textSecondary, height: 1.5)),
      ]),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final String       error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.cloud_off_rounded, size: 60,
            color: AppColors.textHint),
        const SizedBox(height: 16),
        const Text('Could not load review queue',
            style: TextStyle(fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Text(error, textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textHint)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon:  const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Retry'),
        ),
      ]),
    ),
  );
}