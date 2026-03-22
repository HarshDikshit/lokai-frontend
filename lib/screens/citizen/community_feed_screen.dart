import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/issues_provider.dart';
import '../../services/api_service.dart';
import 'package:go_router/go_router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tag definitions
// ─────────────────────────────────────────────────────────────────────────────
const _tags = ['Update', 'Alert', 'Achievement', 'Announcement', 'Notice'];

Color _tagColor(String? tag) {
  switch (tag) {
    case 'Alert':        return const Color(0xFFD32F2F);
    case 'Achievement':  return const Color(0xFF2E7D32);
    case 'Announcement': return const Color(0xFF6A1B9A);
    case 'Notice':       return const Color(0xFF0277BD);
    default:             return AppColors.primary;
  }
}

IconData _tagIcon(String? tag) {
  switch (tag) {
    case 'Alert':        return Icons.warning_amber_rounded;
    case 'Achievement':  return Icons.emoji_events_rounded;
    case 'Announcement': return Icons.campaign_rounded;
    case 'Notice':       return Icons.info_rounded;
    default:             return Icons.update_rounded;
  }
}

String _timeAgo(String? iso) {
  if (iso == null) return '';
  final dt   = DateTime.tryParse(iso);
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inMinutes < 1)  return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24)   return '${diff.inHours}h ago';
  if (diff.inDays < 7)     return '${diff.inDays}d ago';
  return DateFormat('MMM d').format(dt.toLocal());
}

// ─────────────────────────────────────────────────────────────────────────────
// Community Feed Screen
// ─────────────────────────────────────────────────────────────────────────────
class CommunityFeedScreen extends ConsumerStatefulWidget {
  const CommunityFeedScreen({super.key});
  @override
  ConsumerState<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends ConsumerState<CommunityFeedScreen>
    with TickerProviderStateMixin {
  final _scrollCtrl = ScrollController();
  late AnimationController _fabAnim;

  @override
  void initState() {
    super.initState();
    _fabAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fabAnim.forward();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _fabAnim.dispose();
    super.dispose();
  }

  void _openCreatePost() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePostSheet(
        onPosted: (post) => ref.read(feedProvider.notifier).prependPost(post),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth     = ref.watch(authProvider);
    final feedAsync = ref.watch(feedProvider);
    final isLeader = auth.role == 'leader';

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      bottomNavigationBar: isLeader
          ? NavigationBar(
              selectedIndex: 2,
              onDestinationSelected: (i) {
                if (i == 0) context.go('/leader');
                if (i == 1) context.go('/leader/issues');
                // i == 2 is feed — already here
              },
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
                NavigationDestination(
                    icon: Icon(Icons.list_alt_outlined), label: 'Issues'),
                NavigationDestination(
                    icon: Icon(Icons.campaign_rounded), label: 'Feed'),
              ],
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.read(feedProvider.notifier).fetch(),
        color: AppColors.primary,
        child: CustomScrollView(
          controller: _scrollCtrl,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Sticky app bar ──────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              floating: true,
              backgroundColor: AppColors.primary,
              expandedHeight: 110,
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            if (!isLeader)
                              GestureDetector(
                                onTap: () {
                                    if (context.canPop()) {
                                      context.pop();
                                    } else {
                                      context.go('/citizen');
                                    }
                                  },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                                      color: Colors.white, size: 16),
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.campaign_rounded,
                                  color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 10),
                            const Text('Community Feed',
                                style: TextStyle(color: Colors.white,
                                    fontSize: 20, fontWeight: FontWeight.w800)),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded,
                                  color: Colors.white70, size: 20),
                              onPressed: () => ref.read(feedProvider.notifier).fetch(),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                            isLeader
                                ? 'Share updates with your community'
                                : 'Stay informed by your local leaders',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Feed body ───────────────────────────────────────────────────
            feedAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                child: _ErrorState(onRetry: () => ref.read(feedProvider.notifier).fetch()),
              ),
              data: (posts) {
                if (posts.isEmpty) {
                  return SliverFillRemaining(
                    child: _EmptyFeed(isLeader: isLeader, onPost: isLeader ? _openCreatePost : null),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _PostCard(
                        post: posts[i],
                        currentUserId: auth.userId ?? '',
                        currentRole:   auth.role ?? 'citizen',
                        onUpdated: (p) =>
                            ref.read(feedProvider.notifier).updatePost(p),
                      ),
                      childCount: posts.length,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: isLeader
          ? ScaleTransition(
              scale: CurvedAnimation(parent: _fabAnim, curve: Curves.elasticOut),
              child: FloatingActionButton.extended(
                onPressed: _openCreatePost,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Post Update',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                elevation: 4,
              ),
            )
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Post Card
// ─────────────────────────────────────────────────────────────────────────────
class _PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final String currentUserId;
  final String currentRole;
  final ValueChanged<Map<String, dynamic>> onUpdated;

  const _PostCard({
    required this.post,
    required this.currentUserId,
    required this.currentRole,
    required this.onUpdated,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _post;
  bool _liked       = false;
  int  _likeCount   = 0;
  int  _shareCount  = 0;
  bool _showComments = false;
  bool _likeAnimating = false;
  late AnimationController _likeCtrl;

  @override
  void initState() {
    super.initState();
    _post       = Map.from(widget.post);
    _liked      = _post['liked'] == true;
    _likeCount  = _post['like_count'] ?? 0;
    _shareCount = _post['share_count'] ?? 0;
    _likeCtrl   = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _likeCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    HapticFeedback.lightImpact();
    final wasLiked = _liked;
    setState(() {
      _liked     = !_liked;
      _likeCount += _liked ? 1 : -1;
      _likeAnimating = true;
    });
    _likeCtrl.forward(from: 0).then((_) {
      if (mounted) setState(() => _likeAnimating = false);
    });
    try {
      await ApiService.instance.togglePostLike(_post['id']);
    } catch (_) {
      if (mounted) setState(() { _liked = wasLiked; _likeCount += wasLiked ? 1 : -1; });
    }
  }

  Future<void> _share() async {
    HapticFeedback.mediumImpact();
    setState(() => _shareCount++);
    try {
      await ApiService.instance.sharePost(_post['id']);
    } catch (_) {
      if (mounted) setState(() => _shareCount--);
    }
  }

  void _openComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(
        post: _post,
        currentUserId: widget.currentUserId,
        currentRole: widget.currentRole,
        onPostUpdated: (updated) {
          setState(() => _post = updated);
          widget.onUpdated(updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tag         = _post['tag'] as String? ?? 'Update';
    final tColor      = _tagColor(tag);
    final leaderName  = _post['leader_name'] as String? ?? 'Leader';
    final content     = _post['content'] as String? ?? '';
    final imageUrl    = _post['image_url'] as String?;
    final commentCount = (_post['comment_count'] as int? ?? 0);
    final createdAt   = _post['created_at'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Colored tag accent ──────────────────────────────────────────────
        Container(
          height: 4,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [tColor, tColor.withOpacity(0.5)]),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Header: avatar + name + tag + time ──────────────────────────
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Avatar
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [tColor.withOpacity(0.8), tColor],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    leaderName.isNotEmpty ? leaderName[0].toUpperCase() : 'L',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(leaderName,
                      style: const TextStyle(fontWeight: FontWeight.w700,
                          fontSize: 14, color: AppColors.textPrimary))),
                  // Tag pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: tColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: tColor.withOpacity(0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_tagIcon(tag), size: 11, color: tColor),
                      const SizedBox(width: 4),
                      Text(tag, style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w700, color: tColor)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.shield_outlined, size: 11,
                      color: AppColors.textHint),
                  const SizedBox(width: 3),
                  const Text('Local Leader',
                      style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                  const SizedBox(width: 8),
                  const Icon(Icons.schedule_rounded, size: 11,
                      color: AppColors.textHint),
                  const SizedBox(width: 3),
                  Text(_timeAgo(createdAt),
                      style: const TextStyle(fontSize: 11,
                          color: AppColors.textHint)),
                ]),
              ])),
            ]),
            const SizedBox(height: 14),

            // ── Content ─────────────────────────────────────────────────────
            Text(content, style: const TextStyle(fontSize: 14.5,
                color: AppColors.textPrimary, height: 1.55)),

            // ── Image ───────────────────────────────────────────────────────
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(imageUrl, width: double.infinity,
                    height: 200, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ],
            const SizedBox(height: 14),

            // ── Stats row ───────────────────────────────────────────────────
            Row(children: [
              if (_likeCount > 0) ...[
                const Icon(Icons.favorite_rounded, size: 13, color: Color(0xFFE53935)),
                const SizedBox(width: 4),
                Text('$_likeCount', style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(width: 12),
              ],
              if (commentCount > 0) ...[
                const Icon(Icons.chat_bubble_outline_rounded, size: 13,
                    color: AppColors.textHint),
                const SizedBox(width: 4),
                Text('$commentCount ${commentCount == 1 ? "comment" : "comments"}',
                    style: const TextStyle(fontSize: 12,
                        color: AppColors.textSecondary)),
              ],
              if (_shareCount > 0) ...[
                const SizedBox(width: 12),
                const Icon(Icons.share_rounded, size: 13,
                    color: AppColors.textHint),
                const SizedBox(width: 4),
                Text('$_shareCount', style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
              ],
            ]),

            const Divider(height: 20, color: AppColors.borderColor),

            // ── Action buttons ──────────────────────────────────────────────
            Row(children: [
              // Like
              Expanded(child: _ActionBtn(
                icon: _liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: 'Like',
                color: _liked ? const Color(0xFFE53935) : AppColors.textSecondary,
                onTap: _toggleLike,
                animating: _likeAnimating,
              )),
              // Comment
              Expanded(child: _ActionBtn(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Comment',
                color: AppColors.textSecondary,
                onTap: _openComments,
              )),
              // Share
              Expanded(child: _ActionBtn(
                icon: Icons.share_rounded,
                label: 'Share',
                color: AppColors.textSecondary,
                onTap: _share,
              )),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
      ]),
    );
  }
}

// ─── Action button ────────────────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool animating;
  const _ActionBtn({required this.icon, required this.label,
      required this.color, required this.onTap, this.animating = false});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedScale(
          scale: animating ? 1.4 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.elasticOut,
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w600, color: color)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Comments Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _CommentsSheet extends StatefulWidget {
  final Map<String, dynamic> post;
  final String currentUserId;
  final String currentRole;
  final ValueChanged<Map<String, dynamic>> onPostUpdated;

  const _CommentsSheet({
    required this.post,
    required this.currentUserId,
    required this.currentRole,
    required this.onPostUpdated,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  late Map<String, dynamic> _post;
  final _ctrl     = TextEditingController();
  final _focusNode = FocusNode();
  String? _replyToId;
  String? _replyToName;
  bool   _sending = false;

  @override
  void initState() {
    super.initState();
    _post = Map.from(widget.post);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startReply(String commentId, String authorName) {
    setState(() { _replyToId = commentId; _replyToName = authorName; });
    _ctrl.text = '';
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() { _replyToId = null; _replyToName = null; });
    _ctrl.clear();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final updated = await ApiService.instance.addComment(
        _post['id'], text, parentId: _replyToId,
      );
      setState(() {
        _post = Map<String, dynamic>.from(updated);
        _replyToId = null;
        _replyToName = null;
      });
      _ctrl.clear();
      widget.onPostUpdated(_post);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'),
              backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _likeComment(String commentId) async {
    try {
      final comments = List<Map<String, dynamic>>.from(
          (_post['comments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
      for (final c in comments) {
        if (c['id'] == commentId) {
          final wasLiked = c['liked'] == true;
          setState(() {
            c['liked']      = !wasLiked;
            c['like_count'] = (c['like_count'] ?? 0) + (wasLiked ? -1 : 1);
          });
          break;
        }
      }
      await ApiService.instance.toggleCommentLike(_post['id'], commentId);
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _comments =>
      List<Map<String, dynamic>>.from(
          (_post['comments'] as List? ?? []).map((e) =>
              Map<String, dynamic>.from(e)));

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        // Handle
        const SizedBox(height: 10),
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 14),

        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Icon(Icons.chat_bubble_rounded,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text('Comments (${_comments.length})',
                style: const TextStyle(fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
          ]),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: AppColors.borderColor),

        // Comments list
        Expanded(child: _comments.isEmpty
            ? Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.chat_bubble_outline_rounded,
                      size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text('No comments yet',
                      style: TextStyle(color: Colors.grey[500],
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('Be the first to comment!',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                itemCount: _comments.length,
                itemBuilder: (_, i) => _CommentTile(
                  comment: _comments[i],
                  currentUserId: widget.currentUserId,
                  onReply: _startReply,
                  onLike: _likeComment,
                ),
              )),

        // Reply indicator
        if (_replyToName != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.primary.withOpacity(0.06),
            child: Row(children: [
              const Icon(Icons.reply_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('Replying to $_replyToName',
                  style: const TextStyle(fontSize: 12,
                      color: AppColors.primary, fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                onTap: _cancelReply,
                child: const Icon(Icons.close, size: 16,
                    color: AppColors.textSecondary),
              ),
            ]),
          ),

        // Input bar
        Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + inset),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10, offset: const Offset(0, -2),
            )],
          ),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.person, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _replyToName != null
                    ? 'Reply to $_replyToName…'
                    : 'Write a comment…',
                hintStyle: const TextStyle(color: AppColors.textHint,
                    fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: AppColors.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                fillColor: AppColors.inputFill,
                filled: true,
              ),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : _send,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _sending
                      ? AppColors.primary.withOpacity(0.5)
                      : AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 18),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Comment tile (supports sub-comments) ─────────────────────────────────────
class _CommentTile extends StatelessWidget {
  final Map<String, dynamic> comment;
  final String currentUserId;
  final void Function(String id, String name) onReply;
  final void Function(String id) onLike;
  const _CommentTile({
    required this.comment, required this.currentUserId,
    required this.onReply, required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final name      = comment['author_name'] as String? ?? 'Citizen';
    final role      = comment['author_role'] as String? ?? 'citizen';
    final text      = comment['text'] as String? ?? '';
    final liked     = comment['liked'] == true;
    final likeCount = comment['like_count'] as int? ?? 0;
    final createdAt = comment['created_at'] as String?;
    final commentId = comment['id'] as String? ?? '';
    final replies   = List<Map<String, dynamic>>.from(
        (comment['replies'] as List? ?? []).map((e) =>
            Map<String, dynamic>.from(e)));
    final isLeader  = role == 'leader';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Avatar
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: isLeader
                ? AppColors.primary.withOpacity(0.15)
                : AppColors.inputFill,
            shape: BoxShape.circle,
          ),
          child: Center(child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'U',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                color: isLeader ? AppColors.primary : AppColors.textSecondary),
          )),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Comment bubble
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Text(name, style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if (isLeader) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Leader',
                        style: TextStyle(fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ),
                ],
              ]),
              const SizedBox(height: 4),
              Text(text, style: const TextStyle(fontSize: 13,
                  color: AppColors.textPrimary, height: 1.4)),
            ]),
          ),

          // Meta row
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 5, 0, 0),
            child: Row(children: [
              Text(_timeAgo(createdAt),
                  style: const TextStyle(fontSize: 11,
                      color: AppColors.textHint)),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: () => onLike(commentId),
                child: Row(children: [
                  Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      size: 13,
                      color: liked ? const Color(0xFFE53935) : AppColors.textHint),
                  if (likeCount > 0) ...[
                    const SizedBox(width: 3),
                    Text('$likeCount', style: TextStyle(
                        fontSize: 11,
                        color: liked ? const Color(0xFFE53935) : AppColors.textHint,
                        fontWeight: FontWeight.w600)),
                  ],
                ]),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: () => onReply(commentId, name),
                child: const Text('Reply',
                    style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
            ]),
          ),

          // Sub-comments
          if (replies.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...replies.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Sub indent line
                Container(
                  width: 2, height: 30, margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppColors.borderColor,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                // Sub avatar
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.inputFill,
                    shape: BoxShape.circle,
                  ),
                  child: Center(child: Text(
                    (r['author_name'] as String? ?? 'U').isNotEmpty
                        ? (r['author_name'] as String)[0].toUpperCase() : 'U',
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary),
                  )),
                ),
                const SizedBox(width: 8),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7FA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(r['author_name'] as String? ?? 'Citizen',
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(r['text'] as String? ?? '',
                          style: const TextStyle(fontSize: 12,
                              color: AppColors.textPrimary, height: 1.4)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 0, 0),
                    child: Text(_timeAgo(r['created_at'] as String?),
                        style: const TextStyle(fontSize: 10,
                            color: AppColors.textHint)),
                  ),
                ])),
              ]),
            )),
          ],
        ])),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Post Bottom Sheet (leader only)
// ─────────────────────────────────────────────────────────────────────────────
class _CreatePostSheet extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>> onPosted;
  const _CreatePostSheet({required this.onPosted});

  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _ctrl    = TextEditingController();
  String _tag    = 'Update';
  bool   _posting = false;

  Future<void> _post() async {
    final text = _ctrl.text.trim();
    if (text.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post must be at least 5 characters')));
      return;
    }
    setState(() => _posting = true);
    try {
      final post = await ApiService.instance.createPost(
          content: text, tag: _tag);
      if (!mounted) return;
      widget.onPosted(Map<String, dynamic>.from(post));
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post published! ✓'),
            backgroundColor: AppColors.success));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'),
            backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + inset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 10),
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 18),

        // Header
        Row(children: [
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.edit_rounded,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('Create Community Post',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
        ]),
        const SizedBox(height: 18),

        // Tag selector
        const Text('Post Type',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: _tags.map((t) {
            final sel = _tag == t;
            final tc  = _tagColor(t);
            return GestureDetector(
              onTap: () => setState(() => _tag = t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? tc : AppColors.inputFill,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel ? tc : AppColors.borderColor),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_tagIcon(t), size: 13,
                      color: sel ? Colors.white : tc),
                  const SizedBox(width: 5),
                  Text(t, style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : AppColors.textSecondary)),
                ]),
              ),
            );
          }).toList()),
        ),
        const SizedBox(height: 16),

        // Content field
        TextField(
          controller: _ctrl,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Share an update, alert, or announcement with your community…',
            hintStyle: const TextStyle(fontSize: 13,
                color: AppColors.textHint),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: AppColors.primary, width: 1.5),
            ),
            fillColor: AppColors.inputFill,
            filled: true,
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _posting ? null : _post,
            icon: _posting
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(_posting ? 'Publishing…' : 'Publish Post'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _tagColor(_tag),
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Empty / Error states ─────────────────────────────────────────────────────
class _EmptyFeed extends StatelessWidget {
  final bool isLeader;
  final VoidCallback? onPost;
  const _EmptyFeed({required this.isLeader, this.onPost});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.campaign_rounded,
              size: 52, color: AppColors.primary),
        ),
        const SizedBox(height: 20),
        Text(isLeader ? 'Start the conversation!' : 'No posts yet',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(
          isLeader
              ? 'Share updates, alerts, or announcements with your community.'
              : 'Your local leaders haven\'t posted yet. Check back soon.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary,
              height: 1.5),
        ),
        if (isLeader && onPost != null) ...[
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onPost,
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: const Text('Create First Post'),
          ),
        ],
      ]),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.cloud_off_rounded, size: 60, color: AppColors.textHint),
      const SizedBox(height: 16),
      const Text('Could not load feed',
          style: TextStyle(color: AppColors.textSecondary,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Retry'),
      ),
    ]),
  );
}