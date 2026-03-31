import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../services/locale_provider.dart';
import '../../services/assessment_provider.dart';
import '../../services/settings_provider.dart';
import '../../services/ethiopian_calendar.dart';

class AssessmentCard extends StatelessWidget {
  final Assessment assessment;
  final bool isAmharic;
  final VoidCallback? onTap;

  const AssessmentCard({
    super.key,
    required this.assessment,
    required this.isAmharic,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = {
      AssessmentStatus.draft: Colors.grey,
      AssessmentStatus.active: AppTheme.primaryGreen,
      AssessmentStatus.grading: AppTheme.warning,
      AssessmentStatus.completed: AppTheme.info,
    }[assessment.status]!;

    final statusLabel = {
      AssessmentStatus.draft: isAmharic ? 'ረቂቅ' : 'Draft',
      AssessmentStatus.active: isAmharic ? 'ንቁ' : 'Active',
      AssessmentStatus.grading: isAmharic ? 'በመስጠት ላይ' : 'Grading',
      AssessmentStatus.completed: isAmharic ? 'ተጠናቋል' : 'Completed',
    }[assessment.status]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap ??
            () => Navigator.pushNamed(
                  context,
                  AppRoutes.answerKey,
                  arguments: assessment,
                ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAmharic && assessment.titleAmharic.isNotEmpty
                              ? assessment.titleAmharic
                              : assessment.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          assessment.subject,
                          style: TextStyle(
                            color: AppTheme.lightText,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.help_outline,
                    label: '${assessment.questionCount} ${isAmharic ? 'ጥያቄ' : 'Q'}',
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.star_outline,
                    label: '${assessment.maxScore.toInt()} ${isAmharic ? 'ነጥብ' : 'pts'}',
                  ),
                  const SizedBox(width: 8),
                  if (assessment.className.isNotEmpty)
                    _InfoChip(
                      icon: Icons.class_outlined,
                      label: assessment.className,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Question type breakdown
              Wrap(
                spacing: 6,
                children: [
                  if (assessment.mcqCount > 0)
                    _TypeChip(
                      label: 'MCQ ${assessment.mcqCount}',
                      color: AppTheme.primaryGreen,
                    ),
                  if (assessment.trueFalseCount > 0)
                    _TypeChip(
                      label: 'T/F ${assessment.trueFalseCount}',
                      color: AppTheme.info,
                    ),
                  if (assessment.shortAnswerCount > 0)
                    _TypeChip(
                      label: 'Short ${assessment.shortAnswerCount}',
                      color: AppTheme.warning,
                    ),
                  if (assessment.essayCount > 0)
                    _TypeChip(
                      label: 'Essay ${assessment.essayCount}',
                      color: AppTheme.primaryRed,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Created date
              Builder(builder: (context) {
                final useEth = context.watch<SettingsProvider>().useEthiopianCalendar;
                final dateStr = EthiopianCalendar.formatDate(
                  assessment.createdAt,
                  useEthiopian: useEth,
                  isAmharic: isAmharic,
                );
                return Text(
                  '${isAmharic ? 'የተፈጠረ' : 'Created'}: $dateStr',
                  style: TextStyle(fontSize: 11, color: AppTheme.lightText),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.lightText),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppTheme.lightText),
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final Color color;

  const _TypeChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
