import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/issues_provider.dart';
import '../../widgets/common_widgets.dart';

class LeaderDashboardScreen extends ConsumerWidget {
  const LeaderDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final dashAsync = ref.watch(leaderDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leader Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              context.go('/');
            },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), label: 'Issues'),
          NavigationDestination(icon: Icon(Icons.task_outlined), label: 'Tasks'),
        ],
        selectedIndex: 0,
        onDestinationSelected: (i) {
          if (i == 1) context.go('/leader/issues');
          if (i == 2) context.go('/leader/tasks');
        },
      ),
      body: dashAsync.when(
        data: (data) {
          final metrics = data['metrics'] as Map<String, dynamic>? ?? {};
          final categories = data['category_distribution'] as List? ?? [];
          final monthly = data['monthly_resolution'] as List? ?? [];

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(leaderDashboardProvider),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome card
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
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, ${auth.userName}!',
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              const Text('Local Leader', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                        if ((metrics['failed_cases'] as int? ?? 0) > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning, color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '${metrics['failed_cases']} Failed',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text('Performance Overview',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 12),

                  // Metrics grid
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.4,
                    children: [
                      MetricCard(
                        label: 'Total Issues',
                        value: metrics['total_issues'] ?? 0,
                        icon: Icons.list_alt,
                        color: AppColors.primary,
                      ),
                      MetricCard(
                        label: 'Active Problems',
                        value: metrics['active_problems'] ?? 0,
                        icon: Icons.radio_button_checked,
                        color: AppColors.info,
                      ),
                      MetricCard(
                        label: 'Completed Tasks',
                        value: metrics['completed_tasks'] ?? 0,
                        icon: Icons.check_circle_outline,
                        color: AppColors.success,
                      ),
                      MetricCard(
                        label: 'Pending Tasks',
                        value: metrics['pending_tasks'] ?? 0,
                        icon: Icons.pending_actions,
                        color: AppColors.warning,
                      ),
                      MetricCard(
                        label: 'Escalated',
                        value: metrics['escalated_cases'] ?? 0,
                        icon: Icons.arrow_upward,
                        color: AppColors.statusEscalated,
                      ),
                      MetricCard(
                        label: 'Failed Cases',
                        value: metrics['failed_cases'] ?? 0,
                        icon: Icons.close,
                        color: AppColors.error,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Category distribution
                  if (categories.isNotEmpty) ...[
                    const Text('Issue Categories',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          height: 200,
                          child: PieChart(
                            PieChartData(
                              sections: _buildPieSections(categories),
                              centerSpaceRadius: 50,
                              sectionsSpace: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: List.generate(
                        categories.length,
                        (i) => _legendItem(categories[i]['category'] ?? '', _piColors[i % _piColors.length]),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Monthly resolution chart
                  if (monthly.isNotEmpty) ...[
                    const Text('Monthly Resolution Trend',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          height: 180,
                          child: BarChart(
                            BarChartData(
                              barGroups: List.generate(
                                monthly.length,
                                (i) => BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: (monthly[i]['resolved'] as int).toDouble(),
                                      color: AppColors.primary,
                                      width: 20,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ],
                                ),
                              ),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (v, _) => Text(
                                      monthly[v.toInt()]['month']?.toString().substring(0, 3) ?? '',
                                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                                    ),
                                  ),
                                ),
                                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              gridData: const FlGridData(show: false),
                              borderData: FlBorderData(show: false),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 60, color: AppColors.textHint),
              const SizedBox(height: 16),
              Text('$e', style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(leaderDashboardProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _piColors = [
    AppColors.primary, AppColors.accent, AppColors.success,
    AppColors.warning, AppColors.error, AppColors.statusEscalated,
  ];

  List<PieChartSectionData> _buildPieSections(List data) {
    final total = data.fold<int>(0, (sum, d) => sum + (d['count'] as int));
    return List.generate(data.length, (i) {
      final pct = total > 0 ? (data[i]['count'] as int) / total * 100 : 0;
      return PieChartSectionData(
        value: pct.toDouble(),
        color: _piColors[i % _piColors.length],
        title: '${pct.toStringAsFixed(0)}%',
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
        radius: 60,
      );
    });
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}