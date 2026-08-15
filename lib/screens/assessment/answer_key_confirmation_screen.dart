import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';

/// Confirmation screen shown after answer key is set.
/// Displays the answer key and lets teacher confirm before scanning papers.
class AnswerKeyConfirmationScreen extends StatelessWidget {
  final Assessment assessment;

  const AnswerKeyConfirmationScreen({super.key, required this.assessment});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Answer Key Set'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: AppTheme.primaryGreen,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Your answer key:',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                assessment.title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: assessment.questions.length,
                  itemBuilder: (context, index) {
                    final q = assessment.questions[index];
                    final answer = q.correctAnswer?.toString() ?? '';
                    final isEmpty = answer.isEmpty;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: index.isEven
                            ? cs.surfaceContainerHighest.withValues(alpha: 0.3)
                            : null,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${q.number}.',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildAnswerChip(q, answer, isEmpty),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              q.text,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pushReplacementNamed(
                    context,
                    AppRoutes.camera,
                    arguments: {
                      'assessment': assessment,
                      'scanMode': 'batch',
                    },
                  );
                },
                icon: const Icon(Icons.document_scanner),
                label: const Text(
                  'Confirm & Start Scanning',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.edit),
                label: const Text('Edit Answers'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerChip(Question q, String answer, bool isEmpty) {
    if (isEmpty) {
      return Container(
        width: 32,
        height: 24,
        decoration: BoxDecoration(
          color: AppTheme.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: const Text(
          '?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.warning,
            fontSize: 13,
          ),
        ),
      );
    }

    switch (q.type) {
      case QuestionType.multiAnswer:
        final display = answer.replaceAll(',', '+');
        return Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF3A2650).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            display,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFFC5A3E8),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        );

      case QuestionType.shortAnswer:
      case QuestionType.essay:
        final parts = answer.split('|');
        final primary = parts.first;
        final altCount = parts.length - 1;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF5C3A1A).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Text(
                primary,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE8B07A),
                  fontSize: 11,
                ),
              ),
            ),
            if (altCount > 0)
              Text(
                '+$altCount alt',
                style: const TextStyle(fontSize: 8, color: AppTheme.lightText),
              ),
          ],
        );

      case QuestionType.matching:
        return Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF5C2040).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            answer,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFFE8A0B8),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        );

      default:
        return Container(
          width: 32,
          height: 24,
          decoration: BoxDecoration(
            color: AppTheme.primaryGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            answer.length > 3 ? '${answer.substring(0, 3)}..' : answer,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryGreen,
              fontSize: 13,
            ),
          ),
        );
    }
  }
}
