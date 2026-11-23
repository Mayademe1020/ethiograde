import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/proof_vault_entry.dart';
import '../../services/proof_vault_service.dart';

/// Digital Proof Vault Inspector Screen (የማስረጃ ማዕከል)
///
/// Visualizes the recorded bubble densities, detected answers, and SHA-256 seal
/// for a student's graded paper. Serves as undeniable proof against post-grading
/// alterations or student/parent grade disputes.
class ProofVaultInspectorScreen extends StatelessWidget {
  final ProofVaultEntry entry;

  const ProofVaultInspectorScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final isValid = entry.verifyIntegrity();
    final sortedQuestions = entry.bubbleDensities.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Proof Vault (የማስረጃ ማዕከል)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Evidence Certificate Card
            Card(
              color: isValid ? AppTheme.successContainer.withValues(alpha: 0.3) : AppTheme.errorContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: BorderSide(
                  color: isValid ? AppTheme.success : AppTheme.error,
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isValid ? Icons.verified : Icons.warning_amber_rounded,
                          color: isValid ? AppTheme.success : AppTheme.error,
                          size: 28,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isValid ? 'UNALTERABLE DIGITAL EVIDENCE' : 'HASH MISMATCH / TAMPER DETECTED',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isValid ? AppTheme.success : AppTheme.error,
                                ),
                              ),
                              Text(
                                'Recorded: ${entry.scannedAt.toLocal().toString().substring(0, 16)}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    _metaRow('Student Name', entry.studentName),
                    _metaRow('Student ID', entry.studentId),
                    _metaRow('Total Score', '${entry.totalScore.toStringAsFixed(1)} pts'),
                    const SizedBox(height: 6),
                    Text(
                      'SHA-256 Hash: ${entry.integrityHash.substring(0, 16)}...${entry.integrityHash.substring(entry.integrityHash.length - 8)}',
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              'Recorded Bubble Density Vectors (የተቀረፁ ጥቁረቶች)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Shows optical darkness measured at time of initial scan before paper return.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: AppSpacing.md),

            // Question Density Breakdown
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sortedQuestions.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final qNum = sortedQuestions[index];
                final densities = entry.bubbleDensities[qNum] ?? {};
                final detected = entry.detectedAnswers[qNum] ?? '—';

                return Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Question $qNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Original Choice: $detected',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.primary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Options Density Bars
                      ...['A', 'B', 'C', 'D'].map((opt) {
                        final density = densities[opt] ?? 0.0;
                        final isPicked = opt == detected;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 20,
                                child: Text(
                                  opt,
                                  style: TextStyle(
                                    fontWeight: isPicked ? FontWeight.bold : FontWeight.normal,
                                    color: isPicked ? AppTheme.primary : null,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: density.clamp(0.0, 1.0),
                                    backgroundColor: Colors.grey.withValues(alpha: 0.15),
                                    color: isPicked ? AppTheme.primary : Colors.grey,
                                    minHeight: 10,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 40,
                                child: Text(
                                  '${(density * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isPicked ? FontWeight.bold : FontWeight.normal,
                                    color: isPicked ? AppTheme.primary : Colors.grey,
                                  ),
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
