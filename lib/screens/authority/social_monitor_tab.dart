// screens/authority/social_monitor_tab.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

class SocialMonitorTabBody extends StatefulWidget {
  final List<Map<String, dynamic>> availableLeaders;
  final Future<void> Function(SocialPost post) onAssignRequest;

  const SocialMonitorTabBody({
    super.key,
    required this.availableLeaders,
    required this.onAssignRequest,
  });

  @override
  State<SocialMonitorTabBody> createState() => _SocialMonitorTabBodyState();
}

class _SocialMonitorTabBodyState extends State<SocialMonitorTabBody> {
  SocialMonitorResponse? _data;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

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
    // Add artificial delay so the user sees a "loading" state as requested, 
    // even if returning cached data from ApiService.
    await Future.delayed(const Duration(milliseconds: 1500));
    
    try {
      final raw = await ApiService.instance.getSocialMonitor();
      if (!mounted) return;
      setState(() {
        _data = SocialMonitorResponse.fromJson(raw);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorState(error: _error!, onRetry: _fetch);
    if (_data == null || _data!.posts.isEmpty) return const _EmptyState();

    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppColors.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _SocialOverviewBar(
              totalPosts: _data!.totalPosts,
              trending: _data!.trendingIssues,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => SocialPostCard(
                  post: _data!.posts[i],
                  onAssign: () => widget.onAssignRequest(_data!.posts[i]),
                ),
                childCount: _data!.posts.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialOverviewBar extends StatelessWidget {
  final int totalPosts;
  final Map<String, int> trending;

  const _SocialOverviewBar({required this.totalPosts, required this.trending});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.analytics_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Citizen Pulse',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
                    ),
                    Text(
                      'AI-detected social media insights',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              _StatBadge(label: 'Total Posts', value: '$totalPosts', color: AppColors.primary),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'TRENDING CONCERNS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textHint, letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: trending.entries.map((e) {
                return Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderColor),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${e.value}',
                          style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBadge({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 18)),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.white70, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class SocialPostCard extends StatelessWidget {
  final SocialPost post;
  final VoidCallback onAssign;

  const SocialPostCard({
    super.key,
    required this.post,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final sentimentColor = _getSentimentColor(post.sentiment);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Container(height: 4, color: sentimentColor),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          post.title,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: sentimentColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sentimentColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_getSentimentIcon(post.sentiment), size: 12, color: sentimentColor),
                            const SizedBox(width: 4),
                            Text(
                              post.sentiment,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: sentimentColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    post.summary,
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.borderColor),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.tag_rounded, size: 14, color: AppColors.textHint),
                              const SizedBox(width: 6),
                              Text(
                                post.issueCategory,
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: onAssign,
                          icon: const Icon(Icons.send_to_mobile_rounded, size: 16),
                          label: const Text('Assign Leader', style: TextStyle(fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
      ),
    );
  }

  Color _getSentimentColor(String sentiment) {
    switch (sentiment.toUpperCase()) {
      case 'POSITIVE':
        return AppColors.success;
      case 'NEGATIVE':
        return AppColors.error;
      default:
        return AppColors.textHint;
    }
  }

  IconData _getSentimentIcon(String sentiment) {
    switch (sentiment.toUpperCase()) {
      case 'POSITIVE':
        return Icons.sentiment_very_satisfied_rounded;
      case 'NEGATIVE':
        return Icons.sentiment_very_dissatisfied_rounded;
      default:
        return Icons.sentiment_neutral_rounded;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(color: AppColors.successLight, shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_outline_rounded, size: 52, color: AppColors.success),
          ),
          const SizedBox(height: 20),
          const Text('No social reports!',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.success)),
          const SizedBox(height: 8),
          const Text('Everything seems quiet on social media.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ]),
      );
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.cloud_off_rounded, size: 60, color: AppColors.textHint),
            const SizedBox(height: 16),
            const Text('Could not load social monitor',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ]),
        ),
      );
}

