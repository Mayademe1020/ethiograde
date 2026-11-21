import '../models/assessment.dart';
import '../models/class_info.dart';
import '../models/homeroom_report.dart';
import '../models/scan_result.dart';
import '../models/student.dart';

/// Core engine for Semester Report Card ("Card Day") consolidation.
///
/// Automatically aggregates individual subject assessments into a unified
/// class broadsheet with total scores, averages, ranks, conduct, and remarks.
class HomeroomConsolidationService {
  static final HomeroomConsolidationService _instance =
      HomeroomConsolidationService._();
  factory HomeroomConsolidationService() => _instance;
  HomeroomConsolidationService._();

  /// Consolidates all subject assessments for a class section into a complete report.
  HomeroomClassReport consolidateClass({
    required ClassInfo classInfo,
    required List<Student> students,
    required List<Assessment> assessments,
    required List<ScanResult> allScanResults,
    required String academicYear,
    required int semester,
    String homeroomTeacherName = '',
    Set<String> financeHoldStudentIds = const {},
    Map<String, String>? customRemarksEn,
    Map<String, String>? customRemarksAm,
    Map<String, String>? customConducts,
  }) {
    // 1. Discover all distinct subjects from the class assessments
    final subjectsSet = <String>{};
    for (final a in assessments) {
      if (a.subject.trim().isNotEmpty) {
        subjectsSet.add(a.subject.trim());
      }
    }
    // If classInfo has a subject or default set
    if (subjectsSet.isEmpty && classInfo.subject.isNotEmpty) {
      subjectsSet.add(classInfo.subject);
    }
    final subjectList = subjectsSet.toList()..sort();

    // Map scan results by (assessmentId, studentId) -> ScanResult
    final resultMap = <String, ScanResult>{};
    for (final r in allScanResults) {
      resultMap['${r.assessmentId}_${r.studentId}'] = r;
    }

    // 2. Build student records
    final studentRecords = <_TempStudentRecord>[];

    for (final student in students) {
      final subjectBreakdowns = <String, SubjectScoreBreakdown>{};
      double studentGrandTotal = 0.0;

      for (final subject in subjectList) {
        // Find assessments for this subject
        final subjectAssessments = assessments
            .where((a) => a.subject.trim().toLowerCase() == subject.toLowerCase())
            .toList();

        double subjectTotal = 0.0;

        if (subjectAssessments.isEmpty) {
          // No assessment yet for this subject
          subjectBreakdowns[subject] = SubjectScoreBreakdown(
            subjectName: subject,
            totalScore: 0.0,
            letterGrade: 'F',
          );
        } else {
          double earnedTotal = 0.0;
          double maxPossibleTotal = 0.0;
          double quizScore = 0.0;
          double midtermScore = 0.0;
          double finalScore = 0.0;

          for (final a in subjectAssessments) {
            final scan = resultMap['${a.id}_${student.id}'] ??
                resultMap['${a.id}_${student.studentId}'];

            final earned = scan?.totalScore ?? 0.0;
            final maxQ = a.questions.isNotEmpty ? a.questions.length.toDouble() : 100.0;

            final titleLower = a.title.toLowerCase();
            if (titleLower.contains('quiz') || titleLower.contains('test 1')) {
              quizScore = (maxQ > 0) ? (earned / maxQ) * 10.0 : earned;
            } else if (titleLower.contains('midterm') || titleLower.contains('mid')) {
              midtermScore = (maxQ > 0) ? (earned / maxQ) * 30.0 : earned;
            } else if (titleLower.contains('final')) {
              finalScore = (maxQ > 0) ? (earned / maxQ) * 50.0 : earned;
            }

            earnedTotal += earned;
            maxPossibleTotal += maxQ;
          }

          // If standard weighting was detected
          if (quizScore > 0 || midtermScore > 0 || finalScore > 0) {
            subjectTotal = (quizScore + midtermScore + finalScore).clamp(0.0, 100.0);
          } else if (maxPossibleTotal > 0) {
            // Normalize raw scores to 100%
            subjectTotal = ((earnedTotal / maxPossibleTotal) * 100.0).clamp(0.0, 100.0);
          }

          subjectBreakdowns[subject] = SubjectScoreBreakdown(
            subjectName: subject,
            quizScore: quizScore,
            midtermScore: midtermScore,
            finalExamScore: finalScore,
            totalScore: double.parse(subjectTotal.toStringAsFixed(1)),
            letterGrade: SubjectScoreBreakdown.calculateLetterGrade(subjectTotal),
          );
        }

        studentGrandTotal += subjectTotal;
      }

      final subjectCount = subjectList.isNotEmpty ? subjectList.length : 1;
      final semesterAverage = double.parse(
        (studentGrandTotal / subjectCount).toStringAsFixed(2),
      );

      studentRecords.add(
        _TempStudentRecord(
          student: student,
          subjects: subjectBreakdowns,
          grandTotal: double.parse(studentGrandTotal.toStringAsFixed(1)),
          semesterAverage: semesterAverage,
        ),
      );
    }

    // 3. Compute rankings (Sort descending by grandTotal, handle ties)
    studentRecords.sort((a, b) => b.grandTotal.compareTo(a.grandTotal));

    final finalStudentCards = <StudentCardRecord>[];
    int currentRank = 1;

    for (int i = 0; i < studentRecords.length; i++) {
      if (i > 0 && studentRecords[i].grandTotal < studentRecords[i - 1].grandTotal) {
        currentRank = i + 1;
      }

      final temp = studentRecords[i];
      final sId = temp.student.studentId;

      // Smart bilingual remarks based on average
      final avg = temp.semesterAverage;
      final defaultRemarkEn = _getDefaultRemarkEn(avg);
      final defaultRemarkAm = _getDefaultRemarkAm(avg);

      final hasHold = financeHoldStudentIds.contains(temp.student.id) ||
          financeHoldStudentIds.contains(temp.student.studentId);

      finalStudentCards.add(
        StudentCardRecord(
          studentId: temp.student.id,
          rollNumber: temp.student.studentId,
          fullName: temp.student.fullName,
          gender: temp.student.gender,
          subjects: temp.subjects,
          grandTotal: temp.grandTotal,
          semesterAverage: temp.semesterAverage,
          classRank: currentRank,
          conduct: customConducts?[sId] ?? 'A',
          remarkEn: customRemarksEn?[sId] ?? defaultRemarkEn,
          remarkAm: customRemarksAm?[sId] ?? defaultRemarkAm,
          hasFinanceHold: hasHold,
        ),
      );
    }

    return HomeroomClassReport(
      classId: classInfo.id,
      className: classInfo.displayName,
      academicYear: academicYear,
      semester: semester,
      homeroomTeacherName: homeroomTeacherName,
      subjectList: subjectList,
      students: finalStudentCards,
    );
  }

  static String _getDefaultRemarkEn(double avg) {
    if (avg >= 85.0) return 'Outstanding academic achievement and conduct.';
    if (avg >= 75.0) return 'Very good performance. Can reach higher.';
    if (avg >= 60.0) return 'Satisfactory. Needs additional study time.';
    if (avg >= 50.0) return 'Passing. Close parental supervision required.';
    return 'Critical. Immediate teacher-parent intervention needed.';
  }

  static String _getDefaultRemarkAm(double avg) {
    if (avg >= 85.0) return 'የላቀ የትምህርት አቀባበል እና መልካም ስነ-ምግባር አሳይቷል።';
    if (avg >= 75.0) return 'በጣም ጥሩ ውጤት፤ የበለጠ መስራት ይችላል።';
    if (avg >= 60.0) return 'ጥሩ ውጤት፤ ተጨማሪ ጥናትና ትኩረት ያስፈልገዋል።';
    if (avg >= 50.0) return 'አማካይ ውጤት፤ የወላጅ የቅርብ ክትትል ያስፈልገዋል።';
    return 'ደካማ ውጤት፤ አፋጣኝ የወላጅ እና የመምህር ውይይት ያስፈልገዋል።';
  }
}

class _TempStudentRecord {
  final Student student;
  final Map<String, SubjectScoreBreakdown> subjects;
  final double grandTotal;
  final double semesterAverage;

  _TempStudentRecord({
    required this.student,
    required this.subjects,
    required this.grandTotal,
    required this.semesterAverage,
  });
}
