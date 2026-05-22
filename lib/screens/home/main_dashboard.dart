import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../config/constants.dart';
import '../../services/assessment_provider.dart';
import '../../models/assessment.dart';
import '../../services/student_provider.dart';
import '../../services/settings_provider.dart';
import '../../services/teacher_provider.dart';
import '../../services/backup_service.dart';
import '../../models/teacher.dart';
import '../../services/class_provider.dart';
import '../../models/class_info.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/assessment_card.dart';
import '../../widgets/resume_grading_banner.dart';
import '../../widgets/product_components.dart';
import '../assessment/exam_day_create_screen.dart';
import '../classes/create_class_sheet.dart';
import '../classes/class_detail_screen.dart';

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _DashboardHome(onSeeAll: () => setState(() => _currentIndex = 1)),
          _AssessmentsTab(),
          _StudentsTab(),
          _SettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.assignment_outlined),
            selectedIcon: const Icon(Icons.assignment),
            label: 'Assess',
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people),
            label: 'Students',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ──── Dashboard Home ────

class _DashboardHome extends StatelessWidget {
  final VoidCallback onSeeAll;
  const _DashboardHome({required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final students = context.watch<StudentProvider>();
    final assessments = context.watch<AssessmentProvider>();
    final settings = context.watch<SettingsProvider>();
    final readyAssessments = assessments.activeAssessments
        .where((assessment) => assessment.isAnswerKeyComplete)
        .toList(growable: false);
    final setupAssessments = assessments.activeAssessments
        .where((assessment) => !assessment.isAnswerKeyComplete)
        .toList(growable: false);
    // Ensure TeacherProvider is initialized (triggers lazy box load).
    context.watch<TeacherProvider>();

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // App bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Welcome, ${settings.teacherName}",
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            if (settings.schoolName.isNotEmpty)
                              Text(
                                settings.schoolName,
                                style: TextStyle(
                                  color: AppTheme.lightText,
                                  fontSize: 14,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Resume grading banner (if draft exists)
                  const ResumeGradingBanner(),

                  // Quick stats
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          icon: Icons.people,
                          value: '${students.totalStudents}',
                          label: 'Students',
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          icon: Icons.assignment,
                          value: '${assessments.activeAssessments.length}',
                          label: 'Active',
                          color: AppTheme.info,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          icon: Icons.check_circle,
                          value: '${assessments.completedAssessments.length}',
                          label: 'Completed',
                          color: AppTheme.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  PrimaryActionCard(
                    title: readyAssessments.isNotEmpty
                        ? 'Scan papers'
                        : setupAssessments.isNotEmpty
                        ? 'Finish answer key'
                        : 'Grade papers',
                    subtitle: readyAssessments.isNotEmpty
                        ? '${readyAssessments.first.title} is ready. Capture papers, review uncertain answers, then save grades.'
                        : setupAssessments.isNotEmpty
                        ? '${setupAssessments.first.title} needs its answer key before grading can feel trustworthy.'
                        : 'Start with the papers, then choose master scan, manual key, no-roster, or class list.',
                    buttonLabel: readyAssessments.isNotEmpty
                        ? 'Start Scanning'
                        : setupAssessments.isNotEmpty
                        ? 'Set Answer Key'
                        : 'Grade Papers',
                    icon: readyAssessments.isNotEmpty
                        ? Icons.document_scanner
                        : setupAssessments.isNotEmpty
                        ? Icons.rule
                        : Icons.assignment_add,
                    onPressed: () {
                      if (readyAssessments.isNotEmpty) {
                        _handleScanTap(context);
                      } else if (setupAssessments.isNotEmpty) {
                        Navigator.pushNamed(
                          context,
                          AppRoutes.answerKey,
                          arguments: setupAssessments.first,
                        );
                      } else {
                        Navigator.pushNamed(
                          context,
                          AppRoutes.createAssessment,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── Recent Activity ─────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: _RecentActivityCard(),
            ),
          ),

          // ── My Classes ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Classes',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle,
                      color: AppTheme.primaryGreen,
                    ),
                    tooltip: 'New Class',
                    onPressed: () => _createClass(context),
                  ),
                ],
              ),
            ),
          ),
          // Class cards (horizontal scroll)
          context.watch<ClassProvider>().classes.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _NoClassesYet(),
                  ),
                )
              : SliverToBoxAdapter(
                  child: SizedBox(
                    height: 140,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: context.watch<ClassProvider>().classes.length,
                      itemBuilder: (context, index) {
                        final cls = context
                            .watch<ClassProvider>()
                            .classes[index];
                        final studentCount = context
                            .watch<StudentProvider>()
                            .students
                            .where((s) => s.classIds.contains(cls.id))
                            .length;
                        return _ClassCard(
                          classInfo: cls,
                          studentCount: studentCount,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClassDetailScreen(classInfo: cls),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // Recent assessments
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Assessments',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(onPressed: onSeeAll, child: Text('See All')),
                ],
              ),
            ),
          ),

          // Assessment list
          if (assessments.assessments.isEmpty)
            SliverToBoxAdapter(child: _EmptyState())
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => AssessmentCard(
                    assessment: assessments.assessments[index],
                  ),
                  childCount: assessments.assessments.length.clamp(0, 5),
                ),
              ),
            ),

          // Quick actions
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: AppSection(
                title: 'Quick actions',
                child: _SecondaryDashboardActions(),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  void _createClass(BuildContext context) async {
    final cls = await CreateClassSheet.show(context);
    if (cls != null && context.mounted) {
      await context.read<ClassProvider>().addClass(cls);
    }
  }
}

/// Gate the scan action: check for active assessments.
/// If answer key is incomplete, show a soft warning but allow scanning
/// (teacher can scan the answer key sheet first with the checkbox).
void _handleScanTap(BuildContext context) {
  final assessments = context.read<AssessmentProvider>().activeAssessments;

  if (assessments.isEmpty) {
    // No active assessment at all
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.warning_amber, color: Colors.orange, size: 36),
        title: Text('No Active Assessment'),
        content: Text('Create an assessment before scanning.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
    return;
  }

  // Check if any assessment has an incomplete answer key
  final incomplete = assessments.where((a) => !a.isAnswerKeyComplete).toList();
  if (incomplete.isNotEmpty) {
    // Soft warning — allow scanning (teacher can scan answer key sheet first)
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.info_outline, color: AppTheme.info, size: 36),
        title: Text('Answer Key Note'),
        content: Text(
          '"${incomplete.first.title}" has no answer key set yet. You can scan your answer key sheet first (check the box on the sheet).',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.camera);
            },
            child: Text('Start Scanning'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(
                context,
                AppRoutes.answerKey,
                arguments: incomplete.first,
              );
            },
            child: Text('Set Key Manually'),
          ),
        ],
      ),
    );
    return;
  }

  // Ready — go to camera directly
  Navigator.pushNamed(context, AppRoutes.camera);
}

class _NoClassesYet extends StatelessWidget {
  const _NoClassesYet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.class_outlined, size: 32, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No classes yet',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.darkText,
                  ),
                ),
                Text(
                  'Tap + to create your first class',
                  style: TextStyle(fontSize: 12, color: AppTheme.lightText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final ClassInfo classInfo;
  final int studentCount;
  final VoidCallback onTap;

  const _ClassCard({
    required this.classInfo,
    required this.studentCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryGreen.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.class_outlined,
                    color: AppTheme.primaryGreen,
                    size: 20,
                  ),
                ),
                const Spacer(),
                if (classInfo.examScheduleNote != null &&
                    classInfo.examScheduleNote!.isNotEmpty)
                  Icon(
                    Icons.event_note,
                    size: 14,
                    color: AppTheme.primaryYellow,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              classInfo.displayName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '$studentCount ${'students'}',
              style: TextStyle(fontSize: 12, color: AppTheme.lightText),
            ),
            if (classInfo.examScheduleNote != null &&
                classInfo.examScheduleNote!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                classInfo.examScheduleNote!,
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.primaryYellow,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryDashboardActions extends StatelessWidget {
  const _SecondaryDashboardActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _QuickAction(
                icon: Icons.document_scanner_outlined,
                label: 'Master Key',
                color: Colors.teal,
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.createAssessment,
                  arguments: ExamDayStartMode.masterScan,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: Icons.person_off_outlined,
                label: 'No List',
                color: Colors.indigo,
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.createAssessment,
                  arguments: ExamDayStartMode.noRoster,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _QuickAction(
                icon: Icons.groups_outlined,
                label: 'Class List',
                color: AppTheme.primaryGreen,
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.createAssessment,
                  arguments: ExamDayStartMode.classList,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: Icons.edit_note,
                label: 'Manual Key',
                color: AppTheme.primaryYellow,
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.createAssessment,
                  arguments: ExamDayStartMode.manualKey,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No assessments yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.darkText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button below to create your first assessment',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.lightText),
          ),
        ],
      ),
    );
  }
}

// ──── Tabs ────

class _AssessmentsTab extends StatelessWidget {
  const _AssessmentsTab();

  @override
  Widget build(BuildContext context) {
    final assessments = context.watch<AssessmentProvider>();
    final readyAssessments = assessments.activeAssessments
        .where((assessment) => assessment.isAnswerKeyComplete)
        .toList(growable: false);
    final setupAssessments = assessments.activeAssessments
        .where((assessment) => !assessment.isAnswerKeyComplete)
        .toList(growable: false);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assessments',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      AppRoutes.createAssessment,
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Grade papers'),
                  ),
                ),
                const SizedBox(height: 14),
                PrimaryActionCard(
                  title: readyAssessments.isNotEmpty
                      ? 'Ready to scan'
                      : setupAssessments.isNotEmpty
                      ? 'Answer key needed'
                      : 'Grade papers',
                  subtitle: readyAssessments.isNotEmpty
                      ? '${readyAssessments.first.title} has an answer key. Scan papers or choose another assessment below.'
                      : setupAssessments.isNotEmpty
                      ? '${setupAssessments.first.title} is set up, but grading should wait until answers are complete.'
                      : 'Start from the grading job, then choose answer key and student list options.',
                  buttonLabel: readyAssessments.isNotEmpty
                      ? 'Scan Papers'
                      : setupAssessments.isNotEmpty
                      ? 'Set Answer Key'
                      : 'Grade Papers',
                  icon: readyAssessments.isNotEmpty
                      ? Icons.document_scanner
                      : setupAssessments.isNotEmpty
                      ? Icons.rule
                      : Icons.assignment_add,
                  onPressed: () {
                    if (readyAssessments.isNotEmpty) {
                      _handleScanTap(context);
                    } else if (setupAssessments.isNotEmpty) {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.answerKey,
                        arguments: setupAssessments.first,
                      );
                    } else {
                      Navigator.pushNamed(context, AppRoutes.createAssessment);
                    }
                  },
                ),
              ],
            ),
          ),
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                FilterChip(
                  label: Text('All'),
                  selected: assessments.filter == AssessmentFilter.all,
                  onSelected: (_) =>
                      assessments.setFilter(AssessmentFilter.all),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Active'),
                  selected: assessments.filter == AssessmentFilter.active,
                  onSelected: (_) =>
                      assessments.setFilter(AssessmentFilter.active),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Completed'),
                  selected: assessments.filter == AssessmentFilter.completed,
                  onSelected: (_) =>
                      assessments.setFilter(AssessmentFilter.completed),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: assessments.filteredAssessments.isEmpty
                ? AppEmptyState(
                    icon: Icons.assignment_outlined,
                    title: assessments.filter == AssessmentFilter.all
                        ? 'No assessments yet'
                        : 'No assessments in this filter',
                    message: assessments.filter == AssessmentFilter.all
                        ? 'Create one assessment, add the key, then scan papers.'
                        : 'Try another filter or create a new assessment.',
                    buttonLabel: assessments.filter == AssessmentFilter.all
                        ? 'New Assessment'
                        : null,
                    onPressed: assessments.filter == AssessmentFilter.all
                        ? () => Navigator.pushNamed(
                            context,
                            AppRoutes.createAssessment,
                          )
                        : null,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: assessments.filteredAssessments.length,
                    itemBuilder: (context, index) => AssessmentCard(
                      assessment: assessments.filteredAssessments[index],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StudentsTab extends StatelessWidget {
  const _StudentsTab();

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
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search students...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: students.searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => students.setSearchQuery(''),
                      )
                    : null,
              ),
              onChanged: students.setSearchQuery,
            ),
          ),
          const SizedBox(height: 12),
          // Class filter chips (from ClassProvider)
          Builder(
            builder: (context) {
              final classes = context.watch<ClassProvider>().classes;
              if (classes.isEmpty) return const SizedBox.shrink();
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    FilterChip(
                      label: Text('All'),
                      selected: students.selectedClassName.isEmpty,
                      onSelected: (_) => students.setSelectedClass(''),
                    ),
                    ...classes.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: FilterChip(
                          label: Text(c.displayName),
                          selected: students.selectedClassName == c.id,
                          onSelected: (_) => students.setSelectedClass(c.id),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: students.students.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No students — Import Excel or add manually',
                          style: TextStyle(color: AppTheme.lightText),
                        ),
                      ],
                    ),
                  )
                : students.studentsByClass.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No students found for \u201C${students.searchQuery}\u201D',
                          style: TextStyle(color: AppTheme.lightText),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: students.studentsByClass.length,
                    itemBuilder: (context, index) {
                      final student = students.studentsByClass[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryGreen.withOpacity(
                            0.1,
                          ),
                          child: Text(
                            student.firstName.isNotEmpty
                                ? student.firstName[0]
                                : '?',
                            style: const TextStyle(
                              color: AppTheme.primaryGreen,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(student.fullName),
                        subtitle: Text(
                          '${student.className} ${student.section}'.trim(),
                        ),
                        trailing: student.studentId.isNotEmpty
                            ? Text(
                                student.studentId,
                                style: TextStyle(
                                  color: AppTheme.lightText,
                                  fontSize: 12,
                                ),
                              )
                            : null,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.addStudent,
                          arguments: student,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final teachers = context.watch<TeacherProvider>();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Settings',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // Profile section
          _SettingsSection(
            title: 'Profile',
            children: [
              _SettingsTile(
                icon: Icons.person_outline,
                title: 'Teachers',
                subtitle: teachers.activeTeacherName.isEmpty
                    ? ('Not set — tap to add')
                    : '${teachers.activeTeacherName} (${teachers.teachers.length})',
                onTap: () => _manageTeachers(context, teachers),
              ),
              _SettingsTile(
                icon: Icons.school_outlined,
                title: 'School',
                subtitle: settings.schoolName.isEmpty
                    ? ('Not set')
                    : settings.schoolName,
                onTap: () => _editSchool(context, settings),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Preferences
          _SettingsSection(
            title: 'Preferences',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.auto_fix_high),
                title: Text('Auto-enhance Images'),
                value: settings.autoEnhanceImages,
                onChanged: (_) => settings.toggleAutoEnhance(),
                activeColor: AppTheme.primaryGreen,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.mic),
                title: Text('Voice Feedback'),
                value: settings.voiceFeedbackEnabled,
                onChanged: (_) => settings.toggleVoiceFeedback(),
                activeColor: AppTheme.primaryGreen,
              ),
              _SettingsTile(
                icon: Icons.grading,
                title: 'Default Rubric',
                subtitle: settings.defaultRubric == 'moe_national'
                    ? ('MoE National')
                    : settings.defaultRubric == 'university'
                    ? ('University')
                    : ('Private/International'),
                onTap: () => _selectRubric(context, settings),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Data & Privacy
          _SettingsSection(
            title: 'Data & Privacy',
            children: [
              _SettingsTile(
                icon: Icons.shield_outlined,
                title: 'Your data stays on your phone',
                subtitle:
                    'No internet needed — everything stored locally with AES-256 encryption',
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.backup_outlined,
                title: 'Export Backup',
                subtitle: 'Export all data to an encrypted backup file',
                onTap: () => _exportBackup(context),
              ),
              _SettingsTile(
                icon: Icons.restore_outlined,
                title: 'Import Backup',
                subtitle: 'Restore data from a previous backup',
                onTap: () => _importBackup(context),
              ),
              _StorageInfoTile(),
              _SettingsTile(
                icon: Icons.delete_forever_outlined,
                title: 'Clear All Data',
                subtitle: 'Deletes all students, assessments, and results',
                onTap: () => _confirmClearData(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // About
          _SettingsSection(
            title: 'About',
            children: [
              _SettingsTile(
                icon: Icons.info_outline,
                title: 'EthioGrade',
                subtitle: 'v${AppConstants.appVersion}',
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy',
                subtitle: 'Your data stays on your phone',
                onTap: () => _showPrivacyPolicy(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Teacher management dialog — list, add, edit, delete teachers.
  void _manageTeachers(BuildContext ctx, TeacherProvider provider) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (c, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Teachers',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_add),
                    tooltip: 'Add Teacher',
                    onPressed: () => _showTeacherForm(ctx, provider),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: provider.teachers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No teachers yet',
                              style: TextStyle(color: AppTheme.lightText),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => _showTeacherForm(ctx, provider),
                              icon: const Icon(Icons.add),
                              label: Text('Add Teacher'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: provider.teachers.length,
                        itemBuilder: (context, index) {
                          final teacher = provider.teachers[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: teacher.isActive
                                  ? AppTheme.primaryGreen.withOpacity(0.15)
                                  : Colors.grey.shade200,
                              child: Text(
                                teacher.name.isNotEmpty
                                    ? teacher.name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: teacher.isActive
                                      ? AppTheme.primaryGreen
                                      : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(teacher.name),
                            subtitle: Text(
                              (() {
                                final parts = <String>[];
                                if (teacher.subject.isNotEmpty)
                                  parts.add(teacher.subject);
                                if (teacher.school.isNotEmpty)
                                  parts.add(teacher.school);
                                return parts.isNotEmpty
                                    ? parts.join(' • ')
                                    : ('No details');
                              })(),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (teacher.isActive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryGreen.withOpacity(
                                        0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Active',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.primaryGreen,
                                      ),
                                    ),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () => _showTeacherForm(
                                    ctx,
                                    provider,
                                    existing: teacher,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: AppTheme.primaryRed,
                                  ),
                                  onPressed: () =>
                                      _confirmDelete(ctx, provider, teacher),
                                ),
                              ],
                            ),
                            onTap: () async {
                              await provider.setActive(teacher.id);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      "${teacher.name} set as active",
                                    ),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Add or edit teacher form dialog.
  void _showTeacherForm(
    BuildContext ctx,
    TeacherProvider provider, {
    Teacher? existing,
  }) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final subjectCtrl = TextEditingController(text: existing?.subject ?? '');
    final schoolCtrl = TextEditingController(text: existing?.school ?? '');
    final isEdit = existing != null;

    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(isEdit ? ('Edit Teacher') : ('Add Teacher')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Name *',
                  hintText: 'Teacher name',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subjectCtrl,
                decoration: InputDecoration(
                  labelText: 'Subject',
                  hintText: 'e.g. Mathematics',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: schoolCtrl,
                decoration: InputDecoration(
                  labelText: 'School',
                  hintText: 'School name',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(SnackBar(content: Text('Name is required')));
                return;
              }

              if (isEdit) {
                final updated = existing.copyWith(
                  name: name,
                  subject: subjectCtrl.text.trim(),
                  school: schoolCtrl.text.trim(),
                );
                await provider.updateTeacher(updated);
              } else {
                final teacher = Teacher(
                  name: name,
                  subject: subjectCtrl.text.trim(),
                  school: schoolCtrl.text.trim(),
                );
                await provider.addTeacher(teacher);
              }

              if (c.mounted) Navigator.pop(c);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Confirm deletion dialog.
  void _confirmDelete(
    BuildContext ctx,
    TeacherProvider provider,
    Teacher teacher,
  ) {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text('Delete Teacher'),
        content: Text('Delete ${teacher.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await provider.deleteTeacher(teacher.id);
              if (c.mounted) Navigator.pop(c);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryRed,
            ),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _editSchool(BuildContext ctx, SettingsProvider s) {
    final controller = TextEditingController(text: s.schoolName);
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text('Edit School'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: 'School Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              s.updateSchoolInfo(name: controller.text);
              Navigator.pop(c);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _selectRubric(BuildContext ctx, SettingsProvider s) {
    showModalBottomSheet(
      context: ctx,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('MoE National (0-100, 50% pass)'),
              trailing: s.defaultRubric == 'moe_national'
                  ? const Icon(Icons.check, color: AppTheme.primaryGreen)
                  : null,
              onTap: () {
                s.setDefaultRubric('moe_national');
                Navigator.pop(c);
              },
            ),
            ListTile(
              title: Text('Private/International (60% pass)'),
              trailing: s.defaultRubric == 'private_international'
                  ? const Icon(Icons.check, color: AppTheme.primaryGreen)
                  : null,
              onTap: () {
                s.setDefaultRubric('private_international');
                Navigator.pop(c);
              },
            ),
            ListTile(
              title: Text('University'),
              trailing: s.defaultRubric == 'university'
                  ? const Icon(Icons.check, color: AppTheme.primaryGreen)
                  : null,
              onTap: () {
                s.setDefaultRubric('university');
                Navigator.pop(c);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBackup(BuildContext ctx) async {
    try {
      await BackupService.instance.exportAndShare();
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importBackup(BuildContext ctx) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'enc'],
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path!;
      final importResult = await BackupService.instance.importData(filePath);

      if (ctx.mounted) {
        final msg = importResult.errors.isEmpty
            ? 'Imported ${importResult.imported} records'
            : 'Imported ${importResult.imported}, ${importResult.errors.length} errors';
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  void _showPrivacyPolicy(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text('Privacy Policy'),
        content: SingleChildScrollView(
          child: Text(
            'EthioGrade keeps ALL data on your phone only.\n\n'
            '• No data is sent to any external server\n'
            '• All data is encrypted with AES-256\n'
            '• Every feature works without internet\n'
            '• You can delete all data anytime\n'
            '• No tracking or advertising SDKs\n\n'
            'Full policy: PRIVACY_POLICY.md',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('Close')),
        ],
      ),
    );
  }

  void _confirmClearData(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text('Clear All Data?'),
        content: Text(
          'This will delete all students, assessments, results, and classes. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            onPressed: () async {
              Navigator.pop(c);
              await _clearAllData(ctx);
            },
            child: Text('Delete All'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllData(BuildContext ctx) async {
    try {
      for (final boxName in [
        'students',
        'assessments',
        'scan_results',
        'teachers',
        'classes',
        'correction_patterns',
        'metadata',
      ]) {
        if (Hive.isBoxOpen(boxName)) {
          await Hive.box(boxName).clear();
        } else {
          final box = await Hive.openBox(boxName);
          await box.clear();
        }
      }

      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('All data cleared'),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
        Navigator.pushNamedAndRemoveUntil(
          ctx,
          AppRoutes.onboarding,
          (_) => false,
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }
}

// ──── Settings Components ────

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.lightText,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.darkText),
      title: Text(title),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(fontSize: 12))
          : null,
      trailing: onTap != null
          ? Icon(Icons.chevron_right, color: Colors.grey.shade400)
          : null,
      onTap: onTap,
    );
  }
}

/// Storage usage tile — shows total disk used by Hive + scanned images.
class _StorageInfoTile extends StatelessWidget {
  const _StorageInfoTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StorageInfo>(
      future: _calculateStorage(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final subtitle = info == null
            ? 'Calculating...'
            : '${info.totalFormatted} used'
                  '${info.imageCount > 0 ? ' · ${info.imageCount} scanned images' : ''}';

        return ListTile(
          leading: Icon(Icons.storage_outlined, color: Colors.grey.shade600),
          title: Text('Storage Usage'),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: info != null && info.totalBytes > 0
              ? SizedBox(
                  width: 48,
                  height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (info.totalBytes / (500 * 1024 * 1024)).clamp(
                        0.0,
                        1.0,
                      ), // 500MB reference
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                        info.totalBytes > 200 * 1024 * 1024
                            ? AppTheme.primaryRed
                            : AppTheme.primaryGreen,
                      ),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  /// Calculate total storage used by Hive boxes + image files.
  static Future<_StorageInfo> _calculateStorage() async {
    int hiveBytes = 0;
    int imageBytes = 0;
    int imageCount = 0;

    try {
      final dir = await getApplicationDocumentsDirectory();

      // Count Hive files
      for (final entity in dir.listSync(recursive: false)) {
        if (entity is File && entity.path.endsWith('.hive')) {
          hiveBytes += await entity.length();
        }
      }

      // Count image files in common camera/cache directories
      final imageDirs = ['${dir.path}/images', '${dir.path}/Pictures'];
      for (final imageDirPath in imageDirs) {
        final imageDir = Directory(imageDirPath);
        if (await imageDir.exists()) {
          await for (final entity in imageDir.list(recursive: true)) {
            if (entity is File &&
                (entity.path.endsWith('.jpg') ||
                    entity.path.endsWith('.jpeg') ||
                    entity.path.endsWith('.png'))) {
              imageBytes += await entity.length();
              imageCount++;
            }
          }
        }
      }

      // Also check scan results for image paths stored in temp/cache
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: false)) {
          if (entity is File &&
              (entity.path.endsWith('.jpg') ||
                  entity.path.endsWith('.jpeg') ||
                  entity.path.contains('enhanced_'))) {
            imageBytes += await entity.length();
            imageCount++;
          }
        }
      }
    } catch (e) {
      debugPrint('[Storage] Failed to calculate: $e');
    }

    return _StorageInfo(
      hiveBytes: hiveBytes,
      imageBytes: imageBytes,
      imageCount: imageCount,
    );
  }
}

class _StorageInfo {
  final int hiveBytes;
  final int imageBytes;
  final int imageCount;

  const _StorageInfo({
    required this.hiveBytes,
    required this.imageBytes,
    required this.imageCount,
  });

  int get totalBytes => hiveBytes + imageBytes;

  String get totalFormatted {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard();

  @override
  Widget build(BuildContext context) {
    final assessments = context.watch<AssessmentProvider>().assessments;

    final graded =
        assessments
            .where((a) => a.status == AssessmentStatus.completed)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final inProgress =
        assessments
            .where(
              (a) =>
                  a.status == AssessmentStatus.active && a.isAnswerKeyComplete,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (graded.isEmpty && inProgress.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 18, color: AppTheme.lightText),
              const SizedBox(width: 8),
              const Text(
                'Recent Activity',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (graded.isNotEmpty) ...[
            _activityRow(
              icon: Icons.check_circle,
              iconColor: AppTheme.success,
              title: graded.first.title,
              subtitle:
                  'Completed · ${graded.first.questions.length} questions',
            ),
            if (graded.length > 1 || inProgress.isNotEmpty)
              const Divider(height: 16),
          ],
          for (final a in inProgress.take(3)) ...[
            _activityRow(
              icon: Icons.qr_code_scanner,
              iconColor: AppTheme.info,
              title: a.title,
              subtitle: 'Ready to scan · ${a.answerKeyStatus}',
            ),
            if (a != inProgress.last) const Divider(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _activityRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: AppTheme.lightText),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
