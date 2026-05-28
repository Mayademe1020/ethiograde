import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../config/constants.dart';
import '../../models/assessment.dart';
import '../../models/grading_scale.dart';
import '../../services/assessment_provider.dart';
import '../../services/class_provider.dart';
import '../../services/settings_provider.dart';
import '../../models/weighted_grade.dart';
import '../../services/weighted_grade_provider.dart';
import 'weighted_grade_setup_sheet.dart';

class CreateAssessmentScreen extends StatefulWidget {
  const CreateAssessmentScreen({super.key});

  @override
  State<CreateAssessmentScreen> createState() => _CreateAssessmentScreenState();
}

class _CreateAssessmentScreenState extends State<CreateAssessmentScreen> {
  final _titleController = TextEditingController();
  final _subjectController = TextEditingController();

  String _rubricType = 'moe_national';
  String _selectedClassId = '';
  WeightedGradeScale? _weightedScale;
  final List<Question> _questions = [];
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _rubricType = context.read<SettingsProvider>().defaultRubric;
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text('New Assessment'),
        actions: [
          if (_questions.isNotEmpty)
            TextButton.icon(
              onPressed: _saveAssessment,
              icon: const Icon(Icons.check),
              label: Text('Done')),
        ]),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 3) {
            setState(() => _currentStep++);
          } else {
            _saveAssessment();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep--);
          }
        },
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: details.onStepContinue,
                  child: Text(
                    _currentStep == 3
                        ? ('Finish')
                        : ('Next'))),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: details.onStepCancel,
                    child: Text('Back')),
                ],
              ]));
        },
        steps: [
          // Step 1: Basic Info
          Step(
            title: Text('Basic Info'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Assessment Title',
                    hintText: 'e.g. Unit 1 Test'),
                  validator: (v) => v?.isEmpty == true
                      ? ('Title required')
                      : null),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: InputDecoration(
                    hintText: 'Optional')),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _subjectController,
                  decoration: InputDecoration(
                    labelText: 'Subject',
                    hintText: 'e.g. Mathematics'),
                  validator: (v) => v?.isEmpty == true
                      ? ('Subject required')
                      : null,
                  onChanged: (_) => setState(() {}), // Rebuild for subject hint
                ),
                // Subject-aware flow hint
                if (_subjectHint != null) ...[
                  const SizedBox(height: 8),
                  _SubjectHintBanner(
                    hint: _subjectHint!,onQuickEnter: () => Navigator.pushReplacementNamed(
                      context,
                      AppRoutes.quickEnter)),
                ],
                const SizedBox(height: 12),
                // Class dropdown (optional)
                Builder(
                  builder: (context) {
                    final classes = context.watch<ClassProvider>().classes;
                    if (classes.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String>(
                        value: _selectedClassId.isEmpty
                            ? null
                            : _selectedClassId,
                        decoration: InputDecoration(
                          labelText: 'Class (optional)',
                          prefixIcon: const Icon(Icons.class_outlined)),
                        items: classes
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.displayName)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedClassId = v ?? '')));
                  }),
              ])),

          // Step 2: Rubric
          Step(
            title: Text('Rubric'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: Column(
              children: [
                // Built-in scales
                _rubricOption(
                  value: 'moe_national',
                  title: 'MoE National',
                  desc: '0-100, 50% pass mark',
                  scale: 'A+/A/A-/B+/B/B-/C+/C/C-/D/F'),
                const SizedBox(height: 12),
                _rubricOption(
                  value: 'private_international',
                  title: 'Private/International',
                  desc: '60% pass mark',
                  scale: 'A*/A/B/C/D/F'),
                const SizedBox(height: 12),
                _rubricOption(
                  value: 'university',
                  title: 'University',
                  desc: '0-100, 50% pass mark',
                  scale: 'A/A-/B+/B/B-/C+/C/C-/D/F'),

                // Custom scales
                ...context.watch<SettingsProvider>().customScales.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _rubricOption(
                      value: s.rubricKey,
                      title: s.name,
                      desc: 'Custom scale',
                      scale: s.ranges.map((r) => r.grade).join('/'),isCustom: true,
                      onEdit: () async {
                        final result = await Navigator.pushNamed(
                          context,
                          AppRoutes.gradingScaleEditor,
                          arguments: s);
                        if (result is GradingScale) {
                          setState(() => _rubricType = result.rubricKey);
                        }
                      }))),

                const SizedBox(height: 12),

                // Add custom scale button
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.pushNamed(
                      context,
                      AppRoutes.gradingScaleEditor);
                    if (result is GradingScale) {
                      setState(() => _rubricType = result.rubricKey);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: Text(
                    'Create Custom Scale'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryGreen,
                    side: BorderSide(color: AppTheme.primaryGreen.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12))),
                const SizedBox(height: 12),

              ])),

          // Step 3: Weighted Setup
          Step(
            title: Text(
              _weightedScale != null
                  ? 'Weights: ${_weightedScale!.components.map((c) => "${(c.weight * 100).toInt()}%").join("+")}'
                  : 'Weighted Setup'),
            isActive: _currentStep >= 2,
            state: _currentStep > 2
                ? StepState.complete
                : _weightedScale != null
                    ? StepState.complete
                    : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Combine assessments by weight (e.g. Quiz 20% + Midterm 30% + Final 50%)',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600])),
                const SizedBox(height: 16),

                // Show current configuration or prompt
                if (_weightedScale != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.info.withOpacity(0.3))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle, color: AppTheme.info, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Configured',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.info)),
                          ]),
                        const SizedBox(height: 12),
                        ...?_weightedScale?.components.map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(c.name),
                                Text(
                                  '${(c.weight * 100).toInt()}%',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              ]))),
                      ])),
                  const SizedBox(height: 12),
                ],

                // Configure button
                OutlinedButton.icon(
                  onPressed: () => _openWeightedSetup(),
                  icon: const Icon(Icons.balance),
                  label: Text(
                    _weightedScale != null
                        ? ('Edit Weights')
                        : ('Set Up Weights')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.info,
                    side: BorderSide(color: AppTheme.info.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 14))),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _weightedScale = null),
                  child: Text(
                    'Skip (single assessment only)',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13))),
              ])),

          // Step 4: Questions
          Step(
            title: Text('Questions'),
            isActive: _currentStep >= 3,
            content: Column(
              children: [
                // Question type buttons
                Row(
                  children: [
                    Expanded(
                      child: _questionTypeButton(
                        icon: Icons.radio_button_checked,
                        label: 'MCQ',
                        type: QuestionType.mcq,
                        color: AppTheme.primaryGreen)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _questionTypeButton(
                        icon: Icons.check_box,
                        label: 'T/F',
                        type: QuestionType.trueFalse,
                        color: AppTheme.info)),
                  ]),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _questionTypeButton(
                        icon: Icons.short_text,
                        label: 'Short',
                        type: QuestionType.shortAnswer,
                        color: AppTheme.warning)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _questionTypeButton(
                        icon: Icons.article,
                        label: 'Essay',
                        type: QuestionType.essay,
                        color: AppTheme.primaryRed)),
                  ]),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _questionTypeButton(
                        icon: Icons.compare_arrows,
                        label: 'Matching',
                        type: QuestionType.matching,
                        color: AppTheme.primaryGreen)),
                    const SizedBox(width: 8),
                    const Expanded(child: SizedBox()),
                  ]),
                const SizedBox(height: 16),

                // Question list
                if (_questions.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200)),
                    child: Center(
                      child: Text(
                        'Tap a question type above to add',
                        style: TextStyle(color: AppTheme.lightText))))
                else
                  ..._questions.asMap().entries.map((entry) {
                    final i = entry.key;
                    final q = entry.value;
                    return _QuestionCard(
                      question: q,
                      index: i,onDelete: () => setState(() => _questions.removeAt(i)),
                      onEdit: () => _editQuestion(i));
                  }),
              ])),
        ]));
  }

  Widget _rubricOption({
    required String value,
    required String title,
    required String desc,
    required String scale,bool isCustom = false,
    VoidCallback? onEdit,
  }) {
    final isSelected = _rubricType == value;
    return GestureDetector(
      onTap: () => setState(() => _rubricType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryGreen.withOpacity(0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryGreen : Colors.grey.shade200,
            width: isSelected ? 2 : 1)),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? AppTheme.primaryGreen : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                      if (isCustom && onEdit != null)
                        IconButton(
                          icon: const Icon(Icons.edit, size: 16),
                          onPressed: onEdit,
                          color: AppTheme.info,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints()),
                    ]),
                  Text(
                    desc,
                    style: TextStyle(fontSize: 12, color: AppTheme.lightText)),
                  Text(
                    scale,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace')),
                ])),
          ])));
  }

  Widget _questionTypeButton({
    required IconData icon,
    required String label,
    required QuestionType type,
    required Color color,
  }) {
    return OutlinedButton.icon(
      onPressed: () => _addQuestion(type),
      icon: Icon(icon, color: color, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.3)),
        padding: const EdgeInsets.symmetric(vertical: 12)));
  }

  /// Open the weighted grade setup sheet.
  void _openWeightedSetup() async {
    final scale = await WeightedGradeSetupSheet.show(
      context,
      classId: _selectedClassId);
    if (scale != null && mounted) {
      setState(() => _weightedScale = scale);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Weights set: ${scale.components.map((c) => "${c.name} ${(c.weight * 100).toInt()}%").join(" + ")}"),
          backgroundColor: AppTheme.primaryGreen));
    }
  }

  void _addQuestion(QuestionType type) {
    setState(() {
      _questions.add(
        Question(
          number: _questions.length + 1,
          type: type,
          points: 1,
          correctAnswer: type == QuestionType.trueFalse
              ? 'True'
              : type == QuestionType.matching
                  ? ''
                  : 'A',
          options: type == QuestionType.trueFalse
              ? ['True', 'False']
              : type == QuestionType.matching
                  ? []
                  : ['A', 'B', 'C', 'D', 'E']));
    });
  }

  void _editQuestion(int index) {
    final q = _questions[index];
    final answerController = TextEditingController(
      text: q.correctAnswer?.toString() ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(c).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${'Question'} ${q.number}',
              style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Type: ${q.type.name}',
              style: TextStyle(color: AppTheme.lightText)),
            const SizedBox(height: 16),
            TextFormField(
              controller: answerController,
              decoration: InputDecoration(
                labelText: 'Correct Answer',
                hintText: q.type == QuestionType.mcq
                    ? 'A, B, C, D, or E'
                    : q.type == QuestionType.trueFalse
                    ? 'True or False'
                    : 'Answer text')),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: q.points.toString(),
              decoration: InputDecoration(labelText: 'Points'),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final pts = double.tryParse(v);
                if (pts != null) {
                  _questions[index] = Question(
                    id: q.id,
                    number: q.number,
                    type: q.type,
                    text: q.text,
                    points: pts,
                    options: q.options,
                    correctAnswer: answerController.text,
                    topicTag: q.topicTag);
                }
              }),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: q.topicTag,
              decoration: InputDecoration(
                labelText: 'Topic Tag',
                hintText: 'For analytics'),
              onChanged: (v) {
                _questions[index] = Question(
                  id: q.id,
                  number: q.number,
                  type: q.type,
                  text: q.text,
                  points: q.points,
                  options: q.options,
                  correctAnswer: answerController.text,
                  topicTag: v);
              }),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _questions[index] = Question(
                      id: q.id,
                      number: q.number,
                      type: q.type,
                      text: q.text,
                      points: q.points,
                      options: q.options,
                      correctAnswer: answerController.text,
                      topicTag: q.topicTag);
                  });
                  Navigator.pop(c);
                },
                child: Text('Save'))),
            const SizedBox(height: 16),
          ])));
  }

  void _saveAssessment() async {
    if (_titleController.text.isEmpty || _subjectController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Title and Subject are required')));
      return;
    }

    final className = _selectedClassId.isNotEmpty
        ? (context
                  .read<ClassProvider>()
                  .getClassById(_selectedClassId)
                  ?.displayName ??
              '')
        : '';

    final assessment = Assessment(
      title: _titleController.text,
      subject: _subjectController.text,
      className: className,
      rubricType: _rubricType,
      questions: _questions,
      status: AssessmentStatus.active);

    // Save weighted scale if configured — keyed by assessment ID
    Assessment? finalAssessment;
    if (_weightedScale != null) {
      final scaleId = 'exam:${assessment.id}';

      // Populate assessmentIds on each component so computeForExam() can
      // find scan results. Each component references this assessment.
      final linkedComponents = _weightedScale!.components
          .map((c) => GradeComponent(
                name: c.name,
                weight: c.weight,
                assessmentIds: [assessment.id],
                dropLowest: c.dropLowest))
          .toList();

      final linkedScale = WeightedGradeScale(
        name: _weightedScale!.name,
        classId: _weightedScale!.classId,
        components: linkedComponents,
        rubricType: _weightedScale!.rubricType);

      await context.read<WeightedGradeProvider>().saveForExam(assessment.id, linkedScale);
      finalAssessment = assessment.copyWith(weightedScaleId: scaleId);
    }

    final saved = finalAssessment ?? assessment;
    context.read<AssessmentProvider>().saveAssessment(saved);

    Navigator.pushNamed(context, AppRoutes.answerKey, arguments: saved);
  }

  /// Returns a hint type based on the current subject field value.
  /// null = no hint, 'manual' = suggest Quick Enter, 'scan' = scanning works well.
  String? get _subjectHint {
    final subject = _subjectController.text.trim().toLowerCase();
    if (subject.isEmpty) return null;

    final manualSubjects = AppConstants.manualEntrySubjects.map(
      (s) => s.toLowerCase());
    final scanSubjects = AppConstants.scanFriendlySubjects.map(
      (s) => s.toLowerCase());

    for (final s in manualSubjects) {
      if (subject.contains(s)) return 'manual';
    }
    for (final s in scanSubjects) {
      if (subject.contains(s)) return 'scan';
    }
    return null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subjectController.dispose();
    super.dispose();
  }
}

class _QuestionCard extends StatelessWidget {
  final Question question;
  final int index;final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _QuestionCard({
    required this.question,
    required this.index,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final typeColor = {
      QuestionType.mcq: AppTheme.primaryGreen,
      QuestionType.trueFalse: AppTheme.info,
      QuestionType.shortAnswer: AppTheme.warning,
      QuestionType.essay: AppTheme.primaryRed,
      QuestionType.matching: AppTheme.primaryGreen,
    }[question.type]!;

    final typeLabel = {
      QuestionType.mcq: 'MCQ',
      QuestionType.trueFalse: 'T/F',
      QuestionType.shortAnswer: 'Short',
      QuestionType.essay: 'Essay',
      QuestionType.matching: 'Match',
    }[question.type]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: typeColor.withOpacity(0.1),
          child: Text(
            '${question.number}',
            style: TextStyle(color: typeColor, fontWeight: FontWeight.bold))),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4)),
              child: Text(
                typeLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: typeColor,
                  fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            Text(
              '${question.points} ${'pts'}',
              style: TextStyle(fontSize: 12, color: AppTheme.lightText)),
          ]),
        subtitle: question.correctAnswer != null
            ? Text(
                '${'Answer'}: ${question.correctAnswer}',
                style: const TextStyle(fontSize: 12))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: onEdit,
              color: AppTheme.info),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onDelete,
              color: AppTheme.error),
          ]),
        onTap: onEdit));
  }
}

/// Subject-aware flow hint banner.
///
/// Shows a suggestion when the teacher types a subject that's better
/// suited for Quick Enter (Math, Essay) or scanning (Biology, English).
class _SubjectHintBanner extends StatelessWidget {
  final String hint; // 'manual' or 'scan'
  final VoidCallback onQuickEnter;

  const _SubjectHintBanner({
    required this.hint,
    required this.onQuickEnter,
  });

  @override
  Widget build(BuildContext context) {
    final isManual = hint == 'manual';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isManual ? Colors.indigo : AppTheme.primaryGreen).withOpacity(
          0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isManual ? Colors.indigo : AppTheme.primaryGreen).withOpacity(
            0.2))),
      child: Row(
        children: [
          Icon(
            isManual ? Icons.edit_note : Icons.document_scanner,
            color: isManual ? Colors.indigo : AppTheme.primaryGreen,
            size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isManual
                      ? (AppConstants.manualSuggestionEn)
                      : (AppConstants.scanSuggestionEn),
                  style: const TextStyle(fontSize: 13)),
                if (isManual) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onQuickEnter,
                    child: Text(
                      '→ Switch to Quick Enter',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade700))),
                ],
              ])),
        ]));
  }
}
