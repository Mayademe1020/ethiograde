import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/assessment_provider.dart';
import '../../models/assessment.dart';
import '../../services/student_provider.dart';
import '../../models/student.dart';
import '../../services/settings_provider.dart';
import '../../services/teacher_provider.dart';
import '../../services/class_provider.dart';
import '../../models/class_info.dart';
import '../../widgets/assessment_card.dart';
import '../../widgets/ui_components.dart';
import '../../services/draft_service.dart';
import '../../models/scan_result.dart';
import '../../services/demo_data_service.dart';
import '../classes/create_class_sheet.dart';
import '../classes/class_detail_screen.dart';
import 'dashboard_actions.dart';
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
  void initState() {
    super.initState();
    // Ensure test exam exists
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DemoDataService.seed(
        classProvider: context.read<ClassProvider>(),
        studentProvider: context.read<StudentProvider>(),
        assessmentProvider: context.read<AssessmentProvider>(),
      );
    });
  }

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
    final assessments = context.watch<AssessmentProvider>();
    final settings = context.watch<SettingsProvider>();
    final classes = context.watch<ClassProvider>().classes;
    context.watch<TeacherProvider>();

    final action = resolveDashboardAction(
      allAssessments: assessments.assessments,
      activeAssessments: assessments.activeAssessments,
    );

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Welcome, ${settings.teacherName}",
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (settings.schoolName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      settings.schoolName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Primary action card (unified — includes draft resume) ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _buildPrimaryAction(context, action),
            ),
          ),

          // ── Quick actions row ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.add_circle_outline,
                      label: 'Create Exam',
                      onTap: () => Navigator.pushNamed(context, AppRoutes.createAssessment),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.group_add_outlined,
                      label: 'Create Class',
                      onTap: () => _createClass(context),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Student search bar ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _StudentSearchBar(),
            ),
          ),

          // ── Recent Assessments ──────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'Recent Assessments',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (assessments.assessments.isNotEmpty)
                    TextButton(
                      onPressed: onSeeAll,
                      child: const Text('See All'),
                    ),
                ],
              ),
            ),
          ),

          if (assessments.assessments.isEmpty)
            SliverToBoxAdapter(child: _EmptyAssessments())
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AssessmentCard(
                      assessment: assessments.assessments[index],
                    ),
                  ),
                  childCount: assessments.assessments.length.clamp(0, 5),
                ),
              ),
            ),

          // ── My Classes ──────────────────────────────────────────
          if (classes.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'My Classes',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _createClass(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New'),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 130,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: classes.length,
                  itemBuilder: (context, index) {
                    final cls = classes[index];
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
          ] else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _EmptyClassesCard(onCreate: () => _createClass(context)),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction(BuildContext context, DashboardAction action) {
    final cs = Theme.of(context).colorScheme;

    IconData icon;
    switch (action.type) {
      case DashboardActionType.resumeDraft:
        icon = Icons.play_circle_fill;
      case DashboardActionType.finishSetup:
        icon = Icons.key;
      case DashboardActionType.startScanning:
        icon = Icons.document_scanner;
      case DashboardActionType.gradePapers:
        icon = Icons.assignment_add;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary,
            Color.lerp(cs.primary, cs.primaryContainer, 0.35)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleActionTap(context, action),
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          splashColor: Colors.white.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Icon(icon, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action.title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            action.description,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.white.withOpacity(0.85),
                                  height: 1.4,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _handleActionTap(context, action),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            action.ctaLabel,
                            style: TextStyle(
                              color: cs.primary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.arrow_forward,
                            color: cs.primary,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleActionTap(BuildContext context, DashboardAction action) {
    switch (action.type) {
      case DashboardActionType.resumeDraft:
        _resumeDraft(context, action.assessment!);
      case DashboardActionType.finishSetup:
        Navigator.pushNamed(
          context,
          AppRoutes.answerKey,
          arguments: action.assessment,
        );
      case DashboardActionType.startScanning:
        _handleScanTap(context);
      case DashboardActionType.gradePapers:
        Navigator.pushNamed(context, AppRoutes.createAssessment);
    }
  }

  void _resumeDraft(BuildContext context, Assessment assessment) {
    final drafts = DraftService().getAllDrafts();
    final matches = drafts.where((d) => d.assessmentId == assessment.id);
    if (matches.isEmpty || !context.mounted) return;
    final draft = matches.first;

    final completedResults = draft.completedResults
        .map((m) => ScanResult.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    Navigator.pushNamed(
      context,
      AppRoutes.batchScan,
      arguments: {
        'assessment': assessment,
        'draftCompletedResults': completedResults,
        'draftCurrentIndex': draft.currentStudentIndex,
      },
    );
  }

  void _createClass(BuildContext context) async {
    final cls = await CreateClassSheet.show(context);
    if (cls != null && context.mounted) {
      await context.read<ClassProvider>().addClass(cls);
    }
  }
}

void _handleScanTap(BuildContext context) {
  final assessments = context.read<AssessmentProvider>().activeAssessments;

  if (assessments.isEmpty) {
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

  final incomplete = assessments.where((a) => !a.isAnswerKeyComplete).toList();
  if (incomplete.isNotEmpty) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.info_outline, color: AppTheme.info, size: 36),
        title: Text('Answer Key Needed'),
        content: Text(
          '"${incomplete.first.title}" does not have an answer key yet. You can scan the answer sheet or enter answers manually.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(
                context,
                AppRoutes.answerKey,
                arguments: incomplete.first,
              );
            },
            child: Text('Set Answer Key'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.camera);
            },
            child: Text('Scan Anyway'),
          ),
        ],
      ),
    );
    return;
  }

  Navigator.pushNamed(context, AppRoutes.camera);
}

class _EmptyClassesCard extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyClassesCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onCreate,
      color: cs.primaryContainer.withOpacity(0.3),
      borderColor: cs.primary.withOpacity(0.15),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.group_add, color: cs.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create your first class',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Group students by grade, subject, or section',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 14, color: cs.primary),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create First Class'),
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
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.class_, color: cs.primary, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              classInfo.displayName,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: cs.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '$studentCount student${studentCount == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyAssessments extends StatelessWidget {
  const _EmptyAssessments();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AppCard(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderColor: cs.outlineVariant,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(
                  Icons.assignment_outlined,
                  size: 40,
                  color: cs.onSurfaceVariant.withOpacity(0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'No assessments yet',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Create a test or quiz',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.createAssessment,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create First Assessment'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentSearchBar extends StatefulWidget {
  const _StudentSearchBar();

  @override
  State<_StudentSearchBar> createState() => _StudentSearchBarState();
}

class _StudentSearchBarState extends State<_StudentSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  bool _showResults = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final students = context.watch<StudentProvider>().students;
    final filtered = _query.isEmpty
        ? <Student>[]
        : students.where((s) {
            final q = _query.toLowerCase();
            return s.fullName.toLowerCase().contains(q) ||
                s.studentId.toLowerCase().contains(q);
          }).take(5).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: (v) => setState(() {
            _query = v;
            _showResults = v.isNotEmpty;
          }),
          onTapOutside: (_) => Future.delayed(
            const Duration(milliseconds: 200),
            () => mounted ? setState(() => _showResults = false) : null,
          ),
          decoration: InputDecoration(
            hintText: 'Find a student...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _controller.clear();
                      setState(() {
                        _query = '';
                        _showResults = false;
                      });
                    },
                  )
                : null,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        if (_showResults && filtered.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in filtered)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
                      child: Text(
                        s.fullName[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ),
                    title: Text(s.fullName, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      s.studentId.isNotEmpty ? 'ID: ${s.studentId}' : '',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 16),
                    onTap: () {
                      _focusNode.unfocus();
                      setState(() => _showResults = false);
                      Navigator.pushNamed(
                        context,
                        AppRoutes.studentDetail,
                        arguments: s,
                      );
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
