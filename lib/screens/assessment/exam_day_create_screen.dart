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
    // Auto-fill subject from teacher profile (read after first frame)
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

  @override
  Widget build(BuildContext context) {
    final classes = context.watch<ClassProvider>().classes;
    final effectiveSelectedClassId = _effectiveSelectedClassId(classes);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Exam')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Exam title',
                hintText: 'e.g. Grade 8 Biology midterm',
                prefixIcon: Icon(Icons.assignment_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subjectController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Subject (optional)',
                hintText: 'e.g. Mathematics',
                prefixIcon: Icon(Icons.menu_book_outlined),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Answer key',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _ModeCard(
              selected: _answerKeyMode == _AnswerKeyMode.scanMaster,
              icon: Icons.document_scanner_outlined,
              title: 'Scan Answer Sheet',
              subtitle:
                  'Camera reads answers from paper',
              onTap: () =>
                  setState(() => _answerKeyMode = _AnswerKeyMode.scanMaster),
            ),
            _ModeCard(
              selected: _answerKeyMode == _AnswerKeyMode.manual,
              icon: Icons.edit_note,
              title: 'Type Answers',
              subtitle:
                  'Tap correct answers directly',
              onTap: () =>
                  setState(() => _answerKeyMode = _AnswerKeyMode.manual),
            ),
            const SizedBox(height: 18),
            Text(
              'Questions',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
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
            const SizedBox(height: 18),
            Text(
              'Class',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            // Quick Grading card (no class)
            _ModeCard(
              selected: _studentMode == _StudentMode.noRoster,
              icon: Icons.speed,
              title: 'Quick Grading',
              subtitle: 'Papers numbered automatically',
              onTap: () => setState(() {
                _studentMode = _StudentMode.noRoster;
                _selectedClassId = '';
              }),
            ),
            // Class cards
            for (final classInfo in classes)
              _ModeCard(
                selected: _studentMode == _StudentMode.classList &&
                    _effectiveSelectedClassId(classes) == classInfo.id,
                icon: Icons.class_outlined,
                title: classInfo.displayName,
                subtitle: '${classInfo.studentIds.length} students',
                onTap: () => setState(() {
                  _studentMode = _StudentMode.classList;
                  _selectedClassId = classInfo.id;
                }),
              ),
            if (classes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'No classes yet — create one in Students tab',
                  style: TextStyle(color: AppTheme.lightText, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton.icon(
            onPressed: _createAssessment,
            icon: Icon(_buttonIcon),
            label: Text(_buttonLabel),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }

  IconData get _buttonIcon {
    return _answerKeyMode == _AnswerKeyMode.scanMaster
        ? Icons.document_scanner
        : Icons.edit_note;
  }

  String get _buttonLabel {
    return _answerKeyMode == _AnswerKeyMode.scanMaster
        ? 'Continue to Scan'
        : 'Continue to Answer Key';
  }

  void _applyInitialMode(ExamDayStartMode mode) {
    switch (mode) {
      case ExamDayStartMode.masterScan:
        _answerKeyMode = _AnswerKeyMode.scanMaster;
        break;
      case ExamDayStartMode.noRoster:
        _studentMode = _StudentMode.noRoster;
        break;
      case ExamDayStartMode.classList:
        _studentMode = _StudentMode.classList;
        break;
      case ExamDayStartMode.manualKey:
        _answerKeyMode = _AnswerKeyMode.manual;
        break;
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Exam title is required')));
      return;
    }

    final classes = context.read<ClassProvider>().classes;
    final selectedClassId = _effectiveSelectedClassId(classes);

    if (_studentMode == _StudentMode.classList && selectedClassId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a class or use no-roster grading'),
        ),
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
      subject: _subjectController.text.trim().isEmpty
          ? 'Exam'
          : _subjectController.text.trim(),
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
      // Navigate directly to camera in master key mode
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.camera,
        arguments: {
          'assessment': assessment,
          'scanMode': 'masterKey',
        },
      );
      return;
    }

    // Manual answer key — go to answer key screen, then confirmation
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.answerKey,
      arguments: AnswerKeyRouteArgs(
        assessment: assessment,
        returnToConfirmation: true,
      ),
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
              color: selected
                  ? AppTheme.primaryGreen.withOpacity(0.07)
                  : Colors.white,
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
                        style: TextStyle(
                          color: AppTheme.lightText,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: AppTheme.primaryGreen),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
