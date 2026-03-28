import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../services/locale_provider.dart';
import '../../services/assessment_provider.dart';

class AnswerKeyScreen extends StatelessWidget {
  const AnswerKeyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAm = context.watch<LocaleProvider>().isAmharic;
    final assessment =
        ModalRoute.of(context)?.settings.arguments as Assessment? ??
            context.watch<AssessmentProvider>().currentAssessment;

    if (assessment == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(isAm ? 'ፈተና አልተመረጠም' : 'No assessment selected'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isAm ? 'የመልስ ቁልፍ' : 'Answer Key'),
        actions: [
          TextButton.icon(
            onPressed: () {
              context.read<AssessmentProvider>().saveAssessment(assessment);
              Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
            },
            icon: const Icon(Icons.check),
            label: Text(isAm ? 'ጨርስ' : 'Done'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Assessment info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assessment.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${assessment.subject} • ${assessment.questionCount} ${isAm ? 'ጥያቄዎች' : 'questions'} • ${assessment.maxScore} ${isAm ? 'ነጥብ' : 'pts'}',
                    style: TextStyle(color: AppTheme.lightText),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Answer key table
            Text(
              isAm ? 'የመልስ ቁልፍ' : 'Answer Key',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isAm
                  ? 'መልሶችን ለማረም ይንኩ'
                  : 'Tap answers to edit',
              style: TextStyle(color: AppTheme.lightText, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Question answer cards
            ...assessment.questions.map((q) => _AnswerKeyCard(
              question: q,
              isAmharic: isAm,
              onChanged: (correctAnswer) {
                // Update question answer
                final index = assessment.questions.indexOf(q);
                final updatedQuestions = List<Question>.from(assessment.questions);
                updatedQuestions[index] = Question(
                  id: q.id,
                  number: q.number,
                  type: q.type,
                  text: q.text,
                  textAmharic: q.textAmharic,
                  points: q.points,
                  options: q.options,
                  correctAnswer: correctAnswer,
                  topicTag: q.topicTag,
                  keywords: q.keywords,
                );
                context.read<AssessmentProvider>().saveAssessment(
                  assessment.copyWith(questions: updatedQuestions),
                );
              },
            )),

            const SizedBox(height: 24),

            // Next steps info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.info.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.info.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppTheme.info),
                      const SizedBox(width: 8),
                      Text(
                        isAm ? 'ቀጣይ ደረጃ' : 'Next Steps',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAm
                        ? '1. የተማሪዎች ወረቀት ይስተካከሉ\n'
                            '2. ካሜራ በመክፈት ፎቶ ያንሱ\n'
                            '3. ውጤት በራሱ ይሰጣል'
                        : '1. Prepare student papers\n'
                            '2. Open camera and scan\n'
                            '3. Results are graded automatically',
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        AppRoutes.camera,
                        arguments: assessment,
                      ),
                      icon: const Icon(Icons.camera_alt),
                      label: Text(isAm ? 'ስል ጀምር' : 'Start Scanning'),
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
}

class _AnswerKeyCard extends StatelessWidget {
  final Question question;
  final bool isAmharic;
  final Function(dynamic) onChanged;

  const _AnswerKeyCard({
    required this.question,
    required this.isAmharic,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final typeLabel = {
      QuestionType.mcq: isAmharic ? 'MCQ' : 'MCQ',
      QuestionType.trueFalse: isAmharic ? 'ት/ሐ' : 'T/F',
      QuestionType.shortAnswer: isAmharic ? 'አጭር' : 'Short',
      QuestionType.essay: isAmharic ? 'ግጥም' : 'Essay',
    }[question.type]!;

    final typeColor = {
      QuestionType.mcq: AppTheme.primaryGreen,
      QuestionType.trueFalse: AppTheme.info,
      QuestionType.shortAnswer: AppTheme.warning,
      QuestionType.essay: AppTheme.primaryRed,
    }[question.type]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Question number
            CircleAvatar(
              backgroundColor: typeColor.withOpacity(0.1),
              child: Text(
                '${question.number}',
                style: TextStyle(
                  color: typeColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Type and points
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: typeColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${question.points} ${isAmharic ? 'ነጥብ' : 'pts'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.lightText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Answer options
                  if (question.type == QuestionType.mcq)
                    Row(
                      children: question.options.map((opt) {
                        final isSelected =
                            question.correctAnswer == opt;
                        return GestureDetector(
                          onTap: () => onChanged(opt),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primaryGreen
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primaryGreen
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                opt,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : AppTheme.darkText,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                  if (question.type == QuestionType.trueFalse)
                    Row(
                      children: ['True', 'False'].map((opt) {
                        final isSelected =
                            question.correctAnswer == opt;
                        final label = opt == 'True'
                            ? (isAmharic ? 'እውነት' : 'True')
                            : (isAmharic ? 'ሐሰት' : 'False');
                        return GestureDetector(
                          onTap: () => onChanged(opt),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (opt == 'True'
                                      ? AppTheme.primaryGreen
                                      : AppTheme.primaryRed)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? (opt == 'True'
                                        ? AppTheme.primaryGreen
                                        : AppTheme.primaryRed)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : AppTheme.darkText,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                  if (question.type == QuestionType.shortAnswer ||
                      question.type == QuestionType.essay)
                    Text(
                      '${isAmharic ? 'መልስ' : 'Answer'}: ${question.correctAnswer ?? (isAmharic ? 'አልተዘጋጀም' : 'Not set')}',
                      style: TextStyle(
                        color: AppTheme.lightText,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),

            // Edit button
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _editAnswer(context),
            ),
          ],
        ),
      ),
    );
  }

  void _editAnswer(BuildContext context) {
    if (question.type == QuestionType.mcq ||
        question.type == QuestionType.trueFalse) {
      // Options already tappable
      return;
    }

    final ctrl = TextEditingController(
      text: question.correctAnswer?.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          '${isAmharic ? 'ጥያቄ' : 'Question'} ${question.number}',
        ),
        content: TextField(
          controller: ctrl,
          maxLines: question.type == QuestionType.essay ? 4 : 1,
          decoration: InputDecoration(
            labelText: isAmharic ? 'ትክክለኛ መልስ' : 'Correct Answer',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(isAmharic ? 'ሰርዝ' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              onChanged(ctrl.text);
              Navigator.pop(c);
            },
            child: Text(isAmharic ? 'አስቀምጥ' : 'Save'),
          ),
        ],
      ),
    );
  }
}
