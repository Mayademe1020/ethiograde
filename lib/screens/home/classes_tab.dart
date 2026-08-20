import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../config/responsive.dart';
import '../../models/class_info.dart';
import '../../services/class_provider.dart';
import '../../services/student_provider.dart';
import '../../widgets/ui_components.dart';
import '../classes/create_class_sheet.dart';

/// A dedicated tab for managing all classes: browse, search, create, edit,
/// and delete — then drill into [ClassDetailScreen] to work on a class.
class ClassesTab extends StatefulWidget {
  const ClassesTab({super.key});

  @override
  State<ClassesTab> createState() => _ClassesTabState();
}

class _ClassesTabState extends State<ClassesTab> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final classesProv = context.watch<ClassProvider>();
    final studentProv = context.watch<StudentProvider>();
    final hp = ResponsiveLayout.horizontalPadding(context);

    final allClasses = classesProv.classes;
    final filtered = _query.isEmpty
        ? allClasses
        : allClasses.where((c) {
            final q = _query.toLowerCase();
            return c.displayName.toLowerCase().contains(q) ||
                c.subject.toLowerCase().contains(q) ||
                c.section.toLowerCase().contains(q) ||
                c.academicYear.toLowerCase().contains(q);
          }).toList();

    final totalStudents = studentProv.students
        .where((s) => s.classIds.any(
              (id) => allClasses.any((c) => c.id == id),
            ))
        .length;
    final subjectsCount = allClasses
        .map((c) => c.subject.toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(hp, 20, hp, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Classes',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _createClass(context),
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Add Class',
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
              child: _buildSummary(
                context,
                classCount: allClasses.length,
                studentCount: totalStudents,
                subjectCount: subjectsCount,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(hp, 14, hp, 0),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search by name, subject, or grade...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: context.outlineLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: context.outlineLight),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: classesProv.loadFailed
                  ? AppErrorState(
                      title: "Couldn't load classes",
                      message:
                          'Your class data couldn\'t be read from storage. '
                          'Try again.',
                      onRetry: classesProv.reload,
                    )
                  : allClasses.isEmpty
                      ? _buildEmptyState(context)
                      : filtered.isEmpty && _query.isNotEmpty
                          ? _buildNoResults(context)
                          : _buildClassGrid(
                              context,
                              filtered,
                              studentProv,
                            ),
            ),
          ],
        ),
      ),
      floatingActionButton: allClasses.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _createClass(context),
              icon: const Icon(Icons.add),
              label: const Text('Add Class'),
            ),
    );
  }

  Widget _buildSummary(
    BuildContext context, {
    required int classCount,
    required int studentCount,
    required int subjectCount,
  }) {
    final cs = Theme.of(context).colorScheme;
    final items = [
      _SummaryStat(
        icon: Icons.class_,
        value: '$classCount',
        label: 'Classes',
      ),
      _SummaryStat(
        icon: Icons.people,
        value: '$studentCount',
        label: 'Students',
      ),
      _SummaryStat(
        icon: Icons.menu_book_outlined,
        value: '$subjectCount',
        label: 'Subjects',
      ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items
            .map(
              (s) => Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(s.icon, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.value,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                        ),
                        Text(
                          s.label,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildClassGrid(
    BuildContext context,
    List<ClassInfo> classes,
    StudentProvider studentProv,
  ) {
    final columns = ResponsiveLayout.gridColumns(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemCount: classes.length,
      itemBuilder: (context, index) {
        final cls = classes[index];
        final studentCount = studentProv.students
            .where((s) => s.classIds.contains(cls.id))
            .length;
        return _ClassGridCard(
          classInfo: cls,
          studentCount: studentCount,
          onTap: () => _openClass(context, cls),
          onEdit: () => _editClass(context, cls),
          onDelete: () => _confirmDelete(context, cls),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return AppEmptyState(
      icon: Icons.class_outlined,
      title: 'No classes yet',
      message: 'Create a class to group your students by grade or subject.',
      buttonLabel: 'Create Class',
      onPressed: () => _createClass(context),
    );
  }

  Widget _buildNoResults(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: context.lightText),
            const SizedBox(height: 12),
            Text(
              'No classes matching "$_query"',
              style: TextStyle(color: context.lightText),
            ),
          ],
        ),
      ),
    );
  }

  void _openClass(BuildContext context, ClassInfo cls) {
    Navigator.pushNamed(context, AppRoutes.classDetail, arguments: cls);
  }

  Future<void> _createClass(BuildContext context) async {
    final cls = await CreateClassSheet.show(context);
    if (cls != null && context.mounted) {
      final result = await context.read<ClassProvider>().addClass(cls);
      if (result.success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${cls.displayName} created')),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Could not create class'),
            backgroundColor: context.primaryRed,
          ),
        );
      }
    }
  }

  Future<void> _editClass(BuildContext context, ClassInfo cls) async {
    final updated = await CreateClassSheet.show(context, existing: cls);
    if (updated != null && context.mounted) {
      final result =
          await context.read<ClassProvider>().updateClass(updated);
      if (!result.success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Could not update class'),
            backgroundColor: context.primaryRed,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, ClassInfo cls) async {
    final classProv = context.read<ClassProvider>();
    final check = classProv.canDeleteClass(cls.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Class'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delete ${cls.displayName}? Students will not be deleted.'),
            if (!check.canDelete)
              ...[
                const SizedBox(height: 12),
                ...check.blockingReasons.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: context.primaryRed,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            r,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.primaryRed,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final result = await classProv.deleteClass(cls.id);
      if (result.success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${cls.displayName} deleted')),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Could not delete class'),
            backgroundColor: context.primaryRed,
          ),
        );
      }
    }
  }
}

class _SummaryStat {
  final IconData icon;
  final String value;
  final String label;
  const _SummaryStat({
    required this.icon,
    required this.value,
    required this.label,
  });
}

class _ClassGridCard extends StatelessWidget {
  final ClassInfo classInfo;
  final int studentCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClassGridCard({
    required this.classInfo,
    required this.studentCount,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label:
          '${classInfo.displayName}, $studentCount student${studentCount == 1 ? '' : 's'}',
      button: true,
      child: AppCard(
        onTap: onTap,
        color: cs.surface,
        borderColor: cs.outlineVariant,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.class_, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    classInfo.displayName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            color: context.primaryRed,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Delete',
                            style: TextStyle(color: context.primaryRed),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (classInfo.subject.isNotEmpty)
                  _Chip(label: classInfo.subject),
                if (classInfo.section.isNotEmpty)
                  _Chip(label: 'Sec ${classInfo.section}'),
                _Chip(label: '$studentCount students'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cs.primary,
        ),
      ),
    );
  }
}
