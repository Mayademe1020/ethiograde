import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/theme.dart';
import '../../models/class_info.dart';
import '../../models/homeroom_report.dart';
import '../../services/class_provider.dart';
import '../../services/assessment_provider.dart';
import '../../services/student_provider.dart';
import '../../services/settings_provider.dart';
import '../../services/homeroom_consolidation_service.dart';
import '../../services/report_card_pdf_service.dart';

/// Homeroom Card Day Hub (የካርድ ቀን ማዕከል)
///
/// Consolidates all subject assessments across the semester into official
/// Ministry continuous assessment records, calculates ranks, manages conduct
/// grades, toggles Finance Holds (እዳ ያለበት), and prints 4-up Report Cards.
class HomeroomCardScreen extends StatefulWidget {
  const HomeroomCardScreen({super.key});

  @override
  State<HomeroomCardScreen> createState() => _HomeroomCardScreenState();
}

class _HomeroomCardScreenState extends State<HomeroomCardScreen> {
  ClassInfo? _selectedClass;
  int _semester = 1;
  String _academicYear = '2017 E.C.';
  HomeroomClassReport? _report;
  bool _isLoading = false;

  final Map<String, bool> _financeHolds = {};
  final Map<String, String> _conductGrades = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final classProv = context.read<ClassProvider>();
      if (classProv.classes.isNotEmpty) {
        setState(() {
          _selectedClass = classProv.classes.first;
        });
        _generateConsolidation();
      }
    });
  }

  void _generateConsolidation() {
    if (_selectedClass == null) return;
    setState(() => _isLoading = true);

    final assessmentProv = context.read<AssessmentProvider>();
    final studentProv = context.read<StudentProvider>();
    final settingsProv = context.read<SettingsProvider>();

    final classStudents = _selectedClass!.studentIds
        .map(studentProv.getStudentById)
        .whereType<dynamic>()
        .toList();

    // Map existing student objects into consolidation
    final studentList = classStudents.map((s) {
      final id = s.id as String;
      return {
        'id': id,
        'rollNumber': (s.rollNumber as String?) ?? '',
        'fullName': (s.fullName as String?) ?? '',
        'gender': (s.gender as String?) ?? 'M',
        'hasFinanceHold': _financeHolds[id] ?? false,
        'conduct': _conductGrades[id] ?? 'A',
      };
    }).toList();

    // Filter assessments matching this class
    final assessments = assessmentProv.assessments
        .where((a) => a.className == _selectedClass!.displayName)
        .toList();

    final report = HomeroomConsolidationService().consolidateClass(
      classId: _selectedClass!.id,
      className: _selectedClass!.displayName,
      academicYear: _academicYear,
      semester: _semester,
      homeroomTeacherName: settingsProv.teacherName,
      studentsData: studentList,
      assessments: assessments,
      financeHolds: _financeHolds,
      conductGrades: _conductGrades,
    );

    setState(() {
      _report = report;
      _isLoading = false;
    });
  }

  Future<void> _exportAndPrintCards() async {
    if (_report == null) return;
    setState(() => _isLoading = true);

    try {
      final settings = context.read<SettingsProvider>();
      final files = await ReportCardPdfService().generateCardDay(
        report: _report!,
        schoolName: settings.schoolName.isNotEmpty ? settings.schoolName : 'EthioGrade Academy',
      );

      final allFile = files['allCards'];
      if (allFile != null && mounted) {
        await Share.shareXFiles(
          [XFile(allFile.path)],
          text: 'EthioGrade Report Cards - ${_report!.className}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate cards: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showStudentEditSheet(StudentCardRecord student) {
    String currentConduct = _conductGrades[student.studentId] ?? student.conduct;
    bool currentHold = _financeHolds[student.studentId] ?? student.hasFinanceHold;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          student.fullName,
                          style: Theme.of(context).textTheme.titleLarge,
                          maxLines: 1,
                        ),
                      ),
                      Chip(
                        label: Text('Rank: ${student.classRank}'),
                        backgroundColor: AppTheme.primaryContainer,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Conduct Rating
                  Text('ባህሪ (Conduct Grade)', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: ['A', 'B', 'C', 'D'].map((g) {
                      final isSelected = currentConduct == g;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(g),
                          selected: isSelected,
                          onSelected: (val) {
                            if (val) {
                              setSheetState(() => currentConduct = g);
                              setState(() {
                                _conductGrades[student.studentId] = g;
                              });
                              _generateConsolidation();
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Finance Hold Toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('እዳ ያለበት (Finance Hold)'),
                    subtitle: const Text('Watermark card: VISIT FINANCE OFFICE'),
                    activeColor: AppTheme.error,
                    value: currentHold,
                    onChanged: (val) {
                      setSheetState(() => currentHold = val);
                      setState(() {
                        _financeHolds[student.studentId] = val;
                      });
                      _generateConsolidation();
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Save & Close'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final classes = context.watch<ClassProvider>().classes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Homeroom & Card Day (የካርድ ቀን)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _generateConsolidation,
            tooltip: 'Re-calculate Ranks',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ClassInfo>(
                      value: _selectedClass,
                      hint: const Text('Select Class'),
                      isExpanded: true,
                      items: classes.map((c) {
                        return DropdownMenuItem<ClassInfo>(
                          value: c,
                          child: Text(c.displayName),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedClass = val);
                          _generateConsolidation();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                DropdownButton<int>(
                  value: _semester,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Sem 1')),
                    DropdownMenuItem(value: 2, child: Text('Sem 2')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _semester = val);
                      _generateConsolidation();
                    }
                  },
                ),
              ],
            ),
          ),

          // Overview Stats Banner
          if (_report != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  _statCard('Students', '${_report!.students.length}', Icons.people, AppTheme.info),
                  const SizedBox(width: AppSpacing.sm),
                  _statCard(
                    'Class Avg',
                    _report!.students.isEmpty
                        ? '0%'
                        : '${(_report!.students.map((s) => s.semesterAverage).reduce((a, b) => a + b) / _report!.students.length).toStringAsFixed(1)}%',
                    Icons.trending_up,
                    AppTheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _statCard(
                    'Holds',
                    '${_report!.students.where((s) => s.hasFinanceHold).length}',
                    Icons.lock_clock,
                    AppTheme.error,
                  ),
                ],
              ),
            ),

          // Student Roster & Rank Table
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _report == null || _report!.students.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.assignment_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                            const SizedBox(height: AppSpacing.sm),
                            const Text('No students or grades recorded yet.'),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _report!.students.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final student = _report!.students[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: student.classRank <= 3
                                  ? AppTheme.secondaryContainer
                                  : AppTheme.primaryContainer,
                              child: Text(
                                '${student.classRank}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: student.classRank <= 3
                                      ? AppTheme.secondary
                                      : AppTheme.primary,
                                ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    student.fullName,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (student.hasFinanceHold)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.errorContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'እዳ',
                                      style: TextStyle(
                                        color: AppTheme.error,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              'Roll: ${student.rollNumber} • Avg: ${student.semesterAverage.toStringAsFixed(1)}% • Conduct: ${student.conduct}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _showStudentEditSheet(student),
                            ),
                            onTap: () => _showStudentEditSheet(student),
                          );
                        },
                      ),
          ),

          // Bottom Action Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: _report == null || _report!.students.isEmpty
                          ? null
                          : _exportAndPrintCards,
                      icon: const Icon(Icons.print),
                      label: const Text('🖨️ Print Report Cards (PDF)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
