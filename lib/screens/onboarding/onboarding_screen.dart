import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/teacher.dart';
import '../../services/demo_data_service.dart';
import '../../services/class_provider.dart';
import '../../services/student_provider.dart';
import '../../services/assessment_provider.dart';
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
            // Skip — jump ahead to the setup page so the teacher still provides a name.
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: () {
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
            decoration: const InputDecoration(
              labelText: 'Subject (default)',
              prefixIcon: Icon(Icons.menu_book_outlined),
              hintText: 'e.g. Mathematics',
            ),
          ),
          const SizedBox(height: 8),
          if (settings.subjects.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final subject in settings.subjects)
                  FilterChip(
                    label: Text(subject),
                    selected: _selectedSubjects.any(
                      (s) => s.toLowerCase() == subject.toLowerCase(),
                    ),
                    onSelected: (sel) {
                      setState(() {
                        if (sel) {
                          if (!_selectedSubjects.any(
                            (s) => s.toLowerCase() == subject.toLowerCase(),
                          )) {
                            _selectedSubjects.add(subject);
                          }
                        } else {
                          _selectedSubjects.removeWhere(
                            (s) => s.toLowerCase() == subject.toLowerCase(),
                          );
                        }
                      });
                    },
                  ),
              ],
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

  void _addSubjectChip(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (_selectedSubjects.any(
      (s) => s.toLowerCase() == trimmed.toLowerCase(),
    )) {
      _subjectController.clear();
      return;
    }
    setState(() {
      _selectedSubjects.add(trimmed);
      _subjectController.clear();
    });
  }

  Future<void> _completeSetup() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _nameError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name to continue')),
      );
      return;
    }

    // Capture providers before awaiting so BuildContext isn't used across async gaps.
    final classProvider = context.read<ClassProvider>();
    final studentProvider = context.read<StudentProvider>();
    final assessmentProvider = context.read<AssessmentProvider>();
    final teacherProvider = context.read<TeacherProvider>();
    final navigator = Navigator.of(context);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_launch', false);
    await prefs.setString('language', 'en');

    // PII → encrypted Hive (not SharedPreferences)
    try {
      if (_nameController.text.isNotEmpty ||
          _schoolController.text.isNotEmpty) {
        final piiBox = Hive.isBoxOpen('settings_pii')
            ? Hive.box('settings_pii')
            : await Hive.openBox('settings_pii');
        if (_nameController.text.isNotEmpty) {
          await piiBox.put('teacher_name', _nameController.text);
        }
        if (_schoolController.text.isNotEmpty) {
          await piiBox.put('school_name', _schoolController.text);
        }
      }
    } catch (e) {
      debugPrint('Couldn\'t save onboarding details: $e');
    }

    // Create teacher record (subject + classes, more can be added later in Settings)
    try {
      final teachers = teacherProvider;
      final name = _nameController.text.trim();
      final hasExisting = teachers.teachers.any(
        (t) => t.name.toLowerCase() == name.toLowerCase(),
      );
      if (!hasExisting) {
        final subject = _subjectController.text.trim();
        final subjects = <String>[
          if (subject.isNotEmpty) subject,
          ..._selectedSubjects,
        ];
        final uniqueSubjects = <String>{};
        for (final s in subjects) {
          if (s.trim().isNotEmpty) uniqueSubjects.add(s.trim());
        }
        final teacher = Teacher(
          id: 'teacher-${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          role: 'teacher',
          subject: uniqueSubjects.firstOrNull ?? '',
          subjects: uniqueSubjects.isEmpty ? null : uniqueSubjects.toList(),
          classIds: _selectedClassIds,
        );
        await teachers.addTeacher(teacher);
      }
    } catch (e) {
      debugPrint('Couldn\'t create teacher record: $e');
    }

    // Seed demo data in debug builds so the dashboard isn't empty on first launch
    if (kDebugMode) {
      try {
        await DemoDataService.seed(
          classProvider: classProvider,
          studentProvider: studentProvider,
          assessmentProvider: assessmentProvider,
        );
      } catch (e) {
        debugPrint('Demo data seeding failed: $e');
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
