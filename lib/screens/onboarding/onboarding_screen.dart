import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/class_info.dart';
import '../../models/teacher.dart';
import '../../services/class_provider.dart';
import '../../services/teacher_provider.dart';
import '../../services/settings_provider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final _nameController = TextEditingController();
  final _schoolController = TextEditingController();
  final _subjectController = TextEditingController();
  final List<String> _selectedSubjects = [];
  final List<String> _selectedClassIds = [];
  int? _selectedGrade;
  bool _nameError = false;

  final List<_OnboardingPage> _pages = [
    _OnboardingPage(
      icon: Icons.document_scanner,
      titleEn: 'Scan & Grade',
      descEn:
          'Take a photo of any exam paper. Our AI reads answers and grades instantly — no bubble sheets needed.',
    ),
    _OnboardingPage(
      icon: Icons.offline_bolt,
      titleEn: '100% Offline',
      descEn:
          'Works without internet. Perfect for schools anywhere in Ethiopia.',
    ),
    _OnboardingPage(
      icon: Icons.edit_note,
      titleEn: 'Quick Enter',
      descEn:
          'Type scores directly for calculation-heavy subjects. No scanning needed — just enter and save.',
    ),
    _OnboardingPage(
      icon: Icons.assessment,
      titleEn: 'Track Grades',
      descEn:
          'Review class results, see per-question breakdowns, and manage your grading scale.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip — pre-fill the name so the teacher can finish quickly and add
            // subject/classes later in Settings.
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: () {
                  if (_nameController.text.trim().isEmpty) {
                    _nameController.text = 'Teacher';
                  }
                  _pageController.animateToPage(
                    _pages.length,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                child: Text(
                  'Skip',
                  style: TextStyle(color: context.lightText),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length + 1, // +1 for setup page
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  if (index == _pages.length) {
                    return _buildSetupPage();
                  }
                  return _buildPage(_pages[index]);
                },
              ),
            ),

            // Dots indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length + 1,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == i ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == i
                          ? context.primaryGreen
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom buttons
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: const Text('Back'),
                      ),
                    ),
                  if (_currentPage > 0) const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _currentPage == _pages.length
                          ? _completeSetup
                          : () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                      child: Text(
                        _currentPage == _pages.length
                            ? ('Get Started')
                            : ('Next'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: context.primaryGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(page.icon, size: 56, color: context.primaryGreen),
            ),
            const SizedBox(height: 32),
            Text(
              page.titleEn,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              page.descEn,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: context.lightText,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupPage() {
    final settings = context.watch<SettingsProvider>();
    final classes = context.watch<ClassProvider>().classes;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Welcome!',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Tell us about yourself',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: context.lightText),
          ),
          const SizedBox(height: 32),

          // Teacher name
          TextField(
            controller: _nameController,
            onChanged: (_) {
              if (_nameError) setState(() => _nameError = false);
            },
            decoration: InputDecoration(
              labelText: 'Your Name',
              prefixIcon: const Icon(Icons.person_outline),
              hintText: 'e.g. Abebe Tesfaye',
              errorText: _nameError ? 'Please enter your name' : null,
            ),
          ),
          const SizedBox(height: 16),

          // School name
          TextField(
            controller: _schoolController,
            decoration: const InputDecoration(
              labelText: 'School Name (optional)',
              prefixIcon: Icon(Icons.school_outlined),
              hintText: 'e.g. Bole Primary School',
            ),
          ),
          const SizedBox(height: 24),

          // Grade selector — Grades 1-12. A class is created for the chosen
          // grade so the teacher can scan/enter right away.
          Text(
            'Which grade do you teach?',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(12, (i) {
                final grade = i + 1;
                final selected = _selectedGrade == grade;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      'Grade $grade',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.normal,
                        color: selected ? Colors.white : null,
                      ),
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedGrade = grade),
                    selectedColor: AppTheme.primaryGreen,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(
                      color: selected
                          ? AppTheme.primaryGreen
                          : Colors.grey.shade400,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 24),

          // Subject — default + multiple
          Text(
            'What do you teach?',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _subjectController,
            textInputAction: TextInputAction.done,
            onSubmitted: _addSubjectChip,
            decoration: InputDecoration(
              labelText: 'Subject (default)',
              prefixIcon: const Icon(Icons.menu_book_outlined),
              hintText: 'e.g. Mathematics',
              suffixIcon: IconButton(
                tooltip: 'Add subject',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _addSubjectChip(_subjectController.text),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (settings.subjects.isNotEmpty) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final subject in settings.subjects)
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 6),
                      child: FilterChip(
                        label: Text(
                          subject,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _selectedSubjects.any(
                                  (s) =>
                                      s.toLowerCase() ==
                                      subject.toLowerCase(),
                                )
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                        selected: _selectedSubjects.any(
                          (s) => s.toLowerCase() == subject.toLowerCase(),
                        ),
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              if (!_selectedSubjects.any(
                                (s) =>
                                    s.toLowerCase() ==
                                    subject.toLowerCase(),
                              )) {
                                _selectedSubjects.add(subject);
                              }
                            } else {
                              _selectedSubjects.removeWhere(
                                (s) =>
                                    s.toLowerCase() ==
                                    subject.toLowerCase(),
                              );
                            }
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_selectedSubjects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final subject in _selectedSubjects)
                    Chip(
                      label: Text(subject),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () => setState(() {
                        _selectedSubjects.removeWhere(
                          (s) => s.toLowerCase() == subject.toLowerCase(),
                        );
                      }),
                    ),
                ],
              ),
            ),
          Text(
            'You can add more subjects and classes later in Settings.',
            style: TextStyle(color: context.lightText, fontSize: 12),
          ),
          const SizedBox(height: 24),

          // Class selection
          Text(
            'Classes you teach',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (classes.isEmpty)
            Text(
              'No classes yet — you can create them later in the Students tab.',
              style: TextStyle(color: context.lightText, fontSize: 12),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cls in classes)
                  FilterChip(
                    label: Text(cls.displayName),
                    selected: _selectedClassIds.contains(cls.id),
                    onSelected: (sel) {
                      setState(() {
                        if (sel) {
                          if (!_selectedClassIds.contains(cls.id)) {
                            _selectedClassIds.add(cls.id);
                          }
                        } else {
                          _selectedClassIds.remove(cls.id);
                        }
                      });
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _addSubjectChip(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final exists = _selectedSubjects.any(
      (s) => s.toLowerCase() == trimmed.toLowerCase(),
    );
    if (!exists) {
      // Persist new subjects to Settings so they appear in future selectors
      // and stay in sync with the teacher profile.
      try {
        await context.read<SettingsProvider>().addSubject(trimmed);
      } catch (e) {
        debugPrint("Couldn't save subject: $e");
      }
      setState(() => _selectedSubjects.add(trimmed));
    }
    _subjectController.clear();
  }

  Future<void> _completeSetup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name to continue')),
      );
      return;
    }
    setState(() => _nameError = false);

    final settings = context.read<SettingsProvider>();
    final classProvider = context.read<ClassProvider>();
    final teacherProvider = context.read<TeacherProvider>();
    final navigator = Navigator.of(context);

    // Mark onboarding complete so we never show it again.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_launch', false);

    final schoolName = _schoolController.text.trim();

    // Sync PII to Settings via the SettingsProvider (single source of truth).
    await settings.updateSchoolInfo(
      name: schoolName.isNotEmpty ? schoolName : null,
      teacher: name,
    );

    // Ensure academic year is set so starter class has one.
    final academicYear = settings.currentAcademicYear.isEmpty
        ? ''
        : settings.currentAcademicYear;

    // Collect all unique subjects (controller + selected chips).
    final subjectInput = _subjectController.text.trim();
    final allSubjects = <String>{};
    if (subjectInput.isNotEmpty) allSubjects.add(subjectInput);
    for (final s in _selectedSubjects) {
      if (s.trim().isNotEmpty) allSubjects.add(s.trim());
    }

    // Persist any new subjects to Settings so they appear in future selectors.
    for (final s in allSubjects) {
      if (!settings.subjects.any(
        (e) => e.toLowerCase() == s.toLowerCase(),
      )) {
        try {
          await settings.addSubject(s);
        } catch (e) {
          debugPrint('Couldn\'t save subject "$s": $e');
        }
      }
    }

    final subjectsList = [...allSubjects];
    final primarySubject = subjectsList.firstOrNull ?? '';

    // Create teacher record.
    Teacher? createdTeacher;
    try {
      final hasExisting = teacherProvider.teachers.any(
        (t) => t.name.toLowerCase() == name.toLowerCase(),
      );
      if (hasExisting) {
        createdTeacher = teacherProvider.teachers.firstWhere(
          (t) => t.name.toLowerCase() == name.toLowerCase(),
        );
        // Update the existing teacher's subjects + school.
        final updated = createdTeacher.copyWith(
          school: schoolName,
          subjects: subjectsList,
          classIds: [...createdTeacher.classIds, ..._selectedClassIds],
        );
        final result = await teacherProvider.updateTeacher(updated);
        if (result.success && mounted) {
          createdTeacher = result.data;
        }
      } else {
        final teacher = Teacher(
          name: name,
          school: schoolName,
          subject: primarySubject,
          subjects: subjectsList,
          classIds: [..._selectedClassIds],
        );
        final result = await teacherProvider.addTeacher(teacher);
        if (result.success && mounted) {
          createdTeacher = result.data;
        }
      }
    } catch (e) {
      debugPrint('Couldn\'t create/update teacher record: $e');
    }

    // Create a starter class if a grade was selected.
    final classIds = [..._selectedClassIds];
    if (_selectedGrade != null && createdTeacher != null) {
      final grade = _selectedGrade!;
      final className = 'Grade $grade';
      final existing = classProvider.classesForTeacher(createdTeacher.id);
      final hasClass = existing.any(
        (c) => c.grade == grade && c.subject.toLowerCase() == primarySubject.toLowerCase(),
      );
      if (!hasClass) {
        final starterClass = ClassInfo(
          name: className,
          school: schoolName,
          grade: grade,
          section: '',
          subject: primarySubject,
          studentIds: [],
          ownerId: createdTeacher.id,
          academicYear: academicYear,
        );
        final classResult = await classProvider.addClass(starterClass);
        if (classResult.success && classResult.data != null) {
          classIds.add(classResult.data!.id);
          classProvider.selectClass(classResult.data!.id);
        }
      }
    }

    // Update teacher's class list if we created a starter class.
    if (createdTeacher != null &&
        classIds.any((id) => !createdTeacher!.classIds.contains(id))) {
      try {
        final updated = createdTeacher.copyWith(
          classIds: [...{...createdTeacher.classIds, ...classIds}],
        );
        await teacherProvider.updateTeacher(updated);
      } catch (e) {
        debugPrint('Couldn\'t update teacher classIds: $e');
      }
    }

    if (mounted) {
      navigator.pushReplacementNamed(AppRoutes.dashboard);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _schoolController.dispose();
    _subjectController.dispose();
    super.dispose();
  }
}

class _OnboardingPage {
  final IconData icon;
  final String titleEn;
  final String descEn;

  _OnboardingPage({
    required this.icon,
    required this.titleEn,
    required this.descEn,
  });
}
