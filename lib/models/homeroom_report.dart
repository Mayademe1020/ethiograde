import 'package:uuid/uuid.dart';

/// Breakdown of a student's performance in a single subject according to
/// Ethiopian Ministry of Education Continuous Assessment (CA) guidelines.
class SubjectScoreBreakdown {
  final String subjectName;
  final double quizScore; // typically 10%
  final double homeworkScore; // typically 10%
  final double projectScore; // typically 10%
  final double midtermScore; // typically 20-30%
  final double finalExamScore; // typically 40-50%
  final double totalScore; // Normalized sum out of 100%
  final String letterGrade; // A, B, C, D, F

  const SubjectScoreBreakdown({
    required this.subjectName,
    this.quizScore = 0.0,
    this.homeworkScore = 0.0,
    this.projectScore = 0.0,
    this.midtermScore = 0.0,
    this.finalExamScore = 0.0,
    required this.totalScore,
    required this.letterGrade,
  });

  static String calculateLetterGrade(double score) {
    if (score >= 85.0) return 'A';
    if (score >= 75.0) return 'B';
    if (score >= 60.0) return 'C';
    if (score >= 50.0) return 'D';
    return 'F';
  }

  Map<String, dynamic> toMap() => {
    'subjectName': subjectName,
    'quizScore': quizScore,
    'homeworkScore': homeworkScore,
    'projectScore': projectScore,
    'midtermScore': midtermScore,
    'finalExamScore': finalExamScore,
    'totalScore': totalScore,
    'letterGrade': letterGrade,
  };

  factory SubjectScoreBreakdown.fromMap(Map<String, dynamic> map) =>
      SubjectScoreBreakdown(
        subjectName: map['subjectName'] as String,
        quizScore: (map['quizScore'] as num?)?.toDouble() ?? 0.0,
        homeworkScore: (map['homeworkScore'] as num?)?.toDouble() ?? 0.0,
        projectScore: (map['projectScore'] as num?)?.toDouble() ?? 0.0,
        midtermScore: (map['midtermScore'] as num?)?.toDouble() ?? 0.0,
        finalExamScore: (map['finalExamScore'] as num?)?.toDouble() ?? 0.0,
        totalScore: (map['totalScore'] as num?)?.toDouble() ?? 0.0,
        letterGrade: map['letterGrade'] as String? ?? 'F',
      );
}

/// A student's complete semester card record (የተማሪ ውጤት መግለጫ ካርድ).
class StudentCardRecord {
  final String studentId; // internal UUID or Roll Number
  final String rollNumber;
  final String fullName;
  final String gender;
  final Map<String, SubjectScoreBreakdown> subjects; // subjectName -> breakdown
  final double grandTotal;
  final double semesterAverage;
  final int classRank; // 1st, 2nd, etc.
  final String conduct; // 'A', 'B', 'C'
  final String remarkEn;
  final String remarkAm;
  final bool hasFinanceHold; // Private school tuition hold flag (እዳ ያለበት)

  const StudentCardRecord({
    required this.studentId,
    required this.rollNumber,
    required this.fullName,
    this.gender = 'M',
    required this.subjects,
    required this.grandTotal,
    required this.semesterAverage,
    required this.classRank,
    this.conduct = 'A',
    this.remarkEn = 'Good performance',
    this.remarkAm = 'ጥሩ ውጤት አስመዝግቧል',
    this.hasFinanceHold = false,
  });

  Map<String, dynamic> toMap() => {
    'studentId': studentId,
    'rollNumber': rollNumber,
    'fullName': fullName,
    'gender': gender,
    'subjects': subjects.map((k, v) => MapEntry(k, v.toMap())),
    'grandTotal': grandTotal,
    'semesterAverage': semesterAverage,
    'classRank': classRank,
    'conduct': conduct,
    'remarkEn': remarkEn,
    'remarkAm': remarkAm,
    'hasFinanceHold': hasFinanceHold,
  };

  factory StudentCardRecord.fromMap(Map<String, dynamic> map) {
    final subMap = map['subjects'] as Map<String, dynamic>? ?? {};
    final subjects = subMap.map(
      (k, v) => MapEntry(
        k,
        SubjectScoreBreakdown.fromMap(v as Map<String, dynamic>),
      ),
    );

    return StudentCardRecord(
      studentId: map['studentId'] as String,
      rollNumber: map['rollNumber'] as String? ?? '',
      fullName: map['fullName'] as String? ?? '',
      gender: map['gender'] as String? ?? 'M',
      subjects: subjects,
      grandTotal: (map['grandTotal'] as num?)?.toDouble() ?? 0.0,
      semesterAverage: (map['semesterAverage'] as num?)?.toDouble() ?? 0.0,
      classRank: (map['classRank'] as num?)?.toInt() ?? 0,
      conduct: map['conduct'] as String? ?? 'A',
      remarkEn: map['remarkEn'] as String? ?? '',
      remarkAm: map['remarkAm'] as String? ?? '',
      hasFinanceHold: map['hasFinanceHold'] as bool? ?? false,
    );
  }
}

/// The Homeroom compilation for a complete class section on Card Day.
class HomeroomClassReport {
  final String id;
  final String classId;
  final String className; // e.g. "Grade 10B"
  final String academicYear; // e.g. "2026/2027"
  final int semester; // 1 or 2
  final String homeroomTeacherName;
  final List<String> subjectList; // e.g. ['Math', 'Biology', 'Chemistry', 'Physics', 'English', 'Amharic']
  final List<StudentCardRecord> students; // Sorted by rank or roll number
  final DateTime compiledAt;

  HomeroomClassReport({
    String? id,
    required this.classId,
    required this.className,
    required this.academicYear,
    required this.semester,
    required this.homeroomTeacherName,
    required this.subjectList,
    required this.students,
    DateTime? compiledAt,
  }) : id = id ?? const Uuid().v4(),
       compiledAt = compiledAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'classId': classId,
    'className': className,
    'academicYear': academicYear,
    'semester': semester,
    'homeroomTeacherName': homeroomTeacherName,
    'subjectList': subjectList,
    'students': students.map((s) => s.toMap()).toList(),
    'compiledAt': compiledAt.toIso8601String(),
  };

  factory HomeroomClassReport.fromMap(Map<String, dynamic> map) =>
      HomeroomClassReport(
        id: map['id'] as String,
        classId: map['classId'] as String,
        className: map['className'] as String,
        academicYear: map['academicYear'] as String,
        semester: (map['semester'] as num?)?.toInt() ?? 1,
        homeroomTeacherName: map['homeroomTeacherName'] as String? ?? '',
        subjectList: (map['subjectList'] as List<dynamic>?)?.cast<String>() ?? [],
        students: ((map['students'] as List<dynamic>?) ?? [])
            .map((s) => StudentCardRecord.fromMap(s as Map<String, dynamic>))
            .toList(),
        compiledAt: DateTime.parse(map['compiledAt'] as String),
      );
}
