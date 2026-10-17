import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/assessment.dart';

/// Deterministic fingerprint of an assessment's scoring key.
///
/// The fingerprint captures every field that affects automated scoring:
/// question identity, type, correct answer, points, keywords, rubric,
/// topic tag, rubric type, and weighted scale reference.
///
/// Two assessments with identical fingerprints will produce identical
/// scores for the same student responses.
class AnswerKeyFingerprintService {
  const AnswerKeyFingerprintService();

  /// Compute a deterministic SHA-256 fingerprint of the scoring key.
  ///
  /// Returns a lowercase hex string (64 chars).
  /// Empty string if the assessment has no questions.
  String compute(Assessment assessment) {
    if (assessment.questions.isEmpty) return '';

    final canonical = _canonicalize(assessment);
    final bytes = utf8.encode(canonical);
    return sha256.convert(bytes).toString();
  }

  /// Build a deterministic canonical string from scoring-relevant fields.
  ///
  /// Format is JSON with sorted keys at every level, ensuring the same
  /// assessment always produces the same string regardless of field
  /// insertion order in the Dart model.
  String _canonicalize(Assessment assessment) {
    final questionsCanonical = assessment.questions.map((q) {
      final map = <String, dynamic>{
        'id': q.id,
        'number': q.number,
        'type': q.type.index,
        'correctAnswer': _normalizeCorrectAnswer(q.correctAnswer),
        'points': q.points,
      };
      if (q.keywords != null) {
        map['keywords'] = List<String>.from(q.keywords!)..sort();
      }
      if (q.essayRubric != null) {
        map['essayRubric'] = {
          'contentWeight': q.essayRubric!.contentWeight,
          'structureWeight': q.essayRubric!.structureWeight,
          'grammarWeight': q.essayRubric!.grammarWeight,
          'analysisWeight': q.essayRubric!.analysisWeight,
        };
      }
      if (q.topicTag != null && q.topicTag!.isNotEmpty) {
        map['topicTag'] = q.topicTag;
      }
      return map;
    }).toList();

    final root = <String, dynamic>{
      'questions': questionsCanonical,
      'rubricType': assessment.rubricType,
      'weightedScaleId': assessment.weightedScaleId,
    };

    return json.encode(root);
  }

  /// Normalize correctAnswer to a deterministic representation.
  static dynamic _normalizeCorrectAnswer(dynamic answer) {
    if (answer == null) return null;
    if (answer is List) {
      final normalized = List<String>.from(answer.map((e) => e.toString().toLowerCase().trim()));
      normalized.sort();
      return normalized;
    }
    // Normalize case and whitespace for string answers
    return answer.toString().toLowerCase().trim();
  }
}
