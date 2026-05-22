import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/assessment.dart';
import '../../models/class_info.dart';
import '../../services/assessment_provider.dart';
import '../../services/class_provider.dart';
import '../../services/settings_provider.dart';

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
  bool _advancedOpen = false;
  bool _includeShortAnswer = false;
  bool _includeTrueFalse = false;

  static const _presets = [10, 20, 30, 50, 100];

  @override
  void initState() {
    super.initState();
    _applyInitialMode(widget.initialMode ?? ExamDayStartMode.masterScan);
    _customQuestionController.text = _questionCount.toString();
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
      appBar: AppBar(title: const Text('Grade papers')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text(
              'I have papers. I need grades.',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose how to make the answer key and whether to use a class list. The app creates the exam in the background.',
              style: TextStyle(color: AppTheme.lightText, height: 1.35),
            ),
            const SizedBox(height: 18),
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
            const SizedBox(height: 4),
            Text(
              'Choose how the correct answers will be created.',
              style: TextStyle(color: AppTheme.lightText, height: 1.35),
            ),
            const SizedBox(height: 10),
            _ModeCard(
              selected: _answerKeyMode == _AnswerKeyMode.scanMaster,
              icon: Icons.document_scanner_outlined,
              title: 'Scan master answer sheet',
              subtitle:
                  'Best for long exams. Scan the filled key first, confirm weak answers, then grade papers.',
              onTap: () =>
                  setState(() => _answerKeyMode = _AnswerKeyMode.scanMaster),
            ),
            _ModeCard(
              selected: _answerKeyMode == _AnswerKeyMode.manual,
              icon: Icons.edit_note,
              title: 'Enter answer key manually',
              subtitle:
                  'Use quick taps when the master sheet is not ready or scanning is not suitable.',
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._presets.map(
                  (count) => ChoiceChip(
                    label: Text('$count'),
                    selected: _questionCount == count,
                    onSelected: (_) => _setQuestionCount(count),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _customQuestionController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Custom',
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
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Student list',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _ModeCard(
              selected: _studentMode == _StudentMode.noRoster,
              icon: Icons.person_off_outlined,
              title: 'Grade without student list',
              subtitle:
                  'Start now as Paper 1, Paper 2, Paper 3. Names can be assigned after scanning.',
              onTap: () => setState(() => _studentMode = _StudentMode.noRoster),
            ),
            _ModeCard(
              selected: _studentMode == _StudentMode.classList,
              icon: Icons.groups_outlined,
              title: 'Grade with class list',
              subtitle:
                  'Use registered students and review missing, duplicate, and unassigned papers before saving.',
              onTap: () =>
                  setState(() => _studentMode = _StudentMode.classList),
            ),
            if (_studentMode == _StudentMode.classList) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: effectiveSelectedClassId.isEmpty
                    ? null
                    : effectiveSelectedClassId,
                decoration: const InputDecoration(
                  labelText: 'Class',
                  prefixIcon: Icon(Icons.class_outlined),
                ),
                items: classes
                    .map(
                      (classInfo) => DropdownMenuItem(
                        value: classInfo.id,
                        child: Text(classInfo.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _selectedClassId = value ?? ''),
              ),
            ],
            const SizedBox(height: 18),
            ExpansionTile(
              initiallyExpanded: _advancedOpen,
              onExpansionChanged: (open) =>
                  setState(() => _advancedOpen = open),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Advanced question types'),
              subtitle: const Text(
                'Short answers are detect-and-review. Essays stay manual.',
              ),
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include true/false questions'),
                  value: _includeTrueFalse,
                  onChanged: (value) =>
                      setState(() => _includeTrueFalse = value ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include short-answer review placeholders'),
                  subtitle: const Text(
                    'The app highlights them for teacher review instead of promising automatic grading.',
                  ),
                  value: _includeShortAnswer,
                  onChanged: (value) =>
                      setState(() => _includeShortAnswer = value ?? false),
                ),
              ],
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
        ? 'Continue to master scan'
        : 'Continue to answer key';
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

  void _setQuestionCount(int count) {
    setState(() {
      _questionCount = count;
      _customQuestionController.text = count.toString();
    });
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
      Navigator.pushNamed(
        context,
        AppRoutes.answerSheetSetup,
        arguments: assessment,
      );
      return;
    }

    Navigator.pushNamed(context, AppRoutes.answerKey, arguments: assessment);
  }

  List<Question> _buildQuestions() {
    final questions = <Question>[];
    final shortAnswerStart = _includeShortAnswer
        ? (_questionCount - (_questionCount * 0.1).ceil() + 1).clamp(
            1,
            _questionCount,
          )
        : _questionCount + 1;

    for (var i = 1; i <= _questionCount; i++) {
      final isShortAnswer = _includeShortAnswer && i >= shortAnswerStart;
      final isTrueFalse = _includeTrueFalse && !isShortAnswer && i % 5 == 0;
      questions.add(
        Question(
          number: i,
          type: isShortAnswer
              ? QuestionType.shortAnswer
              : isTrueFalse
              ? QuestionType.trueFalse
              : QuestionType.mcq,
          text: 'Question $i',
          points: 1,
          options: isTrueFalse
              ? const ['True', 'False']
              : isShortAnswer
              ? const []
              : const ['A', 'B', 'C', 'D', 'E'],
          correctAnswer: '',
        ),
      );
    }

    return questions;
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
