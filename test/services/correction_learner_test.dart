import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ethiograde/services/correction_learner.dart';

void main() {
  late Box box;

  setUpAll(() async {
    // Init Hive for tests
    Hive.init('test_hive');
  });

  setUp(() async {
    box = await Hive.openBox('correction_patterns');
    await box.clear();
  });

  tearDown(() async {
    await box.clear();
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
  });

  // ─── Pattern Model ───

  group('CorrectionPattern', () {
    test('toMap and fromMap round-trip', () {
      final pattern = CorrectionPattern(
        key: 'Q5:C',
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D',
        count: 3,
        lastCorrected: DateTime(2026, 4, 4));

      final map = pattern.toMap();
      final restored = CorrectionPattern.fromMap(map);

      expect(restored.key, 'Q5:C');
      expect(restored.questionNumber, 5);
      expect(restored.originalAnswer, 'C');
      expect(restored.correctedAnswer, 'D');
      expect(restored.count, 3);
    });
  });

  // ─── Record Correction ───

  group('CorrectionLearner.recordCorrection', () {
    test('records a new correction pattern', () async {
      final learner = CorrectionLearner();
      await learner.initialize();

      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');

      expect(learner.patternCount, 1);
    });

    test('increments count for same correction', () async {
      final learner = CorrectionLearner();
      await learner.initialize();

      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');
      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');

      expect(learner.patternCount, 1); // same key, not 2

      final patterns = learner.getPatternsForQuestion(5);
      expect(patterns.length, 1);
      expect(patterns.first.count, 2);
    });

    test('ignores corrections where original == corrected', () async {
      final learner = CorrectionLearner();
      await learner.initialize();

      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'C');

      expect(learner.patternCount, 0);
    });

    test('replaces pattern when correction direction changes', () async {
      final learner = CorrectionLearner();
      await learner.initialize();

      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');
      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'B', // different direction
      );

      final patterns = learner.getPatternsForQuestion(5);
      expect(patterns.length, 1);
      expect(patterns.first.correctedAnswer, 'B');
      expect(patterns.first.count, 1); // reset to 1
    });

    test('case-insensitive keys', () async {
      final learner = CorrectionLearner();
      await learner.initialize();

      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'c',
        correctedAnswer: 'd');
      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');

      // Both should map to Q5:C
      expect(learner.patternCount, 1);
      final patterns = learner.getPatternsForQuestion(5);
      expect(patterns.first.count, 2);
    });
  });

  // ─── Get Suggestion ───

  group('CorrectionLearner.getSuggestion', () {
    test('returns null when no pattern exists', () {
      final learner = CorrectionLearner();
      final suggestion = learner.getSuggestion(
        questionNumber: 1,
        detectedAnswer: 'A');
      expect(suggestion, isNull);
    });

    test('returns null when count < minCount', () async {
      final learner = CorrectionLearner();
      await learner.initialize();

      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');

      final suggestion = learner.getSuggestion(
        questionNumber: 5,
        detectedAnswer: 'C',
        minCount: 2);
      expect(suggestion, isNull);
    });

    test('returns suggestion when count >= minCount', () async {
      final learner = CorrectionLearner();
      await learner.initialize();

      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');
      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');

      final suggestion = learner.getSuggestion(
        questionNumber: 5,
        detectedAnswer: 'C',
        minCount: 2);
      expect(suggestion, 'D');
    });

    test('custom minCount works', () async {
      final learner = CorrectionLearner();
      await learner.initialize();

      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');

      // With minCount=1, should return suggestion
      final suggestion = learner.getSuggestion(
        questionNumber: 5,
        detectedAnswer: 'C',
        minCount: 1);
      expect(suggestion, 'D');
    });
  });

  // ─── Strong Patterns ───

  group('CorrectionLearner.getStrongPatterns', () {
    test('returns only patterns with count >= minCount', () async {
      final learner = CorrectionLearner();
      await learner.initialize();

      // Strong pattern (count 2)
      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');
      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');

      // Weak pattern (count 1)
      await learner.recordCorrection(
        questionNumber: 10,
        originalAnswer: 'A',
        correctedAnswer: 'B');

      final strong = learner.getStrongPatterns(minCount: 2);
      expect(strong.length, 1);
      expect(strong.first.questionNumber, 5);
    });

    test('sorts by count descending', () async {
      final learner = CorrectionLearner();
      await learner.initialize();

      // Q5: count 2
      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');
      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');

      // Q10: count 3
      await learner.recordCorrection(
        questionNumber: 10,
        originalAnswer: 'A',
        correctedAnswer: 'B');
      await learner.recordCorrection(
        questionNumber: 10,
        originalAnswer: 'A',
        correctedAnswer: 'B');
      await learner.recordCorrection(
        questionNumber: 10,
        originalAnswer: 'A',
        correctedAnswer: 'B');

      final strong = learner.getStrongPatterns(minCount: 2);
      expect(strong.first.questionNumber, 10); // highest count first
      expect(strong.last.questionNumber, 5);
    });
  });

  // ─── Clear ───

  group('CorrectionLearner.clearAll', () {
    test('removes all patterns', () async {
      final learner = CorrectionLearner();
      await learner.initialize();

      await learner.recordCorrection(
        questionNumber: 1,
        originalAnswer: 'A',
        correctedAnswer: 'B');
      await learner.recordCorrection(
        questionNumber: 2,
        originalAnswer: 'C',
        correctedAnswer: 'D');

      expect(learner.patternCount, 2);

      await learner.clearAll();
      expect(learner.patternCount, 0);
    });
  });

  // ─── Remove Pattern ───

  group('CorrectionLearner.removePattern', () {
    test('removes single pattern by key', () async {
      final learner = CorrectionLearner();
      await learner.initialize();

      await learner.recordCorrection(
        questionNumber: 5,
        originalAnswer: 'C',
        correctedAnswer: 'D');
      expect(learner.patternCount, 1);

      await learner.removePattern('Q5:C');
      expect(learner.patternCount, 0);
    });
  });
}
