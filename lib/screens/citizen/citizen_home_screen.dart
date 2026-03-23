import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/issues_provider.dart';
import '../../core/localization.dart';

class CitizenHomeScreen extends ConsumerWidget {
  const CitizenHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth      = ref.watch(authProvider);
    final dashboard = ref.watch(citizenDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.translate('app_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: context.translate('refresh'),
            onPressed: () => ref.refresh(citizenDashboardProvider),
          ),
          IconButton(
            onPressed: () {
              final currentLocale = ref.read(localeProvider);
              ref.read(localeProvider.notifier).setLocale(currentLocale.languageCode == 'en' 
                      ? const Locale('hi') 
                      : const Locale('en'));
            },
            icon: const Icon(Icons.language),
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: context.translate('logout'),
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              context.go('/');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Welcome banner ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.translate('hello_user').replaceAll('{name}', auth.userName ?? "Citizen"),
                      style: const TextStyle(color: Colors.white,
                          fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(context.translate('voice_shapes_city'),
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                )),
                const Icon(Icons.location_city, color: Colors.white38, size: 48),
              ]),
            ),
            const SizedBox(height: 24),

            // ── Dashboard stats ──────────────────────────────────────────────
            dashboard.when(
              data: (data) => GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                   _StatCard(context.translate('total_issues'),    data['total_issues']        ?? 0, Icons.list_alt,            AppColors.primary),
                  _StatCard(context.translate('open'),            data['open_issues']         ?? 0, Icons.radio_button_checked, AppColors.info),
                  _StatCard(context.translate('pending_verify'),  data['pending_verification'] ?? 0, Icons.pending_actions,     AppColors.warning),
                  _StatCard(context.translate('resolved'),        data['resolved_issues']     ?? 0, Icons.check_circle_outline, AppColors.success),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error:   (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // ── Quick actions ────────────────────────────────────────────────
            Text(context.translate('quick_actions'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),

            // Row 1: Report + My Issues
            Row(children: [
              Expanded(child: _ActionCard(
                icon: Icons.add_circle_outline,
                label: context.translate('report_issue'),
                color: AppColors.primary,
                onTap: () => context.push('/citizen/submit'),
              )),
              const SizedBox(width: 12),
              Expanded(child: _ActionCard(
                icon: Icons.track_changes,
                label: context.translate('my_issues'),
                color: AppColors.accent,
                onTap: () => context.push('/citizen/issues'),
              )),
            ]),
            const SizedBox(height: 12),

            // Row 2: Community Feed (full width)
            _ActionCard(
              icon: Icons.campaign_rounded,
              label: context.translate('community_feed'),
              color: const Color(0xFF6A1B9A),
              onTap: () => context.push('/feed'),
              fullWidth: true,
            ),
            const SizedBox(height: 24),

            // ── How it works ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.info.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.lightbulb_outline, color: AppColors.info, size: 18),
                    const SizedBox(width: 8),
                    Text(context.translate('how_it_works'),
                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.info)),
                  ]),
                  const SizedBox(height: 12),
                  _tip('1', context.translate('tip1')),
                  _tip('2', context.translate('tip2')),
                  _tip('3', context.translate('tip3')),
                  _tip('4', context.translate('tip4')),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed('chatbot'),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.auto_awesome, color: Colors.white),
        label: Text(context.translate('chatbot_title'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _tip(String num, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
            color: AppColors.info, borderRadius: BorderRadius.circular(10)),
        child: Center(child: Text(num,
            style: const TextStyle(color: Colors.white,
                fontSize: 11, fontWeight: FontWeight.w700))),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
    ]),
  );
}

// ─── Stat card ────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final int    value;
  final IconData icon;
  final Color  color;
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.borderColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(icon, color: color, size: 22),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value.toString(),
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ]),
      ],
    ),
  );
}

// ─── Action card ──────────────────────────────────────────────────────────────
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;
  final bool     fullWidth;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: fullWidth ? double.infinity : null,
      padding: EdgeInsets.symmetric(
          vertical: fullWidth ? 16 : 20, horizontal: 20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: fullWidth
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(color: color,
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_rounded, color: color.withOpacity(0.6), size: 16),
            ])
          : Column(children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center,
                  style: TextStyle(color: color,
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
    ),
  );
}
