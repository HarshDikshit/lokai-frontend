import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/issues_provider.dart';
import '../../core/localization.dart';

class LeaderDashboardScreen extends ConsumerWidget {
  const LeaderDashboardScreen({super.key});

  // ─── Pie colors ─────────────────────────────────────────────────────────
  static const _pieColors = [
    AppColors.primary, AppColors.accent, AppColors.success,
    AppColors.warning, AppColors.error, AppColors.statusEscalated,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth     = ref.watch(authProvider);
    final dashAsync = ref.watch(leaderDashboardProvider);
    final screenW  = MediaQuery.of(context).size.width;
    final isTablet = screenW >= 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.translate('leader_dashboard')),
        actions: [
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (i) {
          if (i == 1) context.go('/leader/issues');
          if (i == 2) context.go('/feed'); 
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard_outlined),  label: context.translate('status_all')),
          NavigationDestination(icon: const Icon(Icons.list_alt_outlined),    label: context.translate('assigned_issues')),
          NavigationDestination(icon: const Icon(Icons.campaign_rounded),    label: context.translate('feed_title')),
        ],
      ),
      body: dashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(leaderDashboardProvider),
        ),
        data: (data) {
          final metrics    = (data['metrics']              as Map<String, dynamic>?) ?? {};
          final categories = (data['category_distribution'] as List?)               ?? [];
          final monthly    = (data['monthly_resolution']   as List?)                ?? [];

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(leaderDashboardProvider),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? screenW * 0.06 : 16,
                vertical: 20,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Welcome card ─────────────────────────────────
                      _WelcomeCard(
                        name: auth.userName ?? 'Leader',
                        failedCases: metrics['failed_cases'] as int? ?? 0,
                      ),
                      const SizedBox(height: 24),

                      // ── Performance overview ─────────────────────────
                      _SectionLabel(label: context.translate('performance_overview')),
                      const SizedBox(height: 12),

                      _MetricsGrid(
                        metrics: metrics,
                        isTablet: isTablet,
                        screenW: screenW,
                      ),
                      const SizedBox(height: 24),

                      // ── Resolution rate card ─────────────────────────
                      _ResolutionRateCard(metrics: metrics),
                      const SizedBox(height: 24),

                      // ── Category pie ─────────────────────────────────
                      if (categories.isNotEmpty) ...[
                        _SectionLabel(label: context.translate('issue_categories')),
                        const SizedBox(height: 12),
                        _CategoryCard(
                          categories: categories,
                          colors: _pieColors,
                          isTablet: isTablet,
                        ),
                        const SizedBox(height: 24),
                      ],

                      // ── Monthly bar chart ────────────────────────────
                      if (monthly.isNotEmpty) ...[
                        _SectionLabel(label: context.translate('monthly_resolution_trend')),
                        const SizedBox(height: 12),
                        _MonthlyChart(monthly: monthly),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Welcome card ─────────────────────────────────────────────────────────────
class _WelcomeCard extends StatelessWidget {
  final String name;
  final int failedCases;
  const _WelcomeCard({required this.name, required this.failedCases});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: AppColors.primary.withOpacity(0.3),
          blurRadius: 12, offset: const Offset(0, 4),
        )],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Avatar
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.shield_outlined, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),

        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.translate('welcome_leader').replaceAll('{name}', name),
              style: const TextStyle(color: Colors.white, fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(context.translate('local_leader'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ])),

        // Failed badge
        if (failedCases > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.error,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.warning_rounded, color: Colors.white, size: 13),
              const SizedBox(width: 4),
              Text('$failedCases ${context.translate('failed')}',
                  style: const TextStyle(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 3, height: 18,
        decoration: BoxDecoration(color: AppColors.primary,
            borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary)),
  ]);
}

// ─── Metrics grid — RESPONSIVE, no overflow ───────────────────────────────────
class _MetricsGrid extends StatelessWidget {
  final Map<String, dynamic> metrics;
  final bool isTablet;
  final double screenW;
  const _MetricsGrid({required this.metrics, required this.isTablet,
      required this.screenW});

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetricDef(context.translate('total_issues'),    metrics['total_issues']    ?? 0, Icons.list_alt_rounded,           AppColors.primary),
      _MetricDef(context.translate('metrics_active'),          metrics['active_problems'] ?? 0, Icons.radio_button_checked,       AppColors.info),
      _MetricDef(context.translate('metrics_completed'), metrics['completed_tasks'] ?? 0, Icons.check_circle_outline,       AppColors.success),
      _MetricDef(context.translate('metrics_pending'),   metrics['pending_tasks']   ?? 0, Icons.pending_actions_rounded,    AppColors.warning),
      _MetricDef(context.translate('metrics_escalated'),       metrics['escalated_cases'] ?? 0, Icons.arrow_upward_rounded,       AppColors.statusEscalated),
      _MetricDef(context.translate('metrics_failed'),    metrics['failed_cases']    ?? 0, Icons.cancel_outlined,            AppColors.error),
    ];

    // On tablet: 3-col, on phone: 2-col
    final cols = isTablet ? 3 : 2;

    // Calculate tile width so we can set a fixed height that won't overflow
    final hPad    = isTablet ? screenW * 0.12 : 32.0; // total horizontal padding
    final spacing = 12.0;
    final tileW   = (screenW - hPad - spacing * (cols - 1)) / cols;
    // Height: icon row (32) + spacing (10) + value (36) + spacing (4) + label (16) + vpad (24)
    final tileH   = tileW * 0.72;                      // aspect ratio approach
    // Cap min/max so it looks good on all sizes
    final clampedH = tileH.clamp(88.0, 140.0);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:   cols,
        mainAxisSpacing:  12,
        crossAxisSpacing: 12,
        mainAxisExtent:   clampedH,   // ← fixed pixel height, NO childAspectRatio
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _MetricTile(def: items[i]),
    );
  }
}

class _MetricDef {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const _MetricDef(this.label, this.value, this.icon, this.color);
}

class _MetricTile extends StatelessWidget {
  final _MetricDef def;
  const _MetricTile({required this.def});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 6, offset: const Offset(0, 2),
        )],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Icon box
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: def.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(def.icon, color: def.color, size: 18),
          ),
          // Value + label stacked
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(                          // ← shrinks number if it's wide
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                def.value.toString(),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                    color: def.color),
              ),
            ),
            const SizedBox(height: 2),
            Text(def.label,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ],
      ),
    );
  }
}

// ─── Resolution rate card ─────────────────────────────────────────────────────
class _ResolutionRateCard extends StatelessWidget {
  final Map<String, dynamic> metrics;
  const _ResolutionRateCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final total    = (metrics['total_issues']    as int? ?? 0);
    final resolved = (metrics['completed_tasks'] as int? ?? 0);
    final rate     = total > 0 ? resolved / total : 0.0;
    final pct      = (rate * 100).round();

    Color barColor;
    String note;
    if (rate >= 0.75) { barColor = AppColors.success;          note = context.translate('excellent_perf'); }
    else if (rate >= 0.5) { barColor = AppColors.warning;      note = context.translate('good_keep_going');   }
    else                  { barColor = AppColors.statusEscalated; note = context.translate('needs_improvement'); }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.analytics_outlined, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(context.translate('resolution_rate'), style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const Spacer(),
          Text('$pct%', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
              color: barColor)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: rate.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: AppColors.borderColor,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: 6),
        Text(note, style: TextStyle(fontSize: 11, color: barColor,
            fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

// ─── Category pie card ────────────────────────────────────────────────────────
class _CategoryCard extends StatelessWidget {
  final List categories;
  final List<Color> colors;
  final bool isTablet;
  const _CategoryCard({required this.categories, required this.colors,
      required this.isTablet});

  @override
  Widget build(BuildContext context) {
    final total = categories.fold<int>(0, (s, d) => s + (d['count'] as int));
    final sections = List.generate(categories.length, (i) {
      final pct = total > 0 ? (categories[i]['count'] as int) / total * 100 : 0.0;
      return PieChartSectionData(
        value: pct.toDouble(),
        color: colors[i % colors.length],
        title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            color: Colors.white),
        radius: 58,
      );
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: isTablet
          // Tablet: chart + legend side by side
          ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox(width: 180, height: 180,
                child: PieChart(PieChartData(
                  sections: sections,
                  centerSpaceRadius: 44,
                  sectionsSpace: 2,
                ))),
              const SizedBox(width: 24),
              Expanded(child: _Legend(categories: categories, colors: colors)),
            ])
          // Phone: chart above, legend below
          : Column(children: [
              SizedBox(height: 180,
                child: PieChart(PieChartData(
                  sections: sections,
                  centerSpaceRadius: 44,
                  sectionsSpace: 2,
                ))),
              const SizedBox(height: 14),
              _Legend(categories: categories, colors: colors),
            ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final List categories;
  final List<Color> colors;
  const _Legend({required this.categories, required this.colors});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12, runSpacing: 8,
    children: List.generate(categories.length, (i) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(
            color: colors[i % colors.length], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(categories[i]['category'] ?? '',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    )),
  );
}

// ─── Monthly bar chart ────────────────────────────────────────────────────────
class _MonthlyChart extends StatelessWidget {
  final List monthly;
  const _MonthlyChart({required this.monthly});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: SizedBox(
        height: 180,
        child: BarChart(BarChartData(
          barGroups: List.generate(monthly.length, (i) => BarChartGroupData(
            x: i,
            barRods: [BarChartRodData(
              toY: (monthly[i]['resolved'] as num).toDouble(),
              color: AppColors.primary,
              width: 18,
              borderRadius: BorderRadius.circular(5),
              backDrawRodData: BackgroundBarChartRodData(
                show: true, toY: 10,
                color: AppColors.borderColor,
              ),
            )],
          )),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 22,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= monthly.length) return const SizedBox.shrink();
                final month = monthly[idx]['month']?.toString() ?? '';
                return Text(month.length >= 3 ? month.substring(0, 3) : month,
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary));
              },
            )),
            leftTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: AppColors.borderColor, strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                '${rod.toY.toInt()} resolved',
                const TextStyle(color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        )),
      ),
    );
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.cloud_off_rounded, size: 60, color: AppColors.textHint),
        const SizedBox(height: 16),
        Text(message, style: const TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(context.translate('retry')),
        ),
      ]),
    ),
  );
}
