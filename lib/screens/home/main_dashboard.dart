import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/locale_provider.dart';
import '../../services/assessment_provider.dart';
import '../../services/student_provider.dart';
import '../../services/settings_provider.dart';
import '../../services/session_service.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/assessment_card.dart';
import '../../widgets/language_toggle.dart';

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
    // Check for incomplete scan session after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForResume());
  }

  /// Check if an incomplete scan session exists and show resume dialog.
  Future<void> _checkForResume() async {
    final session = await SessionService().getActiveSession();
    if (session == null || !mounted) return;

    final isAm = context.read<LocaleProvider>().isAmharic;
    final shouldResume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.restore, color: AppTheme.primaryGreen, size: 24),
            const SizedBox(width: 8),
            Text(isAm ? 'ማሰስ ይቀጥሉ?' : 'Resume Scanning?'),
          ],
        ),
        content: Text(
          isAm
              ? '${session.imageCount} ወረቀቶች ተይዘዋል። ለ "${session.assessmentTitle}" ፈተና። ማሰስ ይቀጥላሉ?'
              : 'You have ${session.imageCount} paper${session.imageCount == 1 ? '' : 's'} captured for "${session.assessmentTitle}". Continue scanning?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAm ? 'ሰርዝ' : 'Discard'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: Text(isAm ? 'ቀጥል' : 'Resume'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (shouldResume == true) {
      // Navigate to camera with existing images
      Navigator.pushNamed(
        context,
        AppRoutes.camera,
        arguments: {
          'assessmentId': session.assessmentId,
          'existingImages': session.imagePaths,
        },
      );
    } else {
      // Discard session and clean up images
      await SessionService().discardSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    final isAm = locale.isAmharic;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _DashboardHome(isAmharic: isAm),
          _AssessmentsTab(isAmharic: isAm),
          _StudentsTab(isAmharic: isAm),
          _SettingsTab(isAmharic: isAm),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: isAm ? 'ዋና' : 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.assignment_outlined),
            selectedIcon: const Icon(Icons.assignment),
            label: isAm ? 'ፈተና' : 'Assess',
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people),
            label: isAm ? 'ተማሪዎች' : 'Students',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: isAm ? 'ቅንብር' : 'Settings',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.createAssessment,
              ),
              icon: const Icon(Icons.add),
              label: Text(isAm ? 'አዲስ ፈተና' : 'New Assessment'),
            )
          : null,
    );
  }
}

// ──── Dashboard Home ────

class _DashboardHome extends StatelessWidget {
  final bool isAmharic;
  const _DashboardHome({required this.isAmharic});

  @override
  Widget build(BuildContext context) {
    final students = context.watch<StudentProvider>();
    final assessments = context.watch<AssessmentProvider>();
    final settings = context.watch<SettingsProvider>();

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
                              isAmharic
                                  ? 'እንኳን ደህና መጡ፣ ${settings.teacherName}'
                                  : 'Welcome, ${settings.teacherName}',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
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
                      const LanguageToggle(),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Quick stats
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          icon: Icons.people,
                          value: '${students.totalStudents}',
                          label: isAmharic ? 'ተማሪዎች' : 'Students',
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          icon: Icons.assignment,
                          value: '${assessments.activeAssessments.length}',
                          label: isAmharic ? 'ንቁ ፈተና' : 'Active',
                          color: AppTheme.info,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          icon: Icons.check_circle,
                          value: '${assessments.completedAssessments.length}',
                          label: isAmharic ? 'የተጠናቀቀ' : 'Completed',
                          color: AppTheme.success,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Recent assessments
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isAmharic ? 'የቅርብ ጊዜ ፈተናዎች' : 'Recent Assessments',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: Text(isAmharic ? 'ሁሉም' : 'See All'),
                  ),
                ],
              ),
            ),
          ),

          // Assessment list
          if (assessments.assessments.isEmpty)
            SliverToBoxAdapter(
              child: _EmptyState(isAmharic: isAmharic),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => AssessmentCard(
                    assessment: assessments.assessments[index],
                    isAmharic: isAmharic,
                  ),
                  childCount: assessments.assessments.length.clamp(0, 5),
                ),
              ),
            ),

          // Quick actions
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAmharic ? 'ፈጣን ተግባራት' : 'Quick Actions',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.document_scanner,
                          label: isAmharic ? 'ማሰስ' : 'Scan',
                          color: AppTheme.primaryGreen,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.camera,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.upload_file,
                          label: isAmharic ? 'Excel አስገባ' : 'Import',
                          color: AppTheme.primaryYellow,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.importExcel,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.bar_chart,
                          label: isAmharic ? 'ትንተና' : 'Analytics',
                          color: AppTheme.info,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.analytics,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.picture_as_pdf,
                          label: isAmharic ? 'ሪፖርት' : 'Reports',
                          color: AppTheme.primaryRed,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.reports,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
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
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
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
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isAmharic;
  const _EmptyState({required this.isAmharic});

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
            isAmharic ? 'ገና ምንም ፈተና የለም' : 'No assessments yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.darkText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isAmharic
                ? 'የመጀመሪያ ፈተናዎን ለመፍጠር ከታች ያለውን ቁልፍ ይጫኑ'
                : 'Tap the button below to create your first assessment',
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
  final bool isAmharic;
  const _AssessmentsTab({required this.isAmharic});

  @override
  Widget build(BuildContext context) {
    final assessments = context.watch<AssessmentProvider>();

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
                  isAmharic ? 'ፈተናዎች' : 'Assessments',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.createAssessment,
                  ),
                  icon: const Icon(Icons.add_circle),
                  color: AppTheme.primaryGreen,
                  iconSize: 32,
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
                  label: Text(isAmharic ? 'ሁሉም' : 'All'),
                  selected: true,
                  onSelected: (_) {},
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(isAmharic ? 'ንቁ' : 'Active'),
                  selected: false,
                  onSelected: (_) {},
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(isAmharic ? 'የተጠናቀቀ' : 'Completed'),
                  selected: false,
                  onSelected: (_) {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: assessments.assessments.isEmpty
                ? Center(
                    child: Text(
                      isAmharic ? 'ፈተና የለም' : 'No assessments',
                      style: TextStyle(color: AppTheme.lightText),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: assessments.assessments.length,
                    itemBuilder: (context, index) => AssessmentCard(
                      assessment: assessments.assessments[index],
                      isAmharic: isAmharic,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StudentsTab extends StatefulWidget {
  final bool isAmharic;
  const _StudentsTab({required this.isAmharic});

  @override
  State<_StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<_StudentsTab> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final students = context.watch<StudentProvider>();
    final isAmharic = widget.isAmharic;

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
                  isAmharic ? 'ተማሪዎች' : 'Students',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        AppRoutes.importExcel,
                      ),
                      icon: const Icon(Icons.upload_file),
                      tooltip: isAmharic ? 'ከ Excel አስገባ' : 'Import from Excel',
                    ),
                    IconButton(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        AppRoutes.addStudent,
                      ),
                      icon: const Icon(Icons.person_add),
                      tooltip: isAmharic ? 'ተማሪ ጨምር' : 'Add Student',
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
                hintText: isAmharic ? 'ተማሪ ፈልግ...' : 'Search students...',
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (q) {
                setState(() => _searchQuery = q.trim().toLowerCase());
              },
            ),
          ),
          const SizedBox(height: 12),
          // Class filter chips
          if (students.classNames.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  FilterChip(
                    label: Text(isAmharic ? 'ሁሉም' : 'All'),
                    selected: students.selectedClassName.isEmpty,
                    onSelected: (_) => students.setSelectedClass(''),
                  ),
                  ...students.classNames.map((c) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FilterChip(
                      label: Text(c),
                      selected: students.selectedClassName == c,
                      onSelected: (_) => students.setSelectedClass(c),
                    ),
                  )),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: students.students.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          isAmharic
                              ? 'ተማሪ የለም — Excel ይምጡ ወይም ያክሉ'
                              : 'No students — Import Excel or add manually',
                          style: TextStyle(color: AppTheme.lightText),
                        ),
                      ],
                    ),
                  )
                : Builder(
                    builder: (context) {
                      final filtered = _searchQuery.isEmpty
                          ? students.studentsByClass
                          : students.studentsByClass
                              .where((s) => s.fullName.toLowerCase().contains(_searchQuery))
                              .toList();
                      if (filtered.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                isAmharic
                                    ? '"$_searchQuery" አልተገኘም'
                                    : 'No match for "$_searchQuery"',
                                style: TextStyle(color: AppTheme.lightText),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final student = filtered[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
                              child: Text(
                                student.firstName[0],
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
                          );
                        },
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
  final bool isAmharic;
  const _SettingsTab({required this.isAmharic});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final locale = context.watch<LocaleProvider>();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            isAmharic ? 'ቅንብር' : 'Settings',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),

          // Profile section
          _SettingsSection(
            title: isAmharic ? 'መገለጫ' : 'Profile',
            children: [
              _SettingsTile(
                icon: Icons.person_outline,
                title: isAmharic ? 'ስም' : 'Name',
                subtitle: settings.teacherName.isEmpty
                    ? (isAmharic ? 'አልተዘጋጀም' : 'Not set')
                    : settings.teacherName,
                onTap: () => _editName(context, settings, isAmharic),
              ),
              _SettingsTile(
                icon: Icons.school_outlined,
                title: isAmharic ? 'ት/ቤት' : 'School',
                subtitle: settings.schoolName.isEmpty
                    ? (isAmharic ? 'አልተዘጋጀም' : 'Not set')
                    : settings.schoolName,
                onTap: () => _editSchool(context, settings, isAmharic),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Preferences
          _SettingsSection(
            title: isAmharic ? 'ምርጫዎች' : 'Preferences',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.language),
                title: Text(isAmharic ? 'አማርኛ' : 'Amharic'),
                subtitle: Text(isAmharic ? 'ወደ እንግሊዝኛ ቀይር' : 'Switch to Amharic'),
                value: locale.isAmharic,
                onChanged: (_) => locale.toggleLocale(),
                activeColor: AppTheme.primaryGreen,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.calendar_month),
                title: Text(isAmharic ? 'የኢትዮጵያ ዘመን አቆጣጠር' : 'Ethiopian Calendar'),
                subtitle: Text(
                  isAmharic
                      ? 'ቀኖናዊ ቀን ወደ ኢትዮጵያዊ ቀይር'
                      : 'Display dates in Ethiopian calendar',
                ),
                value: settings.useEthiopianCalendar,
                onChanged: (_) => settings.toggleEthiopianCalendar(),
                activeColor: AppTheme.primaryGreen,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.auto_fix_high),
                title: Text(isAmharic ? 'ስዕል ማሻሻል' : 'Auto-enhance Images'),
                value: settings.autoEnhanceImages,
                onChanged: (_) => settings.toggleAutoEnhance(),
                activeColor: AppTheme.primaryGreen,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.mic),
                title: Text(isAmharic ? 'የድምጽ አስተያየት' : 'Voice Feedback'),
                value: settings.voiceFeedbackEnabled,
                onChanged: (_) => settings.toggleVoiceFeedback(),
                activeColor: AppTheme.primaryGreen,
              ),
              _SettingsTile(
                icon: Icons.grading,
                title: isAmharic ? 'ነባሪ መለኪያ' : 'Default Rubric',
                subtitle: settings.defaultRubric == 'moe_national'
                    ? (isAmharic ? 'የMoE ብሔራዊ' : 'MoE National')
                    : settings.defaultRubric == 'university'
                        ? (isAmharic ? 'ዩኒቨርሲቲ' : 'University')
                        : (isAmharic ? 'የግል/ዓለም አቀፍ' : 'Private/International'),
                onTap: () => _selectRubric(context, settings, isAmharic),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Subscription
          _SettingsSection(
            title: isAmharic ? 'የደንበኝነት' : 'Subscription',
            children: [
              _SettingsTile(
                icon: settings.isSchoolMode ? Icons.business : Icons.person,
                title: settings.isSchoolMode
                    ? (isAmharic ? 'የት/ቤት አስተዳዳሪ' : 'School Admin')
                    : (isAmharic ? 'የግል መምህር' : 'Individual Teacher'),
                subtitle: isAmharic ? 'ለመቀየር ይንኩ' : 'Tap to change',
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.subscription,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // About
          _SettingsSection(
            title: isAmharic ? 'ስለ' : 'About',
            children: [
              _SettingsTile(
                icon: Icons.info_outline,
                title: 'EthioGrade',
                subtitle: 'v1.0.0',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _editName(BuildContext ctx, SettingsProvider s, bool isAm) {
    final controller = TextEditingController(text: s.teacherName);
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(isAm ? 'ስም ያስተካክሉ' : 'Edit Name'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: isAm ? 'የመምህር ስም' : 'Teacher Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.dispose();
              Navigator.pop(c);
            },
            child: Text(isAm ? 'ሰርዝ' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              s.updateSchoolInfo(teacher: controller.text);
              controller.dispose();
              Navigator.pop(c);
            },
            child: Text(isAm ? 'አስቀምጥ' : 'Save'),
          ),
        ],
      ),
    );
  }

  void _editSchool(BuildContext ctx, SettingsProvider s, bool isAm) {
    final controller = TextEditingController(text: s.schoolName);
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(isAm ? 'ት/ቤት ያስተካክሉ' : 'Edit School'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: isAm ? 'የት/ቤት ስም' : 'School Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.dispose();
              Navigator.pop(c);
            },
            child: Text(isAm ? 'ሰርዝ' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              s.updateSchoolInfo(name: controller.text);
              controller.dispose();
              Navigator.pop(c);
            },
            child: Text(isAm ? 'አስቀምጥ' : 'Save'),
          ),
        ],
      ),
    );
  }

  void _selectRubric(BuildContext ctx, SettingsProvider s, bool isAm) {
    showModalBottomSheet(
      context: ctx,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(isAm ? 'የMoE ብሔራዊ (0-100, 50% ማለፍ)' : 'MoE National (0-100, 50% pass)'),
              trailing: s.defaultRubric == 'moe_national'
                  ? const Icon(Icons.check, color: AppTheme.primaryGreen)
                  : null,
              onTap: () {
                s.setDefaultRubric('moe_national');
                Navigator.pop(c);
              },
            ),
            ListTile(
              title: Text(isAm ? 'የግል/ዓለም አቀፍ (60% ማለፍ)' : 'Private/International (60% pass)'),
              trailing: s.defaultRubric == 'private_international'
                  ? const Icon(Icons.check, color: AppTheme.primaryGreen)
                  : null,
              onTap: () {
                s.setDefaultRubric('private_international');
                Navigator.pop(c);
              },
            ),
            ListTile(
              title: Text(isAm ? 'ዩኒቨርሲቲ' : 'University'),
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
