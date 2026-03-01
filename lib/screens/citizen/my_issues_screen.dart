import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../providers/issues_provider.dart';
import '../../widgets/common_widgets.dart';

class MyIssuesScreen extends ConsumerWidget {
  const MyIssuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issuesAsync = ref.watch(issuesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Issues'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/citizen'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(issuesProvider.notifier).fetchIssues(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/citizen/submit'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Report New'),
      ),
      body: issuesAsync.when(
        data: (issues) {
          if (issues.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 72, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  const Text('No issues reported yet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  const Text('Tap the button below to report your first civic issue',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textHint)),
                  const SizedBox(height: 80),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Status filter chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'OPEN', 'RESOLVED_L1', 'RESOLVED_L2', 'CLOSED', 'ESCALATED']
                        .map((s) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(s == 'All' ? 'All' : _labelFor(s)),
                                selected: s == 'All',
                                onSelected: (_) {},
                                selectedColor: AppColors.primary.withOpacity(0.15),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
              // Issues list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: issues.length,
                  itemBuilder: (_, i) => IssueCard(
                    issue: issues[i],
                    onTap: () => context.go('/issue/${issues[i].id}'),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 60, color: AppColors.textHint),
              const SizedBox(height: 16),
              Text('Error: $e', style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(issuesProvider.notifier).fetchIssues(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _labelFor(String status) {
    switch (status) {
      case 'RESOLVED_L1': return 'Resolved ✔';
      case 'RESOLVED_L2': return 'Resolved ✔✔';
      default: return status[0] + status.substring(1).toLowerCase();
    }
  }
}