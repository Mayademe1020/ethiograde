import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Lightweight vector representation of a scanned answer sheet.
///
/// Stores only coordinate densities (~1.5 KB) instead of a multi-megabyte JPEG.
/// Allows pixel-perfect visual reconstruction of what the student bubbled at scan
/// time to prevent post-grading tampering and score alteration disputes.
class ProofVaultEntry {
  final String id;
  final String assessmentId;
  final String studentId;
  final String studentName;
  final DateTime scannedAt;
  final String sha256Hash;
  final Map<int, Map<String, double>> questionDensities;
  final Map<int, String> detectedAnswers;
  final double? teacherScore;
  final bool isTamperedFlag;
  final String? tamperReason;

  ProofVaultEntry({
    required this.id,
    required this.assessmentId,
    required this.studentId,
    required this.studentName,
    required this.scannedAt,
    required this.sha256Hash,
    required this.questionDensities,
    required this.detectedAnswers,
    this.teacherScore,
    this.isTamperedFlag = false,
    this.tamperReason,
  });

  /// Generate a cryptographic SHA-256 fingerprint for this scan snapshot.
  static String generateFingerprint({
    required String assessmentId,
    required String studentId,
    required DateTime timestamp,
    required Map<int, String> answers,
    double? teacherScore,
  }) {
    final payload = jsonEncode({
      'assessmentId': assessmentId,
      'studentId': studentId,
      'timestamp': timestamp.toIso8601String(),
      'answers': answers.map((k, v) => MapEntry(k.toString(), v)),
      'teacherScore': teacherScore,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'assessmentId': assessmentId,
    'studentId': studentId,
    'studentName': studentName,
    'scannedAt': scannedAt.toIso8601String(),
    'sha256Hash': sha256Hash,
    'questionDensities': questionDensities.map(
      (q, densities) => MapEntry(q.toString(), densities),
    ),
    'detectedAnswers': detectedAnswers.map(
      (q, ans) => MapEntry(q.toString(), ans),
    ),
    'teacherScore': teacherScore,
    'isTamperedFlag': isTamperedFlag,
    'tamperReason': tamperReason,
  };

  factory ProofVaultEntry.fromMap(Map<String, dynamic> map) {
    final densitiesRaw = map['questionDensities'] as Map<String, dynamic>? ?? {};
    final densities = <int, Map<String, double>>{};
    densitiesRaw.forEach((qStr, optMap) {
      final qNum = int.tryParse(qStr);
      if (qNum != null && optMap is Map) {
        densities[qNum] = optMap.map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        );
      }
    });

    final answersRaw = map['detectedAnswers'] as Map<String, dynamic>? ?? {};
    final answers = <int, String>{};
    answersRaw.forEach((qStr, ans) {
      final qNum = int.tryParse(qStr);
      if (qNum != null) {
        answers[qNum] = ans.toString();
      }
    });

    return ProofVaultEntry(
      id: map['id'] as String,
      assessmentId: map['assessmentId'] as String,
      studentId: map['studentId'] as String,
      studentName: map['studentName'] as String? ?? '',
      scannedAt: DateTime.parse(map['scannedAt'] as String),
      sha256Hash: map['sha256Hash'] as String,
      questionDensities: densities,
      detectedAnswers: answers,
      teacherScore: (map['teacherScore'] as num?)?.toDouble(),
      isTamperedFlag: map['isTamperedFlag'] as bool? ?? false,
      tamperReason: map['tamperReason'] as String?,
    );
  }
}
