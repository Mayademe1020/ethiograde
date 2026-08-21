import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/assessment.dart';
import '../../models/class_info.dart';
import '../../services/assessment_provider.dart';
import '../../services/class_provider.dart';
import '../../services/settings_provider.dart';
import '../../screens/classes/create_class_sheet.dart';
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
  final _titleFocus = FocusNode();
  final _customQuestionController = TextEditingController();

  _StudentMode _studentMode = _StudentMode.classList;
  _AnswerKeyMode _answerKeyMode = _AnswerKeyMode.manual;
  String _selectedClassId = '';
  int _questionCount = 20;
  bool _titleError = false;
  String? _selectedSubject;

  @override
  void initState() {
    super.initState();
    _applyInitialMode(widget.initialMode ?? ExamDayStartMode.classList);
    _customQuestionController.text = _questionCount.toString();
    // Flag the title as required if the teacher taps away with it empty.
    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus &&
          _titleController.text.trim().isEmpty &&
          mounted) {
        setState(() => _titleError = true);
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocus.dispose();
    _customQuestionController.dispose();
    super.dispose();
  }

  /// Subjects available for the currently selected class, plus the teacher's
  /// global subject list. Selecting a class repopulates this list.
  List<String> get _subjectOptions {
    final settings = context.read<SettingsProvider>();
    final classes = context.read<ClassProvider>().classes;
    final selectedId = _effectiveSelectedClassId(classes);
    final set = <String>{};
    if (selectedId.isNotEmpty) {
      final cls = classes
          .cast<ClassInfo?>()
          .firstWhere((c) => c?.id == selectedId, orElse: () => null);
      if (cls != null && cls.subject.trim().isNotEmpty) {
        set.add(cls.subject.trim());
      }
    }
    for (final s in settings.subjects) {
      if (s.trim().isNotEmpty) set.add(s.trim());
    }
    return set.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final classes = context.watch<ClassProvider>().classes;
    final options = _subjectOptions;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Exam')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            // 1. Class — who gets these grades
            _buildSectionHeader(context, 'CLASS — WHO GETS THESE GRADES?'),
            const SizedBox(height: 10),
            if (classes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () async {
                    final created = await CreateClassSheet.show(context);
                    if (created != null && mounted) setState(() {});
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No classes yet — tap to create one before '
                            'this exam.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Create',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.9,
                children: [
                  for (final classInfo in classes)
                    _ClassTile(
                      selected: _studentMode == _StudentMode.classList &&
                          _effectiveSelectedClassId(classes) == classInfo.id,
                      title: classInfo.displayName,
                      subtitle: '${classInfo.studentIds.length} students',
                      onTap: () => setState(() {
                        _studentMode = _StudentMode.classList;
                        _selectedClassId = classInfo.id;
                        _applyClassDefaults(classInfo);
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 18),

            // 2. Subject — depends on the selected class
            _buildSectionHeader(context, 'SUBJECT'),
            const SizedBox(height: 10),
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Subject',
                prefixIcon: const Icon(Icons.menu_book_outlined),
                helperText: _selectedClassId.isNotEmpty
                    ? 'From the selected class'
                    : 'Your subjects (add more in Settings)',
                helperMaxLines: 2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: options.contains(_selectedSubject)
                      ? _selectedSubject
                      : null,
                  isExpanded: true,
                  hint: const Text('Select a subject'),
                  items: options
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(s)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedSubject = v),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 3. Exam title — directly below subject, required
            TextField(
              controller: _titleController,
              focusNode: _titleFocus,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() => _titleError = false),
              decoration: InputDecoration(
                labelText: 'Exam title *',
                hintText: 'e.g. Grade 8 Biology midterm',
                prefixIcon: const Icon(Icons.assignment_outlined),
                errorText: _titleError ? 'Enter a title for this exam' : null,
                errorStyle: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 4. Answer key method
            _buildSectionHeader(context, 'ANSWER KEY METHOD'),
            const SizedBox(height: 10),
            _ModeCard(
              selected: _answerKeyMode == _AnswerKeyMode.manual,
              icon: Icons.edit_note,
              title: 'Type Answers',
              subtitle: 'Tap correct answers directly',
              onTap: () =>
                  setState(() => _answerKeyMode = _AnswerKeyMode.manual),
            ),
            _ModeCard(
              selected: _answerKeyMode == _AnswerKeyMode.scanMaster,
              icon: Icons.document_scanner_outlined,
              title: 'Scan Answer Sheet',
              subtitle: 'Camera reads answers from paper',
              onTap: () =>
                  setState(() => _answerKeyMode = _AnswerKeyMode.scanMaster),
            ),
            const SizedBox(height: 18),

            // 5. Questions
            Text(
              'Questions',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
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
          ],
        ),
      ),
      bottomNavigationBar: _buildStickyCTA(),
    );
  }

  void _applyClassDefaults(ClassInfo classInfo) {
    // Selecting a class repopulates the subject list; default the subject
    // to the class's own subject when available.
    if (classInfo.subject.trim().isNotEmpty) {
      _selectedSubject = classInfo.subject.trim();
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: AppTheme.lightText,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildStickyCTA() {
    final rosterText = _selectedClassName ?? 'No class selected';
    final classes = context.read<ClassProvider>().classes;
    final hasTitle = _titleController.text.trim().isNotEmpty;
    final hasClass = _effectiveSelectedClassId(classes).isNotEmpty;
    final canProceed = hasTitle && hasClass;
    final hint = !hasClass
        ? 'Select a class first'
        : (!hasTitle ? 'Enter an exam title' : null);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 15,
                  color: AppTheme.lightText,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$_questionCount Qs · $rosterText',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.lightText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint,
                style: const TextStyle(
                  color: AppTheme.lightText,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: canProceed ? _createAssessment : _promptTitle,
              icon: Icon(_buttonIcon),
              label: Text(_buttonLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? get _selectedClassName {
    final classes = context.read<ClassProvider>().classes;
    final id = _effectiveSelectedClassId(classes);
    if (id.isEmpty) return null;
    for (final cls in classes) {
      if (cls.id == id) return cls.displayName;
    }
    return null;
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
        _studentMode = _StudentMode.classList;
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
    return '';
  }

  /// Require a title before proceeding; show a red field + alert if missing.
  void _promptTitle() {
    setState(() => _titleError = true);
    _titleFocus.requestFocus();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exam title required'),
        content: const Text(
          'Please enter a title for this exam before continuing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _createAssessment() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _promptTitle();
      return;
    }

    final classes = context.read<ClassProvider>().classes;
    final selectedClassId = _effectiveSelectedClassId(classes);

    if (selectedClassId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a class to grade')),
      );
      return;
    }

    final selectedClass = classes
        .cast<ClassInfo?>()
        .firstWhere((c) => c?.id == selectedClassId, orElse: () => null);
    final subjectText = _selectedSubject?.trim().isNotEmpty == true
        ? _selectedSubject!.trim()
        : (title.isNotEmpty ? 'Exam' : 'Exam');
    final defaultRubric = context.read<SettingsProvider>().defaultRubric;
    final assessment = Assessment(
      title: title,
      subject: subjectText,
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
        arguments: {
          'assessment': assessment,
          'scanMode': 'masterKey',
        },
      );
      return;
    }

    Navigator.pushNamed(
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
                  ? AppTheme.primaryGreen.withValues(alpha: 0.07)
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

class _ClassTile extends StatelessWidget {
  const _ClassTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primaryGreen : Colors.grey.shade700;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primaryGreen.withValues(alpha: 0.07)
                : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.primaryGreen : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.class_ : Icons.class_outlined,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.lightText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
