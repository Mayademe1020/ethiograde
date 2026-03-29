import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/scan_result.dart';
import '../../models/assessment.dart';
import '../../services/locale_provider.dart';
import '../../services/voice_service.dart';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAm = context.watch<LocaleProvider>().isAmharic;
    final results =
        ModalRoute.of(context)?.settings.arguments as List<ScanResult>? ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(isAm ? 'ውጤቶችን ይገምግሙ' : 'Review Results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => _showSortOptions(context, isAm),
          ),
        ],
      ),
      body: results.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    isAm ? 'ውጤት የለም' : 'No results to review',
                    style: TextStyle(color: AppTheme.lightText, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final result = results[index];
                return _ResultCard(
                  result: result,
                  isAmharic: isAm,
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/review/side-by-side',
                    arguments: result,
                  ),
                );
              },
            ),
    );
  }

  void _showSortOptions(BuildContext context, bool isAm) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.arrow_downward),
              title: Text(isAm ? 'ከዝቅተኛ ወደ ከፍተኛ' : 'Lowest to Highest'),
              onTap: () => Navigator.pop(c),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: Text(isAm ? 'ከከፍተኛ ወደ ዝቅተኛ' : 'Highest to Lowest'),
              onTap: () => Navigator.pop(c),
            ),
            ListTile(
              leading: const Icon(Icons.warning),
              title: Text(isAm ? 'ማረሚያ የሚያስፈልጉ' : 'Needs Review First'),
              onTap: () => Navigator.pop(c),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ScanResult result;
  final bool isAmharic;
  final VoidCallback onTap;

  const _ResultCard({
    required this.result,
    required this.isAmharic,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final passMark = 50;
    final passed = result.percentage >= passMark;
    final needsReview = result.needsReview;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Student avatar
                  CircleAvatar(
                    backgroundColor: passed
                        ? AppTheme.primaryGreen.withOpacity(0.1)
                        : AppTheme.primaryRed.withOpacity(0.1),
                    child: Text(
                      result.studentName.isNotEmpty
                          ? result.studentName[0]
                          : '?',
                      style: TextStyle(
                        color: passed
                            ? AppTheme.primaryGreen
                            : AppTheme.primaryRed,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.studentName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        if (needsReview)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isAmharic ? 'ማረሚያ ያስፈልጋል' : 'Needs Review',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Score badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: passed
                          ? AppTheme.primaryGreen.withOpacity(0.1)
                          : AppTheme.primaryRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${result.percentage.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: passed
                                ? AppTheme.primaryGreen
                                : AppTheme.primaryRed,
                          ),
                        ),
                        Text(
                          result.grade,
                          style: TextStyle(
                            fontSize: 12,
                            color: passed
                                ? AppTheme.primaryGreen
                                : AppTheme.primaryRed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Answer summary
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: result.answers.map((a) {
                  return Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: a.isCorrect
                          ? AppTheme.primaryGreen.withOpacity(0.15)
                          : a.detectedAnswer == '[MISSING]'
                              ? Colors.grey.shade200
                              : AppTheme.primaryRed.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: a.isCorrect
                            ? AppTheme.primaryGreen
                            : a.detectedAnswer == '[MISSING]'
                                ? Colors.grey
                                : AppTheme.primaryRed,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${a.questionNumber}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: a.isCorrect
                              ? AppTheme.primaryGreen
                              : a.detectedAnswer == '[MISSING]'
                                  ? Colors.grey
                                  : AppTheme.primaryRed,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${result.totalScore.toInt()}/${result.maxScore.toInt()}',
                    style: TextStyle(
                      color: AppTheme.lightText,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${isAmharic ? 'መተማመን' : 'Confidence'}: ${(result.confidence * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: AppTheme.lightText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──── Side-by-Side Review ────

class SideBySideReview extends StatefulWidget {
  const SideBySideReview({super.key});

  @override
  State<SideBySideReview> createState() => _SideBySideReviewState();
}

class _SideBySideReviewState extends State<SideBySideReview> {
  final VoiceService _voice = VoiceService();
  final TextEditingController _commentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final isAm = context.watch<LocaleProvider>().isAmharic;
    final result =
        ModalRoute.of(context)?.settings.arguments as ScanResult? ??
            ScanResult(
              assessmentId: '',
              studentId: '',
              studentName: 'Unknown',
              imagePath: '',
            );

    return Scaffold(
      appBar: AppBar(
        title: Text(result.studentName),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic),
            onPressed: () => _recordVoiceNote(isAm),
            tooltip: isAm ? 'የድምጽ ማስታወሻ' : 'Voice Note',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Score summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryGreen.withOpacity(0.1),
                    AppTheme.primaryGreen.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ScoreItem(
                    label: isAm ? 'ውጤት' : 'Score',
                    value: '${result.totalScore.toInt()}/${result.maxScore.toInt()}',
                  ),
                  _ScoreItem(
                    label: '%',
                    value: '${result.percentage.toStringAsFixed(1)}%',
                  ),
                  _ScoreItem(
                    label: isAm ? 'ደረጃ' : 'Grade',
                    value: result.grade,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Image preview
            if (result.imagePath.isNotEmpty)
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(result.imagePath),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Answer table
            Text(
              isAm ? 'በጥያቄ ውጤት' : 'Question-by-Question',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...result.answers.map((answer) => _AnswerTile(
              answer: answer,
              isAmharic: isAm,
              onOverride: () => _overrideScore(answer, isAm),
            )),

            const SizedBox(height: 16),

            // Comment section
            Text(
              isAm ? 'አስተያየት' : 'Comment',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: isAm
                    ? 'የተማሪ አስተያየት ይጻፉ...'
                    : 'Write feedback for this student...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.mic),
                  onPressed: () => _recordVoiceNote(isAm),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Voice note indicator
            if (result.voiceNotePath != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: AppTheme.info),
                    const SizedBox(width: 8),
                    Text(
                      isAm ? 'የድምጽ ማስታወሻ ተቀምጧል' : 'Voice note recorded',
                      style: const TextStyle(color: AppTheme.info),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // TODO: Re-scan this paper
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: Text(isAm ? 'እንደገና ስል' : 'Re-Scan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Save and mark as reviewed
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check),
                    label: Text(isAm ? 'አረጋግጥ' : 'Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _overrideScore(AnswerMatch answer, bool isAm) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${isAm ? 'ጥያቄ' : 'Question'} ${answer.questionNumber}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text('${isAm ? 'የተገኘ' : 'Detected'}: ${answer.detectedAnswer}'),
              Text('${isAm ? 'ትክክል' : 'Correct'}: ${answer.correctAnswer}'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        // Mark as correct
                        Navigator.pop(c);
                      },
                      child: Text(isAm ? 'ትክክል ነው' : 'Mark Correct'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Mark as incorrect
                        Navigator.pop(c);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryRed,
                      ),
                      child: Text(isAm ? 'ስህተት ነው' : 'Mark Wrong'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _recordVoiceNote(bool isAm) async {
    if (_voice.isRecording) {
      final path = await _voice.stopRecording();
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAm ? 'የድምጽ ማስታወሻ ተቀምጧል' : 'Voice note saved'),
          ),
        );
      }
    } else {
      await _voice.startRecording();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAm ? 'በመቅዳት ላይ...' : 'Recording...'),
          ),
        );
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
}

class _ScoreItem extends StatelessWidget {
  final String label;
  final String value;
  const _ScoreItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppTheme.lightText),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _AnswerTile extends StatelessWidget {
  final AnswerMatch answer;
  final bool isAmharic;
  final VoidCallback onOverride;

  const _AnswerTile({
    required this.answer,
    required this.isAmharic,
    required this.onOverride,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: answer.isCorrect
              ? AppTheme.primaryGreen.withOpacity(0.1)
              : AppTheme.primaryRed.withOpacity(0.1),
          child: Text(
            '${answer.questionNumber}',
            style: TextStyle(
              color: answer.isCorrect
                  ? AppTheme.primaryGreen
                  : AppTheme.primaryRed,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Text(
              '${isAmharic ? 'ተገኘ' : 'Detected'}: ${answer.detectedAnswer}',
              style: TextStyle(
                color: answer.isCorrect
                    ? AppTheme.darkText
                    : AppTheme.primaryRed,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${isAmharic ? 'ትክክል' : 'Correct'}: ${answer.correctAnswer}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${answer.score.toInt()}/${answer.maxScore.toInt()}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: onOverride,
            ),
          ],
        ),
      ),
    );
  }
}
