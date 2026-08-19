import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../config/responsive.dart';
import '../../models/student.dart';
import '../../services/student_provider.dart';
import '../../widgets/ui_components.dart';

class StudentsTab extends StatefulWidget {
  const StudentsTab({super.key});

  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final students = context.watch<StudentProvider>();
    final hp = ResponsiveLayout.horizontalPadding(context);
    final filtered =
        _query.isEmpty
              ? List<Student>.of(students.students)
              : students.students.where((s) {
                  final q = _query.toLowerCase();
                  return s.fullName.toLowerCase().contains(q) ||
                      s.studentId.toLowerCase().contains(q);
                }).toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hp, 20, hp, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Students',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.importExcel),
                      icon: const Icon(Icons.upload_file),
                      tooltip: 'Import from Excel',
                    ),
                    IconButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.addStudent),
                      icon: const Icon(Icons.person_add),
                      tooltip: 'Add Student',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search by name or ID...',
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
            child: students.loadFailed
                ? AppErrorState(
                    title: "Couldn't load students",
                    message:
                        'Your student data couldn\'t be read from storage. '
                        'Try again.',
                    onRetry: students.loadStudents,
                  )
                : students.students.isEmpty
                ? _buildEmptyState(context)
                : _buildStudentList(context, filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return AppEmptyState(
      icon: Icons.people_outline,
      title: 'No students yet',
      message: 'Add students to get started',
      buttonLabel: 'Add Students',
      onPressed: () => Navigator.pushNamed(context, AppRoutes.addStudent),
      secondaryButtonLabel: 'Import from Excel',
      secondaryOnPressed: () =>
          Navigator.pushNamed(context, AppRoutes.importExcel),
    );
  }

  Widget _buildStudentList(BuildContext context, List<Student> filtered) {
    if (filtered.isEmpty && _query.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 48, color: context.lightText),
              const SizedBox(height: 12),
              Text(
                'No students matching "$_query"',
                style: TextStyle(color: context.lightText),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final student = filtered[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: context.primaryGreen.withValues(alpha: 0.1),
              child: Text(
                student.fullName[0].toUpperCase(),
                style: TextStyle(
                  color: context.primaryGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(student.fullName),
            subtitle: Text(
              student.studentId.isNotEmpty ? 'ID: ${student.studentId}' : '',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.studentDetail,
              arguments: student,
            ),
          ),
        );
      },
    );
  }
}
