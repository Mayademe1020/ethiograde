import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/locale_provider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  String _selectedLanguage = 'en';
  final _nameController = TextEditingController();
  final _schoolController = TextEditingController();

  final List<_OnboardingPage> _pages = [
    _OnboardingPage(
      icon: Icons.document_scanner,
      titleEn: 'Scan & Grade',
      titleAm: 'ማሰስ እና ውጤት ስጥ',
      descEn: 'Take a photo of any exam paper. Our AI reads answers and grades instantly — no bubble sheets needed.',
      descAm: 'የፈተና ወረቀት ፎቶ ያንሱ። ቴክኖሎጂያችን መልሶችን በራሱ ያነባል እና ውጤት ይሰጣል።',
    ),
    _OnboardingPage(
      icon: Icons.language,
      titleEn: 'Amharic & English',
      titleAm: 'አማርኛ እና እንግሊዝኛ',
      descEn: 'Recognizes handwriting in both Amharic (ሀ/ለ/ሐ) and English (A/B/C). True/False and እውነት/ሐሰት supported.',
      descAm: 'በአማርኛ (ሀ/ለ/ሐ) እና በእንግሊዝኛ (A/B/C) የተጻፈን ያነባል። እውነት/ሐሰት ይደገፋል።',
    ),
    _OnboardingPage(
      icon: Icons.analytics,
      titleEn: 'Analytics & Reports',
      titleAm: 'ትንተና እና ሪፖርት',
      descEn: 'See class averages, weak topics, and generate PDF reports with your school logo.',
      descAm: 'የክፍል አማካይ፣ ድክመት ያለባቸው ርዕሶች፣ እና የት/ቤት አርማ ያለው PDF ሪፖርት ያግኙ።',
    ),
    _OnboardingPage(
      icon: Icons.offline_bolt,
      titleEn: '100% Offline',
      titleAm: '100% ያለኢንተርኔት',
      descEn: 'Works without internet. Perfect for schools anywhere in Ethiopia.',
      descAm: 'ያለኢንተርኔት ይሠራል። ለኢትዮጵያ ውስጥ ማናቸውም ት/ቤት ተስማሚ።',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    final isAm = locale.isAmharic;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _goToLastPage,
                child: Text(
                  isAm ? 'ዝለል' : 'Skip',
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
                    return _buildSetupPage(isAm);
                  }
                  return _buildPage(_pages[index], isAm);
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
                        child: Text(isAm ? 'ተመለስ' : 'Back'),
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
                            ? (isAm ? 'ጀምር' : 'Get Started')
                            : (isAm ? 'ቀጣይ' : 'Next'),
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

  Widget _buildPage(_OnboardingPage page, bool isAm) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              page.icon,
              size: 56,
              color: AppTheme.primaryGreen,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            isAm ? page.titleAm : page.titleEn,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            isAm ? page.descAm : page.descEn,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppTheme.lightText,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSetupPage(bool isAm) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            isAm ? 'እንኳን ደህና መጡ!' : 'Welcome!',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isAm
                ? 'የእርስዎን መረጃ ያስገቡ'
                : 'Tell us about yourself',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppTheme.lightText,
            ),
          ),
          const SizedBox(height: 32),

          // Language toggle
          Text(
            isAm ? 'ቋንቋ / Language' : 'Language',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _languageChip('English', 'en'),
              const SizedBox(width: 12),
              _languageChip('አማርኛ', 'am'),
            ],
          ),
          const SizedBox(height: 24),

          // Teacher name
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: isAm ? 'የመምህር ስም' : 'Your Name',
              prefixIcon: const Icon(Icons.person_outline),
              hintText: isAm ? 'ምሳሌ: አበበ ተስፋዬ' : 'e.g. Abebe Tesfaye',
            ),
          ),
          const SizedBox(height: 16),

          // School name
          TextField(
            controller: _schoolController,
            decoration: InputDecoration(
              labelText: isAm ? 'የት/ቤት ስም' : 'School Name (optional)',
              prefixIcon: const Icon(Icons.school_outlined),
              hintText: isAm ? 'ምሳሌ: ቡልቻ ት/ቤት' : 'e.g. Bole Primary School',
            ),
          ),
          const SizedBox(height: 24),

          // Subscription mode
          Text(
            isAm ? 'የአጠቃቀም ሁኔታ' : 'Mode',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _subscriptionOption(
            icon: Icons.person,
            titleEn: 'Individual Teacher',
            titleAm: 'የግል መምህር',
            descEn: 'Just me grading my classes',
            descAm: 'ክፍሎቼን ብቻ ልመል',
            value: 'individual',
          ),
          const SizedBox(height: 12),
          _subscriptionOption(
            icon: Icons.business,
            titleEn: 'School Admin',
            titleAm: 'የት/ቤት አስተዳዳሪ',
            descEn: 'Manage multiple teachers',
            descAm: 'ብዙ መምህራንን ማስተዳደር',
            value: 'school',
          ),
        ],
      ),
    );
  }

  Widget _languageChip(String label, String code) {
    final isSelected = _selectedLanguage == code;
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedLanguage = code);
          context.read<LocaleProvider>().setLocale(code);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryGreen : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.primaryGreen : Colors.grey.shade300,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppTheme.darkText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _subscriptionOption({
    required IconData icon,
    required String titleEn,
    required String titleAm,
    required String descEn,
    required String descAm,
    required String value,
  }) {
    final isAm = context.watch<LocaleProvider>().isAmharic;
    return Semantics(
      button: true,
      label: isAm ? titleAm : titleEn,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppTheme.primaryGreen),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAm ? titleAm : titleEn,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      isAm ? descAm : descEn,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.lightText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  void _goToLastPage() {
    _pageController.animateToPage(
      _pages.length,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _completeSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_launch', false);
    await prefs.setString('language', _selectedLanguage);

    if (_nameController.text.isNotEmpty) {
      await prefs.setString('teacher_name', _nameController.text);
    }
    if (_schoolController.text.isNotEmpty) {
      await prefs.setString('school_name', _schoolController.text);
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
  final String titleAm;
  final String descEn;
  final String descAm;

  _OnboardingPage({
    required this.icon,
    required this.titleEn,
    required this.titleAm,
    required this.descEn,
    required this.descAm,
  });
}
