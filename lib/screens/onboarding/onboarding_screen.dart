import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/demo_data_service.dart';
import '../../services/class_provider.dart';
import '../../services/student_provider.dart';
import '../../services/assessment_provider.dart';

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
            // Skip button
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
                child: const Text(
                  'Skip',
                  style: TextStyle(color: AppTheme.lightText),
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
                          ? AppTheme.primaryGreen
                          : Colors.grey.shade300,
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
                color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(page.icon, size: 56, color: AppTheme.primaryGreen),
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
                color: AppTheme.lightText,
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
            ).textTheme.bodyLarge?.copyWith(color: AppTheme.lightText),
          ),
          const SizedBox(height: 32),

          // Teacher name
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Your Name',
              prefixIcon: Icon(Icons.person_outline),
              hintText: 'e.g. Abebe Tesfaye',
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
        ],
      ),
    );
  }

  Future<void> _completeSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_launch', false);
    await prefs.setString('language', 'en');

    // PII → encrypted Hive (not SharedPreferences)
    if (_nameController.text.isNotEmpty || _schoolController.text.isNotEmpty) {
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

    // Seed demo data in debug builds so the dashboard isn't empty on first launch
    if (mounted && kDebugMode) {
      await DemoDataService.seed(
        classProvider: context.read<ClassProvider>(),
        studentProvider: context.read<StudentProvider>(),
        assessmentProvider: context.read<AssessmentProvider>(),
      );
    }

    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _schoolController.dispose();
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
