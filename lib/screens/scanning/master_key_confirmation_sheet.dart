import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/responsive.dart';
import '../../models/assessment.dart';
import '../../services/coordinate_map_omr_service.dart';

/// Shows the master key confirmation bottom sheet.
/// Returns the confirmed answer key map, or null if rescanned/dismissed.
Future<Map<int, String>?> showMasterKeyConfirmation({
  required BuildContext context,
  required Assessment assessment,
  required CoordinateMapOmrResult omrResult,
}) {
  final objectiveQuestions = assessment.questions
      .where(
        (q) => q.type == QuestionType.mcq || q.type == QuestionType.trueFalse,
      )
      .toList(growable: false);
  final answerByQuestion = {
    for (final answer in omrResult.answers) answer.questionNumber: answer,
  };
  final draft = <int, String>{
    for (final answer in omrResult.answers)
      if (answer.detectedAnswer.isNotEmpty)
        answer.questionNumber: answer.detectedAnswer,
  };

  return showModalBottomSheet<Map<int, String>>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final missing = objectiveQuestions
              .where((question) => (draft[question.number] ?? '').isEmpty)
              .length;
          final weak = objectiveQuestions.where((question) {
            final scanned = answerByQuestion[question.number];
            return scanned != null &&
                scanned.detectedAnswer.isNotEmpty &&
                scanned.confidence < 0.6;
          }).length;
          final ready = objectiveQuestions.isNotEmpty && missing == 0;

          return SafeArea(
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.88,
              minChildSize: 0.58,
              maxChildSize: 0.96,
              builder: (context, controller) {
                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        ResponsiveLayout.horizontalPadding(context), 12,
                        ResponsiveLayout.horizontalPadding(context), 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: context.primaryGreen.withValues(alpha: 
                                    0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.document_scanner_outlined,
                                  color: context.primaryGreen,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Confirm Answer Key',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      missing == 0 && weak == 0
                                          ? 'Looks clean. Check once, then use it as the answer key.'
                                          : 'Only fix the highlighted answers. The rest can stay as detected.',
                                      style: TextStyle(
                                        color: context.lightText,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _MasterKeyStat(
                                  label: 'Detected',
                                  value:
                                      '${objectiveQuestions.length - missing}/${objectiveQuestions.length}',
                                  color: context.primaryGreen,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MasterKeyStat(
                                  label: 'Needs tap',
                                  value: '$missing',
                                  color: missing == 0
                                      ? context.primaryGreen
                                      : context.primaryRed,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MasterKeyStat(
                                  label: 'Weak',
                                  value: '$weak',
                                  color: weak == 0
                                      ? context.primaryGreen
                                      : context.warning,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: controller,
                        padding: EdgeInsets.fromLTRB(
                          ResponsiveLayout.horizontalPadding(context), 4,
                          ResponsiveLayout.horizontalPadding(context), 12,
                        ),
                        itemCount: objectiveQuestions.length,
                        itemBuilder: (context, index) {
                          final question = objectiveQuestions[index];
                          final scanned = answerByQuestion[question.number];
                          final selected = draft[question.number] ?? '';
                          final isMissing = selected.isEmpty;
                          final isWeak =
                              !isMissing &&
                              scanned != null &&
                              scanned.confidence < 0.6;
                          final choices =
                              question.type == QuestionType.trueFalse
                              ? const ['True', 'False']
                              : const ['A', 'B', 'C', 'D', 'E'];

                          return _MasterKeyAnswerRow(
                            questionNumber: question.number,
                            choices: choices,
                            selected: selected,
                            confidence: scanned?.confidence,
                            isMissing: isMissing,
                            isWeak: isWeak,
                            onSelected: (value) {
                              setSheetState(() {
                                draft[question.number] = value;
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        ResponsiveLayout.horizontalPadding(context), 12,
                        ResponsiveLayout.horizontalPadding(context), 16,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Rescan'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: ready
                                  ? () => Navigator.pop(
                                      ctx,
                                      Map<int, String>.from(draft),
                                    )
                                  : null,
                              icon: const Icon(Icons.check_circle_outline),
                              label: Text(
                                ready
                                    ? 'Use as answer key'
                                    : 'Fix $missing missing',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    },
  );
}

class _MasterKeyStat extends StatelessWidget {
  const _MasterKeyStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.lightText,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterKeyAnswerRow extends StatelessWidget {
  const _MasterKeyAnswerRow({
    required this.questionNumber,
    required this.choices,
    required this.selected,
    required this.isMissing,
    required this.isWeak,
    required this.onSelected,
    this.confidence,
  });

  final int questionNumber;
  final List<String> choices;
  final String selected;
  final bool isMissing;
  final bool isWeak;
  final double? confidence;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final statusColor = isMissing
        ? context.primaryRed
        : isWeak
        ? context.warning
        : context.primaryGreen;
    final statusText = isMissing
        ? 'Missing'
        : isWeak
        ? 'Check'
        : 'OK';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: isMissing || isWeak ? 0.08 : 0.035),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: statusColor.withValues(alpha: isMissing || isWeak ? 0.45 : 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$questionNumber',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Question $questionNumber',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  confidence == null
                      ? statusText
                      : '$statusText ${(confidence! * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: choices.map((choice) {
              final isSelected = selected == choice;
              return ChoiceChip(
                label: Text(choice),
                selected: isSelected,
                onSelected: (_) => onSelected(choice),
                selectedColor: context.primaryGreen.withValues(alpha: 0.18),
                labelStyle: TextStyle(
                  color: isSelected ? context.primaryGreen : context.darkText,
                  fontWeight: FontWeight.w800,
                ),
                side: BorderSide(
                  color: isSelected
                      ? context.primaryGreen
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
