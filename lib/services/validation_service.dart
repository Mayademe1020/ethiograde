import '../models/student.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';
import '../models/teacher.dart';

/// Result of a validation check.
/// [isValid] is true when [errors] is empty.
class ValidationResult {
  final bool isValid;
  final List<String> errors;

  const ValidationResult._(this.isValid, this.errors);

  const ValidationResult.valid() : isValid = true, errors = const [];

  const ValidationResult.invalid(List<String> errors)
      : isValid = false,
        errors = errors;

  @override
  String toString() => isValid
      ? 'ValidationResult.valid'
      : 'ValidationResult.invalid($errors)';
}

/// Pure-Dart model validator. Providers call this before every Hive write.
///
/// No platform dependencies — independently testable.
class ValidationService {
  const ValidationService();

  // ── Student ───────────────────────────────────────────────────────

  static const int _maxNameLength = 100;

  /// Validate a [Student] before persisting.
  ValidationResult validateStudent(Student student) {
    final errors = <String>[];

    // Name: not empty, not whitespace-only
    final fullName = student.fullName.trim();
    if (fullName.isEmpty) {
      errors.add('Student name cannot be empty');
    } else if (fullName.length > _maxNameLength) {
      errors.add('Student name cannot exceed $_maxNameLength characters '
          '(${fullName.length} given)');
    }

    // Grade: 1–12 or "University" (stored as 0 or -1)
    if (student.grade < 0 || student.grade > 12) {
      errors.add('Grade must be between 1 and 12, or 0 for University '
          '(${student.grade} given)');
    }

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  // ── Teacher ────────────────────────────────────────────────────────

  /// Validate a [Teacher] before persisting.
  ValidationResult validateTeacher(Teacher teacher) {
    final errors = <String>[];

    // Name: not empty, not whitespace-only
    if (teacher.name.trim().isEmpty) {
      errors.add('Teacher name cannot be empty');
    } else if (teacher.name.trim().length > _maxNameLength) {
      errors.add('Teacher name cannot exceed $_maxNameLength characters '
          '(${teacher.name.trim().length} given)');
    }

    // Phone: if provided, must look like a phone number
    if (teacher.phone.trim().isNotEmpty) {
      final digits = teacher.phone.replaceAll(RegExp(r'[\s\-\+]'), '');
      if (digits.length < 7 || digits.length > 15) {
        errors.add('Phone number must be 7–15 digits');
      }
    }

    // Email: if provided, basic format check
    if (teacher.email.trim().isNotEmpty) {
      final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
      if (!emailRegex.hasMatch(teacher.email.trim())) {
        errors.add('Invalid email format');
      }
    }

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  // ── Assessment ────────────────────────────────────────────────────

  static const Set<String> _validMcqAnswers = {
    'A', 'B', 'C', 'D', 'E',
  };
  static const Set<String> _validTfAnswers = {
    'True', 'False',
  };

  /// Validate an [Assessment] before persisting.
  ValidationResult validateAssessment(Assessment assessment) {
    final errors = <String>[];

    // Title
    if (assessment.title.trim().isEmpty) {
      errors.add('Assessment title cannot be empty');
    }

    // Questions: at least one
    if (assessment.questions.isEmpty) {
      errors.add('Assessment must have at least one question');
    }

    // Validate each question's correct answer
    for (final q in assessment.questions) {
      if (q.correctAnswer == null) {
        errors.add('Question ${q.number}: correct answer is missing');
        continue;
      }

      switch (q.type) {
        case QuestionType.mcq:
          final answer = q.correctAnswer.toString().toUpperCase().trim();
          if (!_validMcqAnswers.contains(answer)) {
            errors.add('Question ${q.number}: invalid MCQ answer '
                '"${q.correctAnswer}" (expected A–E)');
          }
        case QuestionType.trueFalse:
          final answer = _normalizeTf(q.correctAnswer.toString());
          if (!_validTfAnswers.contains(answer)) {
            errors.add('Question ${q.number}: invalid True/False answer '
                '"${q.correctAnswer}"');
          }
        case QuestionType.shortAnswer:
          // Accept any non-empty string or list
          if (q.correctAnswer is String &&
              (q.correctAnswer as String).trim().isEmpty) {
            errors.add('Question ${q.number}: short answer cannot be empty');
          }
        case QuestionType.essay:
          // Essays don't have a single correct answer — skip
          break;
      }
    }

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  /// Helper: normalise "true"/"false" casing.
  static String _normalizeTf(String value) {
    final lower = value.toLowerCase().trim();
    if (lower == 'true') return 'True';
    if (lower == 'false') return 'False';
    return value;
  }

  // ── ScanResult ────────────────────────────────────────────────────

  /// Validate a [ScanResult] before persisting.
  ValidationResult validateScanResult(ScanResult scan) {
    final errors = <String>[];

    // Score: non-negative
    if (scan.totalScore < 0) {
      errors.add('Total score cannot be negative (${scan.totalScore})');
    }

    // Score: cannot exceed max
    if (scan.maxScore > 0 && scan.totalScore > scan.maxScore) {
      errors.add('Total score (${scan.totalScore}) exceeds '
          'max score (${scan.maxScore})');
    }

    // Confidence: 0.0–1.0
    if (scan.confidence < 0 || scan.confidence > 1) {
      errors.add('Confidence must be between 0.0 and 1.0 '
          '(${scan.confidence})');
    }

    // Percentage: 0–100
    if (scan.percentage < 0 || scan.percentage > 100) {
      errors.add('Percentage must be between 0 and 100 '
          '(${scan.percentage})');
    }

    // Assessment / student IDs
    if (scan.assessmentId.isEmpty) {
      errors.add('Assessment ID cannot be empty');
    }
    if (scan.studentId.isEmpty) {
      errors.add('Student ID cannot be empty');
    }

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }
}
