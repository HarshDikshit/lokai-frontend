import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/app_theme.dart';
import '../../providers/issues_provider.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

class TaskManagementScreen extends ConsumerStatefulWidget {
  const TaskManagementScreen({super.key});

  @override
  ConsumerState<TaskManagementScreen> createState() => _TaskManagementScreenState();
}

class _TaskManagementScreenState extends ConsumerState<TaskManagementScreen> {
  String? _selectedIssueId;
  String? _selectedAssigneeId;
  DateTime? _deadline;
  final _descCtrl = TextEditingController();
  bool _creating = false;

  Future<void> _createTask() async {
    if (_selectedIssueId == null || _selectedAssigneeId == null || _deadline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }
    setState(() => _creating = true);
    try {
      await ApiService.instance.createTask(
        issueId: _selectedIssueId!,
        assignedTo: _selectedAssigneeId!,
        deadline: _deadline!,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );
      ref.invalidate(tasksProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task created!'), backgroundColor: AppColors.success),
      );
      setState(() {
        _selectedIssueId = null;
        _selectedAssigneeId = null;
        _deadline = null;
        _descCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) setState(() => _deadline = date);
  }

  Future<void> _updateTaskStatus(String taskId, String status) async {
    await ApiService.instance.updateTask(taskId, {'status': status});
    ref.invalidate(tasksProvider);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final issuesAsync = ref.watch(issuesProvider);
    final tasksAsync = ref.watch(tasksProvider);
    final usersAsync = ref.watch(usersProvider(null));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Management'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/leader'),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), label: 'Issues'),
          NavigationDestination(icon: Icon(Icons.task_outlined), label: 'Tasks'),
        ],
        selectedIndex: 2,
        onDestinationSelected: (i) {
          if (i == 0) context.go('/leader');
          if (i == 1) context.go('/leader/issues');
        },
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Create Task Panel
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.add_task, color: AppColors.primary, size: 20),
                        SizedBox(width: 8),
                        Text('Create New Task', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Issue picker
                    issuesAsync.when(
                      data: (issues) {
                        final openIssues = issues.where((i) => i.status == 'OPEN' || i.status == 'RESOLVED_L1').toList();
                        return DropdownButtonFormField<String>(
                          value: _selectedIssueId,
                          decoration: const InputDecoration(labelText: 'Select Issue *', prefixIcon: Icon(Icons.list_alt_outlined)),
                          items: openIssues.map((i) => DropdownMenuItem(
                            value: i.id,
                            child: Text(i.title, overflow: TextOverflow.ellipsis),
                          )).toList(),
                          onChanged: (v) => setState(() => _selectedIssueId = v),
                        );
                      },
                      loading: () => const CircularProgressIndicator(),
                      error: (_, __) => const Text('Error loading issues'),
                    ),
                    const SizedBox(height: 12),

                    // Assignee picker
                    usersAsync.when(
                      data: (users) {
                        return DropdownButtonFormField<String>(
                          value: _selectedAssigneeId,
                          decoration: const InputDecoration(labelText: 'Assign To *', prefixIcon: Icon(Icons.person_outline)),
                          items: users.map((u) => DropdownMenuItem(
                            value: u.id,
                            child: Text('${u.name} (${u.role})'),
                          )).toList(),
                          onChanged: (v) => setState(() => _selectedAssigneeId = v),
                        );
                      },
                      loading: () => const CircularProgressIndicator(),
                      error: (_, __) => const Text('Error loading users'),
                    ),
                    const SizedBox(height: 12),

                    // Deadline
                    GestureDetector(
                      onTap: _pickDeadline,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.inputFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderColor),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined, color: AppColors.textSecondary, size: 18),
                            const SizedBox(width: 10),
                            Text(
                              _deadline != null
                                  ? 'Deadline: ${DateFormat('MMM d, yyyy').format(_deadline!)}'
                                  : 'Set Deadline *',
                              style: TextStyle(
                                color: _deadline != null ? AppColors.textPrimary : AppColors.textHint,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Task Description (optional)',
                        prefixIcon: Icon(Icons.description_outlined),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _creating ? null : _createTask,
                        icon: _creating
                            ? const SizedBox(height: 16, width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.add),
                        label: const Text('Create Task'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Tasks list
            Row(
              children: [
                const Text('Active Tasks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => ref.invalidate(tasksProvider),
                ),
              ],
            ),
            const SizedBox(height: 12),

            tasksAsync.when(
              data: (tasks) {
                if (tasks.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Text('No tasks yet', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tasks.length,
                  itemBuilder: (_, i) => _TaskCard(
                    task: tasks[i],
                    onStatusChange: (status) => _updateTaskStatus(tasks[i].id, status),
                    onVerifyTap: () => context.go('/leader/verify/${tasks[i].id}'),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Task task;
  final Function(String) onStatusChange;
  final VoidCallback onVerifyTap;

  const _TaskCard({
    required this.task,
    required this.onStatusChange,
    required this.onVerifyTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = task.deadline.isBefore(DateTime.now()) && task.status != 'completed';
    final (statusColor, statusLabel) = _statusProps(task.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.issueTitle ?? 'Issue Task',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(statusLabel, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (task.assigneeName != null) ...[
              const SizedBox(height: 6),
              Text('Assigned to: ${task.assigneeName}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 13,
                  color: isOverdue ? AppColors.error : AppColors.textHint,
                ),
                const SizedBox(width: 4),
                Text(
                  'Due: ${DateFormat('MMM d, yyyy').format(task.deadline)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isOverdue ? AppColors.error : AppColors.textSecondary,
                    fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (isOverdue) ...[
                  const SizedBox(width: 4),
                  const Text('OVERDUE', style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (task.status == 'pending')
                  _actionChip('Start', Icons.play_arrow, AppColors.info, () => onStatusChange('in_progress')),
                if (task.status == 'in_progress') ...[
                  _actionChip('Complete', Icons.check, AppColors.success, () => onStatusChange('completed')),
                  const SizedBox(width: 8),
                  _actionChip('Verify', Icons.camera_alt, AppColors.primary, onVerifyTap),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionChip(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  (Color, String) _statusProps(String status) {
    switch (status) {
      case 'in_progress': return (AppColors.warning, 'In Progress');
      case 'completed': return (AppColors.success, 'Completed');
      case 'cancelled': return (AppColors.error, 'Cancelled');
      default: return (AppColors.info, 'Pending');
    }
  }
}