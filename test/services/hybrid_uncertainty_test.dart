import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/scan_result.dart';
import 'package:ethiograde/services/hybrid_grading_service.dart';
import 'package:ethiograde/services/scoring_service.dart';

void main() {
  Assessment makeAssessment({List<Question>? questions}) {
    return Assessment(
      title: 'Test',
      subject: 'English',
      questions:
          questions ??
          [
            Question(
              id: 'q16',
              number: 16,
              type: QuestionType.shortAnswer,
              correctAnswer: 'Addis Ababa',
              points: 1,
            ),
            Question(
              id: 'q1',
              number: 1,
              type: QuestionType.mcq,
              correctAnswer: 'A',
              points: 1,
            ),
          ],
    );
  }

  group('HybridGradingService.uncertainQuestionNumbers (pure function)', () {
    test('spatially-associated short answer is collected', () {
      final detected = [
        const DetectedAnswer(
          questionNumber: 16,
          answer: 'Addis Ababa',
          confidence: 0.9,
          rawText: '16 Addis Ababa',
          needsReview: true,
          source: 'ocr-spatial',
        ),
      ];

      final uncertain = HybridGradingService.uncertainQuestionNumbers(
        detected: detected,
        assessment: makeAssessment(),
      );
      expect(uncertain, {16});
    });

    test('sub-floor-confidence same-line short answer is collected', () {
      final detected = [
        const DetectedAnswer(
          questionNumber: 16,
          answer: 'Addis Ababa',
          confidence: 0.3, // retained between 0.25 and 0.5 floors
          rawText: '16. Addis Ababa',
          source: 'ocr',
        ),
      ];

      expect(
        HybridGradingService.uncertainQuestionNumbers(
          detected: detected,
          assessment: makeAssessment(),
        ),
        {16},
      );
    });

    test('high-confidence same-line short answer is NOT flagged here', () {
      final detected = [
        const DetectedAnswer(
          questionNumber: 16,
          answer: 'Addis Ababa',
          confidence: 0.88,
          rawText: '16. Addis Ababa',
          source: 'ocr',
        ),
      ];

      expect(
        HybridGradingService.uncertainQuestionNumbers(
          detected: detected,
          assessment: makeAssessment(),
        ),
        isEmpty,
      );
    });

    test('objective questions are never collected (behavior unchanged)', () {
      final detected = [
        const DetectedAnswer(
          questionNumber: 1,
          answer: 'B',
          confidence: 0.3,
          rawText: '1 B',
          needsReview: true,
          source: 'omr-low-confidence',
        ),
      ];

      expect(
        HybridGradingService.uncertainQuestionNumbers(
          detected: detected,
          assessment: makeAssessment(),
        ),
        isEmpty,
      );
    });

    test('unknown question numbers are ignored', () {
      final detected = [
        const DetectedAnswer(
          questionNumber: 99,
          answer: 'Noise',
          confidence: 0.2,
          rawText: '99 Noise',
          needsReview: true,
          source: 'ocr-spatial',
        ),
      ];

      expect(
        HybridGradingService.uncertainQuestionNumbers(
          detected: detected,
          assessment: makeAssessment(),
        ),
        isEmpty,
      );
    });
  });

  group('ScanResult uncertainty gating (metadata-based, no schema change)', () {
    ScanResult makeResult(Map<String, dynamic> metadata) {
      return ScanResult(
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Test Student',
        imagePath: '/img.jpg',
        answers: [
          AnswerMatch(
            questionNumber: 16,
            detectedAnswer: 'Addis Ababa',
            correctAnswer: 'Addis Ababa',
            isCorrect: true,
            score: 1,
            maxScore: 1,
            confidence: 0.92,
          ),
        ],
        totalScore: 1,
        maxScore: 1,
        percentage: 100,
        grade: 'A+',
        status: ScanStatus.graded,
        confidence: 0.92, // high â€” gating must come from metadata alone
        metadata: metadata,
      );
    }

    test('uncertainQuestions in metadata drives needsReview', () {
      final result = makeResult({
        'detectedMethod': 'ocr-only',
        'uncertainQuestions': <int>[16],
      });
      expect(result.uncertainQuestions, {16});
      expect(result.needsReview, isTrue);
      expect(result.requiresTeacherAction, isTrue);
    });

    test(
      'metadata list of dynamic ints is tolerated after Hive round-trip',
      () {
        final result = makeResult({
          'uncertainQuestions': <dynamic>['16', 17],
        });
        expect(result.uncertainQuestions, {16, 17});
      },
    );

    test('resolved results do not require action despite uncertainty flag', () {
      final result = makeResult({
        'uncertainQuestions': <int>[16],
        'teacherReviewed': true,
      });
      expect(result.isResolved, isTrue);
      expect(result.requiresTeacherAction, isFalse);
    });

    test('legacy results without the key behave exactly as before', () {
      final result = makeResult({'detectedMethod': 'hybrid'});
      expect(result.uncertainQuestions, isEmpty);
      expect(result.needsReview, isFalse);
      expect(result.requiresTeacherAction, isFalse);
    });
  });

  group('ScanResult.preserveOriginalOcrRead (teacher-edit preservation)', () {
    test('stores the first original reading per question', () {
      final metadata = ScanResult.preserveOriginalOcrRead(
        {'detectedMethod': 'ocr-only'},
        16,
        '(OCR line) Photosynthesls',
      );
      expect(metadata['originalOcrReads'], {'16': '(OCR line) Photosynthesls'});
    });

    test('later edits never overwrite the earliest reading', () {
      var metadata = ScanResult.preserveOriginalOcrRead(const {}, 16, 'first');
      metadata = ScanResult.preserveOriginalOcrRead(metadata, 16, 'second');
      expect(metadata['originalOcrReads'], {'16': 'first'});
    });

    test('falls back to detectedAnswer when ocrRawText was empty', () {
      // Callers pass original.detectedAnswer when raw text is null/empty;
      // helper only rejects truly empty strings.
      final metadata = ScanResult.preserveOriginalOcrRead(const {}, 3, 'B');
      expect(metadata['originalOcrReads'], {'3': 'B'});
    });

    test('empty read is ignored (no junk entries)', () {
      final metadata = ScanResult.preserveOriginalOcrRead(const {}, 3, '');
      expect(metadata.containsKey('originalOcrReads'), isTrue);
      expect((metadata['originalOcrReads'] as Map), isEmpty);
    });

    test('does not mutate the input map', () {
      final input = <String, dynamic>{'detectedMethod': 'hybrid'};
      ScanResult.preserveOriginalOcrRead(input, 16, 'Photosynthesls');
      expect(input.containsKey('originalOcrReads'), isFalse);
    });

    test('existing keys are preserved alongside new data', () {
      final metadata = ScanResult.preserveOriginalOcrRead(
        {'ik_scoredWithKeyFingerprint': 'abc'},
        2,
        'True',
      );
      expect(metadata['ik_scoredWithKeyFingerprint'], 'abc');
      expect(metadata['originalOcrReads'], {'2': 'True'});
    });
  });

  group(
    'Phase 1 end-to-end uncertainty propagation (DetectedAnswer â†’ gating)',
    () {
      test(
        'spatial detection reaches ScanResult review gating via scoring',
        () {
          // Simulates the pipeline stage hand-off without images:
          // spatial parse â†’ DetectedAnswer(needsReview) â†’ uncertain set â†’
          // metadata â†’ ScanResult getter.
          const detected = [
            DetectedAnswer(
              questionNumber: 16,
              answer: 'Addis Ababa',
              confidence: 0.85,
              rawText: '16 Addis Ababa',
              needsReview: true,
              source: 'ocr-spatial',
            ),
          ];
          final assessment = makeAssessment();

          final uncertain = HybridGradingService.uncertainQuestionNumbers(
            detected: detected,
            assessment: assessment,
          );

          final scored = const ScoringService().scoreAnswers(
            detected: detected,
            assessment: assessment,
          );

          expect(scored.first.isCorrect, isTrue); // graded automaticallyâ€¦
          final result = ScanResult(
            assessmentId: assessment.id,
            studentId: 's1',
            studentName: 'T',
            imagePath: '/i.jpg',
            answers: scored,
            totalScore: 1,
            maxScore: 1,
            percentage: 100,
            grade: 'A+',
            status: ScanStatus.graded,
            confidence: 0.85,
            metadata: uncertain.isEmpty
                ? const {}
                : {'uncertainQuestions': uncertain.toList()..sort()},
          );
          // â€¦but still flagged for teacher confirmation.
          expect(result.needsReview, isTrue);
          expect(result.requiresTeacherAction, isTrue);
        },
      );
    },
  );

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // Phase 1.1 â€” Option B: fuzzy-only short-answer matches â†’ NEEDS REVIEW
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  group('HybridGradingService.fuzzyOnlyReviewQuestions (Option B)', () {
    test('distance-2 fuzzy-only scored match is collected', () {
      final assessment = makeAssessment(); // Q16 â†’ 'Addis Ababa'
      const scoring = ScoringService();
      final scored = scoring.scoreAnswers(
        detected: const [
          DetectedAnswer(
            questionNumber: 16,
            answer: 'Addis Abena', // distance 2
            confidence: 0.9,
            rawText: '16. Addis Abena',
          ),
        ],
        assessment: assessment,
      );

      expect(
        scored.firstWhere((m) => m.questionNumber == 16).isCorrect,
        isTrue,
      ); // provisional
      expect(
        HybridGradingService.fuzzyOnlyReviewQuestions(
          scored: scored,
          assessment: assessment,
        ),
        {16},
      );
    });

    test('exact normalized match is NOT collected â†’ auto CORRECT', () {
      final assessment = makeAssessment();
      const scoring = ScoringService();
      final scored = scoring.scoreAnswers(
        detected: const [
          DetectedAnswer(
            questionNumber: 16,
            answer: 'addis ababa', // normalization makes this exact
            confidence: 0.9,
            rawText: '16. addis ababa',
          ),
        ],
        assessment: assessment,
      );

      expect(
        scored.firstWhere((m) => m.questionNumber == 16).isCorrect,
        isTrue,
      );
      expect(
        HybridGradingService.fuzzyOnlyReviewQuestions(
          scored: scored,
          assessment: assessment,
        ),
        isEmpty,
      );
    });

    test('clearly different answer is NOT collected â†’ stays INCORRECT', () {
      final assessment = makeAssessment();
      const scoring = ScoringService();
      final scored = scoring.scoreAnswers(
        detected: const [
          DetectedAnswer(
            questionNumber: 16,
            answer: 'Nairobi',
            confidence: 0.9,
            rawText: '16. Nairobi',
          ),
        ],
        assessment: assessment,
      );

      expect(
        scored.firstWhere((m) => m.questionNumber == 16).isCorrect,
        isFalse,
      );
      expect(
        HybridGradingService.fuzzyOnlyReviewQuestions(
          scored: scored,
          assessment: assessment,
        ),
        isEmpty,
      );
    });

    test('objective questions are excluded even when strings are close', () {
      final assessment = makeAssessment(); // Q1 MCQ 'A'
      final scored = [
        AnswerMatch(
          questionNumber: 1,
          detectedAnswer: 'A',
          correctAnswer: 'A',
          isCorrect: true,
          score: 1,
          maxScore: 1,
          confidence: 0.95,
        ),
      ];

      expect(
        HybridGradingService.fuzzyOnlyReviewQuestions(
          scored: scored,
          assessment: assessment,
        ),
        isEmpty,
        reason: 'MCQ/T-F/OMR behavior must remain unchanged (scope guard)',
      );
    });

    test(
      'list-type answer keys: fuzzy-only against any option is collected',
      () {
        final assessment = makeAssessment(
          questions: [
            Question(
              id: 'q5',
              number: 5,
              type: QuestionType.shortAnswer,
              correctAnswer: ['Nile River', 'River Nile'],
              points: 1,
            ),
          ],
        );
        final scored = [
          AnswerMatch(
            questionNumber: 5,
            detectedAnswer: 'Nile Riber', // distance 1 from option 1
            correctAnswer: '[Nile River, River Nile]',
            isCorrect: true, // matched via fuzzy in checkAnswer
            score: 1,
            maxScore: 1,
            confidence: 0.88,
          ),
        ];

        expect(
          HybridGradingService.fuzzyOnlyReviewQuestions(
            scored: scored,
            assessment: assessment,
          ),
          {5},
        );
      },
    );

    test('missing/unreadable sentinels are ignored', () {
      final assessment = makeAssessment();
      final scored = [
        AnswerMatch(
          questionNumber: 16,
          detectedAnswer: '[MISSING]',
          correctAnswer: 'Addis Ababa',
          isCorrect: false,
          score: 0,
          maxScore: 1,
          confidence: 0,
        ),
      ];

      expect(
        HybridGradingService.fuzzyOnlyReviewQuestions(
          scored: scored,
          assessment: assessment,
        ),
        isEmpty,
      );
    });
  });

  group(
    'Phase 1.1 end-to-end: fuzzy-only NEEDS REVIEW survives into ScanResult '
    'and review gating',
    () {
      test(
        'distance-1 misread routes to review despite high OCR confidence',
        () {
          final assessment = makeAssessment(
            questions: [
              Question(
                id: 'q16',
                number: 16,
                type: QuestionType.shortAnswer,
                correctAnswer: 'Photosynthesis',
                points: 1,
              ),
            ],
          );
          const detected = [
            DetectedAnswer(
              questionNumber: 16,
              answer: 'Photosynthesls', // distance 1
              confidence: 0.93, // printed-quality read of a handwriting error
              rawText: '16. Photosynthesls',
            ),
          ];

          final scored = const ScoringService().scoreAnswers(
            detected: detected,
            assessment: assessment,
          );
          expect(
            scored.firstWhere((m) => m.questionNumber == 16).isCorrect,
            isTrue,
          ); // provisional CORRECTâ€¦

          final flags = HybridGradingService.fuzzyOnlyReviewQuestions(
            scored: scored,
            assessment: assessment,
          );
          expect(flags, {16});

          final result = ScanResult(
            assessmentId: assessment.id,
            studentId: 's1',
            studentName: 'T',
            imagePath: '/i.jpg',
            answers: scored,
            totalScore: 1,
            maxScore: 1,
            percentage: 100,
            grade: 'A+',
            status: ScanStatus.graded,
            confidence: 0.93, // high â€” gating MUST come from the flag
            metadata: {
              'detectedMethod': 'ocr-only',
              'uncertainQuestions': flags.toList()..sort(),
            },
          );

          // The critical Option B assertion: NOT silently graded.
          expect(result.needsReview, isTrue);
          expect(result.requiresTeacherAction, isTrue);

          // Teacher resolves â†’ gating clears.
          final resolved = result.copyWith(
            metadata: {...result.metadata, 'teacherReviewed': true},
          );
          expect(resolved.requiresTeacherAction, isFalse);
        },
      );
    },
  );
}
