import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../services/assessment_provider.dart';
import '../../services/locale_provider.dart';
import '../../services/settings_provider.dart';

class CreateAssessmentScreen extends StatefulWidget {
  const CreateAssessmentScreen({super.key});

  @override
  State<CreateAssessmentScreen> createState() => _CreateAssessmentScreenState();
}

class _CreateAssessmentScreenState extends State<CreateAssessmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _titleAmController = TextEditingController();
  final _subjectController = TextEditingController();
  final _classController = TextEditingController();

  String _rubricType = 'moe_national';
  final List<Question> _questions = [];
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _rubricType = context.read<SettingsProvider>().defaultRubric;
  }

  @override
  Widget build(BuildContext context) {
    final isAm = context.watch<LocaleProvider>().isAmharic;
    final provider = context.read<AssessmentProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(isAm ? 'አዲስ ፈተና' : 'New Assessment'),
        actions: [
          if (_questions.isNotEmpty)
            TextButton.icon(
              onPressed: _saveAssessment,
              icon: const Icon(Icons.check),
              label: Text(isAm ? 'ጨርስ' : 'Done'),
            ),
        ],
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 2) {
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
                    _currentStep == 2
                        ? (isAm ? 'ጨርስ' : 'Finish')
                        : (isAm ? 'ቀጣይ' : 'Next'),
                  ),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: details.onStepCancel,
                    child: Text(isAm ? 'ተመለስ' : 'Back'),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          // Step 1: Basic Info
          Step(
            title: Text(isAm ? 'መሰረታዊ መረጃ' : 'Basic Info'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0
                ? StepState.complete
                : StepState.indexed,
            content: Column(
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: isAm ? 'የፈተና ርዕስ' : 'Assessment Title',
                    hintText: isAm ? 'ምሳሌ: የ1ኛ ሙከራ' : 'e.g. Unit 1 Test',
                  ),
                  validator: (v) => v?.isEmpty == true
                      ? (isAm ? 'ርዕስ ያስፈልጋል' : 'Title required')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _titleAmController,
                  decoration: InputDecoration(
                    labelText: isAm ? 'ርዕስ (አማርኛ)' : 'Title (Amharic)',
                    hintText: isAm ? '' : 'Optional',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _subjectController,
                  decoration: InputDecoration(
                    labelText: isAm ? 'ለSubject' : 'Subject',
                    hintText: isAm ? 'ምሳሌ: ሂሳብ' : 'e.g. Mathematics',
                  ),
                  validator: (v) => v?.isEmpty == true
                      ? (isAm ? 'Subject ያስፈልጋል' : 'Subject required')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _classController,
                  decoration: InputDecoration(
                    labelText: isAm ? 'ክፍል' : 'Class',
                    hintText: isAm ? 'ምሳሌ: 5ኛ ክፍል "ሀ"' : 'e.g. Grade 5A',
                  ),
                ),
              ],
            ),
          ),

          // Step 2: Rubric
          Step(
            title: Text(isAm ? 'መለኪያ' : 'Rubric'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1
                ? StepState.complete
                : StepState.indexed,
            content: Column(
              children: [
                _rubricOption(
                  value: 'moe_national',
                  title: isAm ? 'የMoE ብሔራዊ' : 'MoE National',
                  desc: isAm ? '0-100, 50% ማለፍ' : '0-100, 50% pass mark',
                  scale: 'A+/A/A-/B+/B/B-/C+/C/C-/D/F',
                  isAmharic: isAm,
                ),
                const SizedBox(height: 12),
                _rubricOption(
                  value: 'private_international',
                  title: isAm ? 'የግል/ዓለም አቀፍ' : 'Private/International',
                  desc: isAm ? '60% ማለፍ' : '60% pass mark',
                  scale: 'A*/A/B/C/D/F',
                  isAmharic: isAm,
                ),
                const SizedBox(height: 12),
                _rubricOption(
                  value: 'university',
                  title: isAm ? 'ዩኒቨርሲቲ' : 'University',
                  desc: isAm ? '0-100, 50% ማለፍ' : '0-100, 50% pass mark',
                  scale: 'A/A-/B+/B/B-/C+/C/C-/D/F',
                  isAmharic: isAm,
                ),
              ],
            ),
          ),

          // Step 3: Questions
          Step(
            title: Text(isAm ? 'ጥያቄዎች' : 'Questions'),
            isActive: _currentStep >= 2,
            content: Column(
              children: [
                // Question type buttons
                Row(
                  children: [
                    Expanded(
                      child: _questionTypeButton(
                        icon: Icons.radio_button_checked,
                        label: isAm ? 'MCQ' : 'MCQ',
                        type: QuestionType.mcq,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _questionTypeButton(
                        icon: Icons.check_box,
                        label: isAm ? 'ት/ሐ' : 'T/F',
                        type: QuestionType.trueFalse,
                        color: AppTheme.info,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _questionTypeButton(
                        icon: Icons.short_text,
                        label: isAm ? 'አጭር' : 'Short',
                        type: QuestionType.shortAnswer,
                        color: AppTheme.warning,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _questionTypeButton(
                        icon: Icons.article,
                        label: isAm ? 'ግጥም' : 'Essay',
                        type: QuestionType.essay,
                        color: AppTheme.primaryRed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Question list
                if (_questions.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Center(
                      child: Text(
                        isAm
                            ? 'ጥያቄ ለመጨመር ከላይ ይጫኑ'
                            : 'Tap a question type above to add',
                        style: TextStyle(color: AppTheme.lightText),
                      ),
                    ),
                  )
                else
                  ..._questions.asMap().entries.map((entry) {
                    final i = entry.key;
                    final q = entry.value;
                    return _QuestionCard(
                      question: q,
                      index: i,
                      isAmharic: isAm,
                      onDelete: () => setState(() => _questions.removeAt(i)),
                      onEdit: () => _editQuestion(i, isAm),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rubricOption({
    required String value,
    required String title,
    required String desc,
    required String scale,
    required bool isAmharic,
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
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? AppTheme.primaryGreen : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(desc, style: TextStyle(fontSize: 12, color: AppTheme.lightText)),
                  Text(scale, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  void _addQuestion(QuestionType type) {
    setState(() {
      _questions.add(Question(
        number: _questions.length + 1,
        type: type,
        points: 1,
        correctAnswer: type == QuestionType.trueFalse ? 'True' : 'A',
        options: type == QuestionType.trueFalse
            ? ['True', 'False']
            : ['A', 'B', 'C', 'D', 'E'],
      ));
    });
  }

  void _editQuestion(int index, bool isAm) {
    final q = _questions[index];
    final answerController = TextEditingController(
      text: q.correctAnswer?.toString() ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(c).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${isAm ? 'ጥያቄ' : 'Question'} ${q.number}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Type: ${q.type.name}',
              style: TextStyle(color: AppTheme.lightText),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: answerController,
              decoration: InputDecoration(
                labelText: isAm ? 'ትክክለኛ መልስ' : 'Correct Answer',
                hintText: q.type == QuestionType.mcq
                    ? 'A, B, C, D, or E'
                    : q.type == QuestionType.trueFalse
                        ? 'True or False'
                        : 'Answer text',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: q.points.toString(),
              decoration: InputDecoration(
                labelText: isAm ? 'ነጥብ' : 'Points',
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final pts = double.tryParse(v);
                if (pts != null) {
                  _questions[index] = Question(
                    id: q.id,
                    number: q.number,
                    type: q.type,
                    text: q.text,
                    textAmharic: q.textAmharic,
                    points: pts,
                    options: q.options,
                    correctAnswer: answerController.text,
                    topicTag: q.topicTag,
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: q.topicTag,
              decoration: InputDecoration(
                labelText: isAm ? 'ርዕስ ምልክት' : 'Topic Tag',
                hintText: isAm ? 'ለትንተና' : 'For analytics',
              ),
              onChanged: (v) {
                _questions[index] = Question(
                  id: q.id,
                  number: q.number,
                  type: q.type,
                  text: q.text,
                  textAmharic: q.textAmharic,
                  points: q.points,
                  options: q.options,
                  correctAnswer: answerController.text,
                  topicTag: v,
                );
              },
            ),
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
                      textAmharic: q.textAmharic,
                      points: q.points,
                      options: q.options,
                      correctAnswer: answerController.text,
                      topicTag: q.topicTag,
                    );
                  });
                  Navigator.pop(c);
                },
                child: Text(isAm ? 'አስቀምጥ' : 'Save'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _saveAssessment() {
    if (_titleController.text.isEmpty || _subjectController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<LocaleProvider>().isAmharic
                ? 'ርዕስ እና Subject ያስፈልጋል'
                : 'Title and Subject are required',
          ),
        ),
      );
      return;
    }

    final assessment = Assessment(
      title: _titleController.text,
      titleAmharic: _titleAmController.text,
      subject: _subjectController.text,
      className: _classController.text,
      rubricType: _rubricType,
      questions: _questions,
      status: AssessmentStatus.active,
    );

    context.read<AssessmentProvider>().saveAssessment(assessment);

    Navigator.pushNamed(
      context,
      AppRoutes.answerKey,
      arguments: assessment,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleAmController.dispose();
    _subjectController.dispose();
    _classController.dispose();
    super.dispose();
  }
}

class _QuestionCard extends StatelessWidget {
  final Question question;
  final int index;
  final bool isAmharic;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _QuestionCard({
    required this.question,
    required this.index,
    required this.isAmharic,
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
    }[question.type]!;

    final typeLabel = {
      QuestionType.mcq: isAmharic ? 'MCQ' : 'MCQ',
      QuestionType.trueFalse: isAmharic ? 'ት/ሐ' : 'T/F',
      QuestionType.shortAnswer: isAmharic ? 'አጭር' : 'Short',
      QuestionType.essay: isAmharic ? 'ግጥም' : 'Essay',
    }[question.type]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: typeColor.withOpacity(0.1),
          child: Text(
            '${question.number}',
            style: TextStyle(
              color: typeColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                typeLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: typeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${question.points} ${isAmharic ? 'ነጥብ' : 'pts'}',
              style: TextStyle(fontSize: 12, color: AppTheme.lightText),
            ),
          ],
        ),
        subtitle: question.correctAnswer != null
            ? Text(
                '${isAmharic ? 'መልስ' : 'Answer'}: ${question.correctAnswer}',
                style: const TextStyle(fontSize: 12),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: onEdit,
              color: AppTheme.info,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onDelete,
              color: AppTheme.error,
            ),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}
