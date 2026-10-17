import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/responsive.dart';
import '../../models/assessment.dart';
import '../../services/assessment_provider.dart';

/// Actions for the Quick Grade save/discard dialog.
enum QuickGradeAction { save, discard }

/// Shows the save/discard dialog for Quick Grade assessments.
Future<QuickGradeAction?> showQuickGradeDialog(BuildContext context) {
  return showDialog<QuickGradeAction>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Save this assessment?'),
      content: const Text('Save to reuse later and generate full reports.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, QuickGradeAction.discard),
          child: const Text('No, Discard'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, QuickGradeAction.save),
          child: const Text('Yes, Save'),
        ),
      ],
    ),
  );
}

/// Shows the rename bottom sheet so teacher can give Quick Grade a proper title.
/// Returns true if renamed and saved.
Future<bool?> showRenameSheet({
  required BuildContext context,
  required Assessment assessment,
  required ValueChanged<Assessment> onSaved,
}) async {
  final controller = TextEditingController(text: assessment.title);
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: ResponsiveLayout.horizontalPadding(ctx),
        right: ResponsiveLayout.horizontalPadding(ctx),
        top: 24,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 20),
          const Text(
            'Name this assessment',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Give it a name so you can find it later.',
            style: TextStyle(color: context.lightText, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Assessment name',
              hintText: 'e.g. Math Unit 1 Test',
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Keep as is'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final newTitle = controller.text.trim();
                    if (newTitle.isNotEmpty) {
                      final updated = Assessment(
                        id: assessment.id,
                        title: newTitle,
                        subject: assessment.subject,
                        rubricType: assessment.rubricType,
                        questions: assessment.questions,
                        status: assessment.status,
                        isQuickGrade: false,
                        createdAt: assessment.createdAt,
                        weightedScaleId: assessment.weightedScaleId,
                      );
                      await context.read<AssessmentProvider>().addAssessment(
                        updated,
                      );
                      onSaved(updated);
                    }
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  controller.dispose();

  if (confirmed == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Assessment saved'),
        backgroundColor: context.primaryGreen,
      ),
    );
  }

  return confirmed;
}
