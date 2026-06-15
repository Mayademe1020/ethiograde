import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/student_provider.dart';
import '../../services/class_provider.dart';

class StudentsTab extends StatelessWidget {
  const StudentsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final students = context.watch<StudentProvider>();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Students',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
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
          Expanded(
            child: students.students.isEmpty
                ? _buildEmptyState(context)
                : _buildStudentList(context, students),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No students yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add students to get started',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.addStudent),
            icon: const Icon(Icons.person_add),
            label: const Text('Add Students'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.importExcel),
            icon: const Icon(Icons.upload_file),
            label: const Text('Import from Excel'),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentList(BuildContext context, StudentProvider students) {
    final sorted = List.of(students.students)
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final student = sorted[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
              child: Text(
                student.fullName[0].toUpperCase(),
                style: TextStyle(
                  color: AppTheme.primaryGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(student.fullName),
            subtitle: Text(
              student.studentId.isNotEmpty ? 'ID: ${student.studentId}' : '',
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }
}
