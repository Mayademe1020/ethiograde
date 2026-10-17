import 'package:flutter/material.dart';
import '../../models/assessment.dart';

/// Assessment selector dropdown shown on camera screen.
class AssessmentSelector extends StatelessWidget {
  final List<Assessment> assessments;
  final Assessment? selectedAssessment;
  final ValueChanged<Assessment?> onChanged;

  const AssessmentSelector({
    super.key,
    required this.assessments,
    required this.selectedAssessment,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 100,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Assessment',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<Assessment>(
              dropdownColor: Colors.grey.shade900,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey.shade800,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              items: assessments
                  .where((a) => a.status == AssessmentStatus.active)
                  .map(
                    (a) => DropdownMenuItem(
                      value: a,
                      child: Text(
                        '${a.title} (${a.subject})',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
