import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/assessment_provider.dart';
import '../../models/assessment.dart';
import '../../services/student_provider.dart';
import '../../services/settings_provider.dart';
import '../../services/teacher_provider.dart';
import '../../services/class_provider.dart';
import '../../models/class_info.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/assessment_card.dart';
import '../../widgets/resume_grading_banner.dart';
import '../../widgets/product_components.dart';
import '../assessment/exam_day_create_screen.dart';
import '../classes/create_class_sheet.dart';
import '../classes/class_detail_screen.dart';
import 'settings_tab.dart';
import 'students_tab.dart';
import 'assessments_tab.dart';

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
          const AssessmentsTab(),
          const StudentsTab(),
          const SettingsTab(),
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
