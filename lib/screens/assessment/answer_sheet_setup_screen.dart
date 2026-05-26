import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/assessment.dart';
import '../../models/student.dart';
import '../../models/answer_sheet_config.dart';
import '../../services/assessment_provider.dart';
import '../../services/student_provider.dart';
import '../../services/class_provider.dart';
import '../../services/settings_provider.dart';
import '../../services/answer_sheet_generator.dart';

/// Screen for configuring and generating answer sheet PDFs.
///
/// Accessible from assessment detail or reports.
/// Phase 2 of the OMR pipeline — the UI that controls Phase 1 engine.
class AnswerSheetSetupScreen extends StatefulWidget {
  final Assessment? assessment;

  const AnswerSheetSetupScreen({super.key, this.assessment});

  @override
  State<AnswerSheetSetupScreen> createState() => _AnswerSheetSetupScreenState();
}

class _AnswerSheetSetupScreenState extends State<AnswerSheetSetupScreen> {
  Assessment? _assessment;
  final _schoolController = TextEditingController();
  final _examNameController = TextEditingController();
  final _subjectController = TextEditingController();

  SheetLayout _layout = SheetLayout.halfSheet; // default to paper-saving
  bool _prefillNames = false;
  bool _isGenerating = false;
  bool _editingRanges = false;
  List<QuestionTypeRange>? _customRanges;

  @override
  void initState() {
    super.initState();
    _assessment = widget.assessment;
    if (_assessment != null) {
      _examNameController.text = _assessment!.title;
      _subjectController.text = _assessment!.subject;
    }
  }

  @override
  void dispose() {
    _schoolController.dispose();
    _examNameController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assessments = context.watch<AssessmentProvider>().assessments;

    // Load school name from settings
    final settings = context.watch<SettingsProvider>();
    if (_schoolController.text.isEmpty && settings.schoolName.isNotEmpty) {
      _schoolController.text = settings.schoolName;
    }

    final hasAssessment = _assessment != null;
    final typeRanges = hasAssessment
        ? AnswerSheetConfig.detectRanges(_assessment!)
        : <QuestionTypeRange>[];

    return Scaffold(
      appBar: AppBar(title: Text('Answer Sheet Setup')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Assessment selector ────────────────────────────────
            _sectionTitle('Assessment'),
            const SizedBox(height: 8),
            if (widget.assessment != null)
              _assessmentCard(_assessment!)
            else
              DropdownButtonFormField<Assessment>(
                value: _assessment,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.assignment),
                  hintText: 'Select assessment...',
                ),
                items: assessments
                    .map(
                      (a) => DropdownMenuItem(
                        value: a,
                        child: Text('${a.title} (${a.subject})'),
                      ),
                    )
                    .toList(),
                onChanged: (a) {
                  setState(() {
                    _assessment = a;
                    if (a != null) {
                      _examNameController.text = a.title;
                      _subjectController.text = a.subject;
                    }
                  });
                },
              ),
            const SizedBox(height: 24),

            // ── Question type breakdown ────────────────────────────
            if (hasAssessment) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _sectionTitle('Question Types'),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _editingRanges = !_editingRanges;
                        if (_editingRanges && _customRanges == null) {
                          _customRanges = typeRanges
                              .map(
                                (r) => QuestionTypeRange(
                                  start: r.start,
                                  end: r.end,
                                  isMcq: r.isMcq,
                                ),
                              )
                              .toList();
                        }
                      });
                    },
                    icon: Icon(
                      _editingRanges ? Icons.check : Icons.edit,
                      size: 16,
                    ),
                    label: Text(
                      _editingRanges ? ('Done') : ('Edit'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _editingRanges && _customRanges != null
                  ? _editableTypeBreakdown(_customRanges!)
                  : _typeBreakdown(typeRanges),
              const SizedBox(height: 24),
            ],

            // ── Paper layout ──────────────────────────────────────
            _sectionTitle('Paper Layout'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _layoutOption(
                    SheetLayout.fullA4,
                    Icons.fullscreen,
                    'Full A4',
                    '1 sheet per page',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _layoutOption(
                    SheetLayout.halfSheet,
                    Icons.content_cut,
                    'Half (2 per page)',
                    '50% paper savings',
                  ),
                ),
              ],
            ),
            if (_layout == SheetLayout.halfSheet) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.info.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.info.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: AppTheme.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cut sheets in half and share. Check the box on one sheet to set the answer key.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.lightText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // ── Header fields ──────────────────────────────────────
            _sectionTitle('Header Info'),
            const SizedBox(height: 8),
            TextField(
              controller: _schoolController,
              decoration: InputDecoration(
                labelText: 'School Name',
                prefixIcon: const Icon(Icons.school_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _examNameController,
              decoration: InputDecoration(
                labelText: 'Exam Name',
                prefixIcon: const Icon(Icons.description_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subjectController,
              decoration: InputDecoration(
                labelText: 'Subject',
                prefixIcon: const Icon(Icons.book_outlined),
              ),
            ),
            const SizedBox(height: 24),

            // ── Student name mode ──────────────────────────────────
            _sectionTitle('Student Names'),
            const SizedBox(height: 8),
            _studentNameMode(),
            if (_prefillNames && hasAssessment) ...[
              const SizedBox(height: 12),
              _studentListPreview(),
            ],
            const SizedBox(height: 24),

            // ── Answer key status ──────────────────────────────────
            if (hasAssessment) ...[
              _sectionTitle('Answer Key Status'),
              const SizedBox(height: 8),
              _answerKeyStatus(_assessment!),
              const SizedBox(height: 24),
            ],

            // ── Generate button ────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: hasAssessment && !_isGenerating ? _generate : null,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: Text(
                  _isGenerating ? ('Generating...') : ('Generate PDF'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (hasAssessment) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.camera,
                    arguments: {
                      'assessment': _assessment,
                      'scanMode': 'masterKey',
                    },
                  ),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text(
                    'Scan master answer sheet',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Section title ─────────────────────────────────────────────────

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  // ── Assessment card (when pre-selected) ───────────────────────────

  Widget _assessmentCard(Assessment a) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.assignment, color: AppTheme.primaryGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${a.subject} · ${a.questions.length} ${"questions"}',
                  style: TextStyle(fontSize: 12, color: AppTheme.lightText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Question type breakdown ───────────────────────────────────────

  Widget _typeBreakdown(List<QuestionTypeRange> ranges) {
    if (ranges.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No questions — add questions before generating',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: ranges.map((range) {
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: range.isMcq
                ? AppTheme.primaryGreen.withOpacity(0.05)
                : AppTheme.primaryYellow.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: range.isMcq
                  ? AppTheme.primaryGreen.withOpacity(0.2)
                  : AppTheme.primaryYellow.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                range.isMcq ? Icons.circle_outlined : Icons.check_box_outlined,
                size: 18,
                color: range.isMcq
                    ? AppTheme.primaryGreen
                    : AppTheme.primaryYellow,
              ),
              const SizedBox(width: 10),
              Text(
                range.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                range.isMcq ? ('MCQ (A-D)') : ('True/False'),
                style: TextStyle(fontSize: 12, color: AppTheme.lightText),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: range.isMcq
                      ? AppTheme.primaryGreen.withOpacity(0.1)
                      : AppTheme.primaryYellow.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${range.count}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: range.isMcq
                        ? AppTheme.primaryGreen
                        : Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Editable version of type breakdown — shows start/end fields + MCQ/T/F toggle.
  Widget _editableTypeBreakdown(List<QuestionTypeRange> ranges) {
    return Column(
      children: [
        ...ranges.asMap().entries.map((entry) {
          final i = entry.key;
          final range = entry.value;
          final startController = TextEditingController(text: '${range.start}');
          final endController = TextEditingController(text: '${range.end}');

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: range.isMcq
                  ? AppTheme.primaryGreen.withOpacity(0.05)
                  : AppTheme.primaryYellow.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: range.isMcq
                    ? AppTheme.primaryGreen.withOpacity(0.3)
                    : AppTheme.primaryYellow.withOpacity(0.4),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // MCQ / T/F toggle
                    GestureDetector(
                      onTap: () => setState(() {
                        _customRanges![i] = QuestionTypeRange(
                          start: range.start,
                          end: range.end,
                          isMcq: !range.isMcq,
                        );
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: range.isMcq
                              ? AppTheme.primaryGreen
                              : AppTheme.primaryYellow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          range.isMcq ? 'MCQ' : ('T/F'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: range.isMcq ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Start field
                    Expanded(
                      child: TextField(
                        controller: startController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'From',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onChanged: (val) {
                          final n = int.tryParse(val);
                          if (n != null && n > 0) {
                            setState(() {
                              _customRanges![i] = QuestionTypeRange(
                                start: n,
                                end: range.end,
                                isMcq: range.isMcq,
                              );
                            });
                          }
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '–',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    // End field
                    Expanded(
                      child: TextField(
                        controller: endController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'To',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onChanged: (val) {
                          final n = int.tryParse(val);
                          if (n != null && n >= range.start) {
                            setState(() {
                              _customRanges![i] = QuestionTypeRange(
                                start: range.start,
                                end: n,
                                isMcq: range.isMcq,
                              );
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Delete button (if more than 1 range)
                    if (ranges.length > 1)
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          size: 20,
                          color: Colors.red,
                        ),
                        onPressed: () => setState(() {
                          _customRanges!.removeAt(i);
                        }),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${range.count} ${"questions"}',
                  style: TextStyle(fontSize: 11, color: AppTheme.lightText),
                ),
              ],
            ),
          );
        }),
        // Add range button
        OutlinedButton.icon(
          onPressed: () => setState(() {
            final last = _customRanges!.last;
            _customRanges!.add(
              QuestionTypeRange(
                start: last.end + 1,
                end: last.end + 5,
                isMcq: true,
              ),
            );
          }),
          icon: const Icon(Icons.add, size: 18),
          label: Text('Add Range'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryGreen,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }

  // ── Questions per page option ─────────────────────────────────────

  // ── Paper layout option ───────────────────────────────────────────

  Widget _layoutOption(
    SheetLayout value,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final isSelected = _layout == value;
    return GestureDetector(
      onTap: () => setState(() => _layout = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryGreen.withOpacity(0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primaryGreen : Colors.grey.shade300,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? AppTheme.primaryGreen : Colors.grey),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isSelected ? AppTheme.primaryGreen : AppTheme.darkText,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: AppTheme.lightText),
            ),
          ],
        ),
      ),
    );
  }

  // ── Student name mode ─────────────────────────────────────────────

  Widget _studentNameMode() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _prefillNames = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: !_prefillNames
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: !_prefillNames
                      ? AppTheme.primaryGreen
                      : Colors.grey.shade300,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.edit_off_outlined,
                    color: !_prefillNames ? AppTheme.primaryGreen : Colors.grey,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Blank',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: !_prefillNames
                          ? AppTheme.primaryGreen
                          : AppTheme.darkText,
                    ),
                  ),
                  Text(
                    'All same sheet',
                    style: TextStyle(fontSize: 11, color: AppTheme.lightText),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _prefillNames = true),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _prefillNames
                    ? AppTheme.primaryGreen.withOpacity(0.1)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _prefillNames
                      ? AppTheme.primaryGreen
                      : Colors.grey.shade300,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.person_outline,
                    color: _prefillNames ? AppTheme.primaryGreen : Colors.grey,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Prefill Names',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _prefillNames
                          ? AppTheme.primaryGreen
                          : AppTheme.darkText,
                    ),
                  ),
                  Text(
                    'One per student',
                    style: TextStyle(fontSize: 11, color: AppTheme.lightText),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Student list preview ──────────────────────────────────────────

  Widget _studentListPreview() {
    final classId = _assessment!.className;
    final classes = context.read<ClassProvider>().classes;
    final matchingClass = classes.where((c) => c.name == classId).toList();

    List<Student> students = [];
    if (matchingClass.isNotEmpty) {
      students = context.read<StudentProvider>().studentsByClassId(
        matchingClass.first.id,
      );
    }

    if (students.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Text(
          'No students found in this class',
          style: const TextStyle(fontSize: 13),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${students.length} ${"students"}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          ...students
              .take(5)
              .map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${s.studentId.isNotEmpty ? "${s.studentId} · " : ""}${s.fullName}',
                    style: TextStyle(fontSize: 12, color: AppTheme.lightText),
                  ),
                ),
              ),
          if (students.length > 5)
            Text(
              '... +${students.length - 5} ${"more"}',
              style: TextStyle(fontSize: 11, color: AppTheme.lightText),
            ),
        ],
      ),
    );
  }

  // ── Answer key status ─────────────────────────────────────────────

  Widget _answerKeyStatus(Assessment assessment) {
    final total = assessment.questions.length;
    final withAnswer = assessment.questions
        .where(
          (q) =>
              q.correctAnswer != null && q.correctAnswer.toString().isNotEmpty,
        )
        .length;
    final allSet = withAnswer == total;
    final ratio = total > 0 ? withAnswer / total : 0.0;

    Color statusColor;
    IconData statusIcon;
    if (allSet) {
      statusColor = AppTheme.primaryGreen;
      statusIcon = Icons.check_circle;
    } else if (ratio > 0.5) {
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
    } else {
      statusColor = Colors.red;
      statusIcon = Icons.error;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$withAnswer/$total ${"answers set"}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
                if (!allSet)
                  Text(
                    'Set all answers before grading will work',
                    style: TextStyle(fontSize: 11, color: AppTheme.lightText),
                  ),
              ],
            ),
          ),
          if (!allSet)
            SizedBox(
              height: 32,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/assessment/answer-key',
                    arguments: assessment,
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: BorderSide(color: statusColor),
                ),
                child: Text(
                  'Fix',
                  style: TextStyle(color: statusColor, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Generate PDF ──────────────────────────────────────────────────

  Future<void> _generate() async {
    if (_assessment == null) return;

    setState(() => _isGenerating = true);

    try {
      // Fetch students if prefill is on
      List<Student> students = [];
      if (_prefillNames && _assessment != null) {
        final classId = _assessment!.className;
        final classes = context.read<ClassProvider>().classes;
        final matchingClass = classes.where((c) => c.name == classId).toList();
        if (matchingClass.isNotEmpty) {
          students = context.read<StudentProvider>().studentsByClassId(
            matchingClass.first.id,
          );
        }
      }

      final generator = AnswerSheetGenerator();
      final (pdfFile, coordMapFile, relativeName) = await generator.generate(
        assessment: _assessment!,
        schoolName: _schoolController.text,
        students: students,
        prefillNames: _prefillNames,
        layout: _layout,
      );

      // Persist relative coordinate map filename to assessment so scanner can find it
      final updated = _assessment!.copyWith(coordinateMapPath: relativeName);
      await context.read<AssessmentProvider>().updateAssessment(updated);
      _assessment = updated;

      if (!mounted) return;

      // Show success + share

      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppTheme.primaryGreen,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'PDF Generated!',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_assessment!.questions.length} ${"questions"}',
                  style: TextStyle(color: AppTheme.lightText),
                ),
                if (_prefillNames && students.isNotEmpty)
                  Text(
                    '${students.length} ${"sheets"} (${"names pre-filled"})',
                    style: TextStyle(
                      color: AppTheme.primaryGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (_layout == SheetLayout.halfSheet)
                  Text(
                    '2 per page — cut and share',
                    style: TextStyle(
                      color: AppTheme.info,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await Share.shareXFiles([
                        XFile(pdfFile.path),
                      ], text: '${_assessment!.title} - Answer Sheet');
                    },
                    icon: const Icon(Icons.share),
                    label: Text('Share / Print'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }
}
