import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/assessment.dart';
import '../../models/class_info.dart';
import '../../services/assessment_provider.dart';
import '../../services/class_provider.dart';
import '../../services/settings_provider.dart';
import '../../services/teacher_provider.dart';
import 'answer_key_screen.dart';

enum ExamDayStartMode { masterScan, noRoster, classList, manualKey }

enum _StudentMode { noRoster, classList }

enum _AnswerKeyMode { scanMaster, manual }

class ExamDayCreateScreen extends StatefulWidget {
  const ExamDayCreateScreen({super.key, this.initialMode});

  final ExamDayStartMode? initialMode;

  @override
  State<ExamDayCreateScreen> createState() => _ExamDayCreateScreenState();
}

class _ExamDayCreateScreenState extends State<ExamDayCreateScreen> {
  final _titleController = TextEditingController();
  final _subjectController = TextEditingController();
  final _customQuestionController = TextEditingController();

  _StudentMode _studentMode = _StudentMode.noRoster;
  _AnswerKeyMode _answerKeyMode = _AnswerKeyMode.scanMaster;
  String _selectedClassId = '';
  int _questionCount = 20;

  @override
  void initState() {
    super.initState();
    _applyInitialMode(widget.initialMode ?? ExamDayStartMode.masterScan);
    _customQuestionController.text = _questionCount.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final teacher = context.read<TeacherProvider>().activeTeacher;
      if (teacher != null && teacher.subject.isNotEmpty && _subjectController.text.isEmpty) {
        _subjectController.text = teacher.subject;
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subjectController.dispose();
    _customQuestionController.dispose();
    super.dispose();
  }

  void _applyInitialMode(ExamDayStartMode mode) {
    switch (mode) {
      case ExamDayStartMode.masterScan:
        _answerKeyMode = _AnswerKeyMode.scanMaster;
        _studentMode = _StudentMode.noRoster;
        break;
      case ExamDayStartMode.noRoster:
        _answerKeyMode = _AnswerKeyMode.scanMaster;
        _studentMode = _StudentMode.noRoster;
        break;
      case ExamDayStartMode.classList:
        _answerKeyMode = _AnswerKeyMode.scanMaster;
        _studentMode = _StudentMode.classList;
        break;
      case ExamDayStartMode.manualKey:
        _answerKeyMode = _AnswerKeyMode.manual;
        _studentMode = _StudentMode.noRoster;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final classes = context.watch<ClassProvider>().classes;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Exam')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            // 1. Exam title
            _TitleField(),
            const SizedBox(height: 12),
            // 2. Answer key mode
            _AnswerKeyModeCard(),
            const SizedBox(height: 18),
            // 3. Questions + Class
            _QuestionCountAndClassCard(classes: classes),
            // 4. Sticky CTA
            const SizedBox(height: 10),
            _StickyCTA(),
          ],
        ),
      ),
    );
  }

  Widget _TitleField() {
    return TextField(
      controller: _titleController,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Exam title',
        hintText: 'e.g. Grade 8 Biology midterm',
        prefixIcon: Icon(Icons.assignment_outlined),
      ),
    );
  }

  Widget _AnswerKeyModeCard() {
    return _ModeCard(
      selected: _answerKeyMode == _AnswerKeyMode.scanMaster,
      icon: Icons.document_scanner_outlined,
      title: 'Scan Answer Sheet',
      subtitle: 'Camera reads answers from paper',
      onTap: () => setState(() => _answerKeyMode = _AnswerKeyMode.scanMaster),
    );
  }

  Widget _QuestionCountAndClassCard({required List<ClassInfo> classes}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Questions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            ...[10, 20, 30, 50, 100].map((count) {
              final isActive = count == _questionCount;
              return FilledButton.icon(
                onPressed: () => setState(() => _questionCount = count),
                icon: Icon(
                  isActive ? Icons.check_circle : Icons.circle_outlined,
                  size: isActive ? 20 : 16,
                  color: isActive ? AppTheme.primaryGreen : AppTheme.lightText,
                ),
                label: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isActive ? AppTheme.primaryGreen : AppTheme.lightText,
                  ),
                ),
                style: FilledButton.styleFrom(minimumSize: const Size(50, 32)),
              );
            }),
            const SizedBox(width: 8),
            // No Roster toggle
            _ModeCard(
              selected: _studentMode == _StudentMode.noRoster,
              icon: Icons.group_off,
              title: 'No Roster',
              subtitle: 'Grade without student list',
              onTap: () => setState(() => _studentMode = _StudentMode.noRoster),
            ),
            SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _customQuestionController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Count',
                  prefixIcon: Icon(Icons.numbers),
                  isDense: true,
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null && parsed > 0 && parsed <= 200) {
                    setState(() => _questionCount = parsed);
                  }
                },
              ),
            ),
            if (classes.isNotEmpty)
              _ClassSelector(classes: classes),
          ],
        ),
      ],
    );
  }

  Widget _ClassSelector({required List<ClassInfo> classes}) {
    return Row(
      children: [
        Text('Class:', style: TextStyle(fontSize: 12, color: AppTheme.lightText)),
        const SizedBox(width: 8),
        ...classes.take(3).map((cls) {
          final isSelected = _selectedClassId == cls.id;
          return _ModeCard(
            selected: isSelected,
            icon: Icons.class_outlined,
            title: cls.displayName,
            subtitle: '${cls.studentIds.length} students',
            onTap: () => setState(() => _selectedClassId = cls.id),
          );
        }),
        if (classes.length > 3)
          _ModeCard(
            selected: _studentMode == _StudentMode.classList &&
                _effectiveSelectedClassId(classes) == classes.last.id,
            icon: Icons.more,
            title: 'Plus ${classes.length - 3}',
            subtitle: 'View all ${classes.length} classes',
            onTap: () => setState(() => _studentMode = _StudentMode.classList),
          ),
      ],
    );
  }

  Widget _StickyCTA() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 54,
        child: FilledButton.icon(
          onPressed: _createAssessment,
          icon: Icon(_answerKeyMode == _AnswerKeyMode.scanMaster
              ? Icons.document_scanner
              : Icons.edit_note),
          label: Text(
            _answerKeyMode == _AnswerKeyMode.scanMaster
                ? 'Continue to Scan'
                : 'Continue to Answer Key',
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  String _effectiveSelectedClassId(List<ClassInfo> classes) {
    if (_selectedClassId.isNotEmpty) return _selectedClassId;
    if (_studentMode == _StudentMode.classList && classes.length == 1) {
      return classes.single.id;
    }
    return '';
  }

  Future<void> _createAssessment() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exam title is required')),
      );
      return;
    }

    final classes = context.watch<ClassProvider>().classes;
    final selectedClassId = _effectiveSelectedClassId(classes);

    if (_studentMode == _StudentMode.classList && selectedClassId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Choose a class or use no-roster grading')),
      );
      return;
    }

    final selectedClass = selectedClassId.isEmpty
        ? null
        : classes.cast<ClassInfo?>().firstWhere(
            (classInfo) => classInfo?.id == selectedClassId,
            orElse: () => null,
          );
    final defaultRubric = context.read<SettingsProvider>().defaultRubric;

    final assessment = Assessment(
      title: title,
      subject: _subjectController.text.trim().isEmpty ? 'Exam' : _subjectController.text.trim(),
      className: selectedClass?.displayName ?? '',
      rubricType: defaultRubric,
      questions: _buildQuestions(),
      status: AssessmentStatus.active,
      isQuickGrade: _studentMode == _StudentMode.noRoster,
      settings: {
        'examDayMode': 'gradePapers',
        'studentMode': _studentMode.name,
        'answerKeyMode': _answerKeyMode.name,
        if (selectedClass != null) 'classId': selectedClass.id,
        'requiresBatchReview': true,
        'shortAnswerPolicy': 'detect-and-review',
      },
    );

    await context.read<AssessmentProvider>().saveAssessment(assessment);
    if (!mounted) return;

    if (_answerKeyMode == _AnswerKeyMode.scanMaster) {
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.camera,
        arguments: {'assessment': assessment, 'scanMode': 'masterKey'},
      );
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      AppRoutes.answerKey,
      arguments: AnswerKeyRouteArgs(assessment: assessment, returnToConfirmation: true),
    );
  }

  List<Question> _buildQuestions() {
    return List.generate(_questionCount, (i) {
      return Question(
        number: i + 1,
        type: QuestionType.mcq,
        text: 'Question ${i + 1}',
        points: 1,
        options: const ['A', 'B', 'C', 'D', 'E'],
        correctAnswer: '',
      );
    });
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primaryGreen : Colors.grey.shade700;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primaryGreen.withOpacity(0.07) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppTheme.primaryGreen : Colors.grey.shade300,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppTheme.lightText,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: AppTheme.primaryGreen),
              ],
            ),
          ),
        ),
      ),
    );
  }
}