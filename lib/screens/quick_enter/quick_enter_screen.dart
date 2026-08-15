import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../models/student.dart';
import '../../models/class_info.dart';
import '../../services/assessment_provider.dart';
import '../../services/student_provider.dart';
import '../../services/class_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/scoring_service.dart';

/// Quick Enter — manual score entry for non-OCR subjects.
///
/// Teacher selects an assessment, sees student list, taps scores per question.
/// Works for Math, Essay, or any subject where OCR can't grade.
class QuickEnterScreen extends StatefulWidget {
  const QuickEnterScreen({super.key});

  @override
  State<QuickEnterScreen> createState() => _QuickEnterScreenState();
}

class _QuickEnterScreenState extends State<QuickEnterScreen> {
  Assessment? _assessment;
  List<Student> _students = [];
  // studentId → questionNumber → score
  final Map<String, Map<int, double>> _scores = {};
  // studentId → ScanResult (built as scores are entered)
  final Map<String, ScanResult> _results = {};
  bool _isSaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_assessment == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Assessment) {
        _assessment = args;
        _loadStudents();
      }
    }
  }

  void _loadStudents() {
    if (_assessment == null) return;

    final classProv = context.read<ClassProvider>();
    final studentProv = context.read<StudentProvider>();

    // Try to find students linked to this assessment's class
    final matchingClass = _assessment!.className.isNotEmpty
        ? classProv.classes.cast<ClassInfo?>().firstWhere(
            (c) => c?.displayName == _assessment!.className,
            orElse: () => null)
        : null;

    if (matchingClass != null) {
      _students = matchingClass.studentIds
          .map(studentProv.getStudentById)
          .whereType<Student>()
          .toList();
    } else {
      // No class linked — show all students
      _students = List.from(studentProv.students);
    }

    // Sort by name
    _students.sort((a, b) => a.fullName.compareTo(b.fullName));

    // Initialize score maps
    for (final student in _students) {
      _scores[student.id] = {};
    }
  }

  /// Set score for a student's question.
  void _setScore(String studentId, int questionNumber, double score) {
    setState(() {
      _scores[studentId]![questionNumber] = score;
    });
  }

  /// Calculate and save ScanResult for a student.
  Future<void> _saveStudentScores(Student student) async {
    if (_assessment == null) return;

    const scoring = ScoringService();
    final studentScores = _scores[student.id] ?? {};
    final answers = <AnswerMatch>[];

    for (final question in _assessment!.questions) {
      final score = studentScores[question.number] ?? 0;
      final isCorrect = score >= question.points;

      answers.add(
        AnswerMatch(
          questionNumber: question.number,
          detectedAnswer: score.toStringAsFixed(1),
          correctAnswer: question.correctAnswer?.toString() ?? '',
          isCorrect: isCorrect,
          score: score,
          maxScore: question.points,
          confidence: 1.0, // Manual entry = 100% confidence
          ocrRawText: '(manual entry)'));
    }

    final totalScore = scoring.calculateTotalScore(answers);
    final maxScore = _assessment!.maxScore;
    final percentage = scoring.calculatePercentage(
      totalScore: totalScore,
      maxScore: maxScore);
    final grade = scoring.calculateGrade(percentage, _assessment!.rubricType);

    final result = ScanResult(
      assessmentId: _assessment!.id,
      studentId: student.id,
      studentName: student.fullName,
      imagePath: '',
      answers: answers,
      totalScore: totalScore,
      maxScore: maxScore,
      percentage: percentage,
      grade: grade,
      status: ScanStatus.reviewed,
      confidence: 1.0,
      isManualEntry: true,
      metadata: {'entryMethod': 'quick_enter'});

    // Save to Hive
    await HybridGradingService().saveScanResult(result);

    setState(() {
      _results[student.id] = result;
    });
  }

  /// Save all students at once.
  Future<void> _saveAll() async {
    setState(() => _isSaving = true);

    for (final student in _students) {
      await _saveStudentScores(student);
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_results.length} students saved'),
        backgroundColor: AppTheme.primaryGreen));
  }

  @override
  Widget build(BuildContext context) {

    if (_assessment == null) {
      // Show assessment picker
      return _AssessmentPicker(
        onSelected: (assessment) {
          setState(() {
            _assessment = assessment;
            _loadStudents();
          });
        });
    }

    final questions = _assessment!.questions;
    final savedCount = _results.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Enter'),
        actions: [
          if (savedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(
                  '$savedCount/${_students.length}',
                  style: const TextStyle(fontSize: 12)),
                backgroundColor: AppTheme.primaryGreen.withOpacity(0.1))),
        ]),
      body: _students.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 64,
                    color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text(
                    'No students found',
                    style: TextStyle(color: AppTheme.lightText)),
                  const SizedBox(height: 8),
                  const Text(
                    'Add students or link a class first',
                    style: TextStyle(color: AppTheme.lightText, fontSize: 12)),
                ]))
          : Column(
              children: [
                // Assessment info header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: AppTheme.primaryGreen.withOpacity(0.05),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit_note,
                        color: AppTheme.primaryGreen,
                        size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _assessment!.title,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text(
                        '${questions.length} ${'Qs'}',
                        style: const TextStyle(
                          color: AppTheme.lightText,
                          fontSize: 12)),
                    ])),

                // Score entry table
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: _buildScoreTable(questions)))),

                // Save all button
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveAll,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                            : const Icon(Icons.save),
                        label: Text(
                          _isSaving
                              ? ('Saving...')
                              : ('Save All')))))),
              ]));
  }

  Widget _buildScoreTable(List<Question> questions) {
    return Table(
      defaultColumnWidth: const FixedColumnWidth(60),
      border: TableBorder.all(color: Colors.grey.shade200, width: 0.5),
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(
            color: AppTheme.primaryGreen.withOpacity(0.05)),
          children: [
            const SizedBox(
              width: 150,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Student',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12)))),
            ...questions.map(
              (q) => SizedBox(
                width: 60,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    children: [
                      Text(
                        'Q${q.number}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                      Text(
                        '/${q.points.toInt()}',
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.lightText)),
                    ])))),
            const SizedBox(
              width: 70,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Total',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11)))),
          ]),
        // Student rows
        ..._students.map((student) {
          final studentScores = _scores[student.id] ?? {};
          final total = studentScores.values.fold(0.0, (s, v) => s + v);
          final maxTotal = questions.fold(0.0, (s, q) => s + q.points);
          final isSaved = _results.containsKey(student.id);

          return TableRow(
            decoration: BoxDecoration(
              color: isSaved ? AppTheme.primaryGreen.withOpacity(0.03) : null),
            children: [
              // Student name
              SizedBox(
                width: 150,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      if (isSaved)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.check_circle,
                            size: 14,
                            color: AppTheme.primaryGreen)),
                      Expanded(
                        child: Text(
                          student.fullName,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis)),
                    ]))),
              // Score cells
              ...questions.map(
                (q) => _ScoreCell(
                  studentId: student.id,
                  question: q,
                  currentScore: studentScores[q.number],
                  onChanged: (score) => _setScore(student.id, q.number, score))),
              // Total
              SizedBox(
                width: 70,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '${total.toStringAsFixed(0)}/${maxTotal.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: total >= maxTotal * 0.5
                          ? AppTheme.primaryGreen
                          : AppTheme.primaryRed)))),
            ]);
        }),
      ]);
  }
}

/// A tappable score cell that shows a number pad dialog.
class _ScoreCell extends StatelessWidget {
  final String studentId;
  final Question question;
  final double? currentScore;
  final ValueChanged<double> onChanged;

  const _ScoreCell({
    required this.studentId,
    required this.question,
    required this.currentScore,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasScore = currentScore != null;
    final maxPoints = question.points;

    return GestureDetector(
      onTap: () => _showScorePad(context),
      child: SizedBox(
        width: 60,
        height: 44,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: hasScore
                  ? (currentScore! >= maxPoints
                        ? AppTheme.primaryGreen.withOpacity(0.15)
                        : currentScore! > 0
                        ? AppTheme.primaryYellow.withOpacity(0.15)
                        : AppTheme.primaryRed.withOpacity(0.15))
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hasScore ? Colors.transparent : Colors.grey.shade300,
                width: 0.5)),
            child: Text(
              hasScore ? currentScore!.toStringAsFixed(0) : '—',
              style: TextStyle(
                fontSize: 13,
                fontWeight: hasScore ? FontWeight.bold : FontWeight.normal,
                color: hasScore
                    ? (currentScore! >= maxPoints
                          ? AppTheme.primaryGreen
                          : currentScore! > 0
                          ? Colors.orange.shade700
                          : AppTheme.primaryRed)
                    : Colors.grey.shade400))))));
  }

  void _showScorePad(BuildContext context) {
    final controller = TextEditingController(
      text: currentScore?.toStringAsFixed(0) ?? '');

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${'Question'} ${question.number}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
              Text(
                '${'of'} ${question.points.toStringAsFixed(0)} ${'points'}',
                style: const TextStyle(color: AppTheme.lightText)),
              const SizedBox(height: 16),

              // Quick score buttons (0 to maxPoints)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(question.points.toInt() + 1, (score) {
                  final isSelected = currentScore?.toInt() == score;
                  return ChoiceChip(
                    label: Text('$score'),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryGreen,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : null,
                      fontWeight: FontWeight.bold),
                    onSelected: (_) {
                      onChanged(score.toDouble());
                      Navigator.pop(ctx);
                    });
                })),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Custom score input
              const Text(
                'Or enter custom score',
                style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*')),
                      ],
                      decoration: const InputDecoration(
                        hintText: 'Score',
                        isDense: true),
                      onSubmitted: (v) {
                        final score = double.tryParse(v);
                        if (score != null) {
                          onChanged(score.clamp(0, question.points));
                          Navigator.pop(ctx);
                        }
                      })),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () {
                      final score = double.tryParse(controller.text);
                      if (score != null) {
                        onChanged(score.clamp(0, question.points));
                        Navigator.pop(ctx);
                      }
                    },
                    icon: const Icon(Icons.check, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white)),
                ]),
            ]))));
  }
}

/// Assessment picker shown when Quick Enter is opened without an assessment.
class _AssessmentPicker extends StatelessWidget {
  final ValueChanged<Assessment> onSelected;

  const _AssessmentPicker({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final assessments = context.watch<AssessmentProvider>().assessments;

    return Scaffold(
      appBar: AppBar(title: const Text('Select Assessment')),
      body: assessments.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 64,
                    color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text(
                    'No assessments yet',
                    style: TextStyle(color: AppTheme.lightText)),
                ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: assessments.length,
              itemBuilder: (context, index) {
                final a = assessments[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
                      child: const Icon(
                        Icons.assignment,
                        color: AppTheme.primaryGreen)),
                    title: Text(a.title),
                    subtitle: Text(
                      '${a.subject} • ${a.questionCount} ${'questions'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onSelected(a)));
              }));
  }
}
