import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/assessment.dart';
import '../../models/student.dart';
import '../../models/class_info.dart';
import '../../models/scan_result.dart';
import '../../services/assessment_provider.dart';
import '../../services/student_provider.dart';
import '../../services/class_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/scoring_service.dart';

/// Fast-Entry Continuous Assessment (CA) Screen (ፈጣን ማስገቢያ)
///
/// Features a persistent bottom numeric keypad (0–9, decimal, backspace, next)
/// with auto-advance down the student roster. Allows teachers to grade 60 students
/// on homework, quizzes, or lab practicals in under 60 seconds with one hand.
class CaFastEntryScreen extends StatefulWidget {
  final Assessment assessment;

  const CaFastEntryScreen({super.key, required this.assessment});

  @override
  State<CaFastEntryScreen> createState() => _CaFastEntryScreenState();
}

class _CaFastEntryScreenState extends State<CaFastEntryScreen> {
  List<Student> _students = [];
  int _currentIndex = 0;
  final Map<String, double> _scores = {};
  String _inputBuffer = '';
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  void _loadStudents() {
    final classProv = context.read<ClassProvider>();
    final studentProv = context.read<StudentProvider>();

    final matchingClass = widget.assessment.className.isNotEmpty
        ? classProv.classes.cast<ClassInfo?>().firstWhere(
            (c) => c?.displayName == widget.assessment.className,
            orElse: () => null)
        : null;

    if (matchingClass != null) {
      _students = matchingClass.studentIds
          .map(studentProv.getStudentById)
          .whereType<Student>()
          .toList();
    } else {
      _students = List.from(studentProv.students);
    }

    _students.sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  void _handleKeyTap(String key) {
    if (_students.isEmpty) return;

    setState(() {
      if (key == '⌫') {
        if (_inputBuffer.isNotEmpty) {
          _inputBuffer = _inputBuffer.substring(0, _inputBuffer.length - 1);
        }
      } else if (key == '.') {
        if (!_inputBuffer.contains('.')) {
          _inputBuffer = _inputBuffer.isEmpty ? '0.' : '$_inputBuffer.';
        }
      } else if (key == '✓') {
        _commitCurrentAndAdvance();
      } else {
        // Digit 0-9
        if (_inputBuffer.length < 5) {
          _inputBuffer += key;
        }
      }
    });
  }

  void _commitCurrentAndAdvance() {
    if (_students.isEmpty) return;
    final student = _students[_currentIndex];

    if (_inputBuffer.isNotEmpty) {
      final parsed = double.tryParse(_inputBuffer);
      if (parsed != null) {
        final capped = parsed > widget.assessment.maxScore ? widget.assessment.maxScore : parsed;
        _scores[student.id] = capped;
      }
    }

    _inputBuffer = '';

    if (_currentIndex < _students.length - 1) {
      _currentIndex++;
      _scrollToIndex(_currentIndex);
    }
  }

  void _selectStudent(int index) {
    setState(() {
      _currentIndex = index;
      _inputBuffer = '';
    });
  }

  void _scrollToIndex(int index) {
    if (_scrollController.hasClients) {
      final target = (index * 60.0).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _saveAllScores() async {
    const scoring = ScoringService();

    for (final student in _students) {
      final score = _scores[student.id] ?? 0.0;
      final percentage = scoring.calculatePercentage(
        totalScore: score,
        maxScore: widget.assessment.maxScore,
      );
      final grade = scoring.calculateGrade(percentage, widget.assessment.rubricType);

      final result = ScanResult(
        assessmentId: widget.assessment.id,
        studentId: student.id,
        studentName: student.fullName,
        imagePath: '',
        answers: [
          AnswerMatch(
            questionNumber: 1,
            detectedAnswer: score.toStringAsFixed(1),
            correctAnswer: '',
            isCorrect: score >= (widget.assessment.maxScore * 0.5),
            score: score,
            maxScore: widget.assessment.maxScore,
            confidence: 1.0,
            ocrRawText: '(continuous assessment entry)',
          ),
        ],
        totalScore: score,
        maxScore: widget.assessment.maxScore,
        percentage: percentage,
        grade: grade,
        status: ScanStatus.reviewed,
        confidence: 1.0,
        isManualEntry: true,
        metadata: {'entryMethod': 'ca_fast_entry'},
      );

      await HybridGradingService().saveScanResult(result);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_scores.length} scores saved successfully!'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentStudent = _students.isNotEmpty ? _students[_currentIndex] : null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.assessment.title, style: const TextStyle(fontSize: 16)),
            Text(
              'Max: ${widget.assessment.maxScore.toInt()} pts • ${_scores.length}/${_students.length} graded',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _scores.isEmpty ? null : _saveAllScores,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Current Student Spotlight Banner
          if (currentStudent != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              color: AppTheme.primaryContainer.withValues(alpha: 0.5),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.primary,
                    child: Text(
                      '${_currentIndex + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentStudent.fullName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          maxLines: 1,
                        ),
                        Text('Roll: ${currentStudent.rollNumber}', style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppTheme.primary, width: 1.5),
                    ),
                    child: Text(
                      _inputBuffer.isNotEmpty
                          ? _inputBuffer
                          : (_scores[currentStudent.id]?.toStringAsFixed(1) ?? '—'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Scrollable Student Roster
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              itemCount: _students.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final student = _students[index];
                final isSelected = index == _currentIndex;
                final score = _scores[student.id];

                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: AppTheme.primaryContainer.withValues(alpha: 0.25),
                  leading: Text(
                    '${index + 1}.',
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? AppTheme.primary : Colors.grey,
                    ),
                  ),
                  title: Text(
                    student.fullName,
                    style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: score != null
                          ? AppTheme.primary.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      score != null ? score.toStringAsFixed(1) : '—',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: score != null ? AppTheme.primary : Colors.grey,
                      ),
                    ),
                  ),
                  onTap: () => _selectStudent(index),
                );
              },
            ),
          ),

          // Persistent Custom Keypad
          _buildCustomKeypad(),
        ],
      ),
    );
  }

  Widget _buildCustomKeypad() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _keyRow(['1', '2', '3']),
              _keyRow(['4', '5', '6']),
              _keyRow(['7', '8', '9']),
              _keyRow(['.', '0', '⌫', '✓']),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyRow(List<String> keys) {
    return Row(
      children: keys.map((k) {
        final isConfirm = k == '✓';
        final isBackspace = k == '⌫';

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(2.5),
            child: Material(
              color: isConfirm
                  ? AppTheme.primary
                  : (isBackspace ? AppTheme.errorContainer : Theme.of(context).colorScheme.surfaceContainerHighest),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => _handleKeyTap(k),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  child: Text(
                    k,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isConfirm
                          ? Colors.white
                          : (isBackspace ? AppTheme.error : Theme.of(context).textTheme.bodyLarge?.color),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
