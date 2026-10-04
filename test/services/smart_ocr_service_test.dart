import 'package:ethiograde/services/smart_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProxyResponse', () {
    test('flags auth failures for 401 and 403', () {
      expect(const ProxyResponse('bad key', 401).isAuthFailure, isTrue);
      expect(const ProxyResponse('bad key', 403).isAuthFailure, isTrue);
      expect(const ProxyResponse('boom', 500).isAuthFailure, isFalse);
    });

    test('flags rate limiting for 429 only', () {
      expect(const ProxyResponse('slow down', 429).isRateLimit, isTrue);
      expect(const ProxyResponse('boom', 500).isRateLimit, isFalse);
    });
  });

  group('buildCloudOcrResult', () {
    Map<String, dynamic> row(
      int number, [
      String answer = 'A',
      double confidence = 0.9,
    ]) =>
        {
          'questionNumber': number,
          'detectedAnswer': answer,
          'confidence': confidence,
        };

    test('returns null for an empty reply', () {
      expect(buildCloudOcrResult(const []), isNull);
    });

    test('returns null when every row is unusable', () {
      expect(
        buildCloudOcrResult([
          row(0),
          {'questionNumber': 'abc', 'detectedAnswer': 'A'},
          row(1, '   '),
        ]),
        isNull,
      );
    });

    test('creates one self-labelled block per question', () {
      final result = buildCloudOcrResult([row(1), row(2), row(3)]);

      expect(result, isNotNull);
      expect(result!.blocks, hasLength(3));
      expect(result.blocks[0].text, '1. A');
      expect(result.blocks[1].text, '2. A');
      expect(result.blocks[2].text, '3. A');
    });

    test('positions blocks in a top-to-bottom column by question number', () {
      final result = buildCloudOcrResult([row(3), row(1), row(2)])!;

      expect(result.blocks.map((b) => b.text).toList(),
          ['1. A', '2. A', '3. A']);
      expect(result.blocks[0].y, 1 * kCloudBlockLineHeight);
      expect(result.blocks[1].y, 2 * kCloudBlockLineHeight);
      expect(result.blocks[2].y, 3 * kCloudBlockLineHeight);
    });

    test('keeps short answers verbatim', () {
      final result =
          buildCloudOcrResult([row(16, 'Addis Ababa'), row(17, '42 km')]);

      expect(result!.blocks[0].text, '16. Addis Ababa');
      expect(result.blocks[1].text, '17. 42 km');
      expect(result.text, '16. Addis Ababa\n17. 42 km');
    });

    test('drops questions the model could not read', () {
      final result =
          buildCloudOcrResult([row(1), row(2, ''), row(3, 'C')]);

      expect(result!.blocks, hasLength(2));
      expect(result.blocks.map((b) => b.text).toList(), ['1. A', '3. C']);
    });

    test('de-duplicates repeated question numbers, first wins', () {
      final result = buildCloudOcrResult([
        row(1, 'A'),
        row(1, 'B'),
      ]);

      expect(result!.blocks, hasLength(1));
      expect(result.blocks.single.text, '1. A');
    });

    test('accepts numeric strings for question numbers', () {
      final result = buildCloudOcrResult([
        {'questionNumber': '5', 'detectedAnswer': 'D', 'confidence': 0.8},
      ]);

      expect(result!.blocks.single.text, '5. D');
    });

    test('flags handwriting and averages confidence', () {
      final result = buildCloudOcrResult([
        row(1, 'A', 0.8),
        row(2, 'B', 0.6),
      ]);

      expect(result!.source, OcrSource.cloud);
      expect(result.isHandwriting, isTrue);
      expect(result.confidence, closeTo(0.7, 1e-9));
    });

    test('routes low-confidence readings to teacher review', () {
      final mixed = buildCloudOcrResult([
        row(1, 'A', 0.95),
        row(2, 'B', 0.3),
      ]);
      expect(mixed!.needsReview, isTrue);

      final clean = buildCloudOcrResult([
        row(1, 'A', 0.95),
        row(2, 'B', 0.9),
      ]);
      expect(clean!.needsReview, isFalse);
    });

    test('clamps out-of-range confidence into 0..1', () {
      final result = buildCloudOcrResult([
        row(1, 'A', 5.0),
        row(2, 'B', -3.0),
      ]);

      expect(result!.blocks[0].confidence, 1.0);
      expect(result.blocks[1].confidence, 0.0);
      expect(result.needsReview, isTrue);
    });

    test('defaults a missing confidence to 0.5', () {
      final result = buildCloudOcrResult([
        {'questionNumber': 1, 'detectedAnswer': 'A'},
      ]);

      expect(result!.blocks.single.confidence, 0.5);
    });
  });

  group('GradingResult', () {
    test('computes percentage from score over max', () {
      final result = GradingResult.fromJson({
        'results': [],
        'overallScore': 18,
        'maxScore': 20,
        'confidence': 0.9,
      });

      expect(result.percentage, closeTo(90, 1e-9));
    });

    test('percentage is zero when maxScore is zero', () {
      final result = GradingResult.fromJson({
        'results': [],
        'overallScore': 0,
        'maxScore': 0,
        'confidence': 0,
      });

      expect(result.percentage, 0);
    });

    test('tolerates a reply with no fields at all', () {
      final result = GradingResult.fromJson(const {});

      expect(result.results, isEmpty);
      expect(result.overallScore, 0);
      expect(result.maxScore, 0);
      expect(result.confidence, 0);
    });

    test('parses per-question results with string numerics', () {
      final result = GradingResult.fromJson({
        'results': [
          {
            'questionNumber': '4',
            'detectedAnswer': 'B',
            'correctAnswer': 'B',
            'isCorrect': true,
            'score': '2',
            'maxScore': '2',
            'confidence': 0.97,
            'notes': 'clear',
          },
        ],
        'overallScore': 2,
        'maxScore': 2,
        'confidence': 0.9,
      });

      final q = result.results.single;
      expect(q.questionNumber, 4);
      expect(q.score, 2.0);
      expect(q.maxScore, 2.0);
      expect(q.isCorrect, isTrue);
      expect(q.notes, 'clear');
    });
  });

  group('CostSummary', () {
    test('reports budget usage and over-budget state', () {
      final summary = CostSummary.fromJson({
        'totalRequests': 120,
        'totalCost': 2.5,
        'monthlyBudget': 10.0,
        'period': '2026-10',
        'byProvider': {
          'gemini': {'requests': 120, 'cost': 2.5},
        },
      });

      expect(summary.totalRequests, 120);
      expect(summary.budgetUsedPercent, closeTo(25, 1e-9));
      expect(summary.isOverBudget, isFalse);
      expect(summary.byProvider['gemini']?.requests, 120);
    });

    test('is over budget when spend exceeds the limit', () {
      final summary = CostSummary.fromJson({
        'totalCost': 12.0,
        'monthlyBudget': 10.0,
      });

      expect(summary.isOverBudget, isTrue);
      expect(summary.budgetUsedPercent, closeTo(100, 1e-9));
    });

    test('falls back to a default budget when none is set', () {
      final summary = CostSummary.fromJson(const {});

      expect(summary.monthlyBudget, 10.0);
      expect(summary.period, 'all-time');
    });
  });

  group('ModelInfo', () {
    test('parses a server model entry', () {
      final info = ModelInfo.fromJson({
        'name': 'gemini',
        'displayName': 'Gemini 2.0 Flash',
        'isAvailable': true,
        'costPer1k': 0.15,
        'latencyMs': 3000,
      });

      expect(info.name, 'gemini');
      expect(info.isAvailable, isTrue);
      expect(info.costPer1k, 0.15);
      expect(info.latencyMs, 3000);
    });

    test('defaults isAvailable to false when absent', () {
      expect(ModelInfo.fromJson(const {}).isAvailable, isFalse);
    });
  });

  group('SmartOcrResult', () {
    test('copyWith preserves untouched fields', () {
      const original = SmartOcrResult(
        text: 'hello',
        blocks: [],
        confidence: 0.5,
        source: OcrSource.cloud,
        isHandwriting: true,
        needsReview: true,
      );

      final updated = original.copyWith(confidence: 0.9);

      expect(updated.confidence, 0.9);
      expect(updated.text, 'hello');
      expect(updated.source, OcrSource.cloud);
      expect(updated.isHandwriting, isTrue);
      expect(updated.needsReview, isTrue);
    });

    test('empty result is empty and not flagged', () {
      final empty = SmartOcrResult.empty();

      expect(empty.isEmpty, isTrue);
      expect(empty.isNotEmpty, isFalse);
      expect(empty.confidence, 0);
      expect(empty.needsReview, isFalse);
    });
  });
}