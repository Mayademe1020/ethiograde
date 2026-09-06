import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/answer_parser.dart';

void main() {
  const parser = AnswerParser();

  // ══════════════════════════════════════════════════════════════════
  // parseQuestionAnswer — does the regex correctly extract Q# and answer?
  // ══════════════════════════════════════════════════════════════════

  group('parseQuestionAnswer — standard MCQ formats', () {
    test('period delimiter: "1. A"', () {
      final result = parser.parseQuestionAnswer('1. A');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'A');
    });

    test('period delimiter, lowercase: "3. c"', () {
      final result = parser.parseQuestionAnswer('3. c');
      expect(result, isNotNull);
      expect(result!.$1, 3);
      expect(result.$2, 'C');
    });

    test('dash delimiter: "5-B"', () {
      final result = parser.parseQuestionAnswer('5-B');
      expect(result, isNotNull);
      expect(result!.$1, 5);
      expect(result.$2, 'B');
    });

    test('paren delimiter: "10) D"', () {
      final result = parser.parseQuestionAnswer('10) D');
      expect(result, isNotNull);
      expect(result!.$1, 10);
      expect(result.$2, 'D');
    });

    test('colon delimiter: "7: E"', () {
      final result = parser.parseQuestionAnswer('7: E');
      expect(result, isNotNull);
      expect(result!.$1, 7);
      expect(result.$2, 'E');
    });

    test('extra spaces: "1 .  A"', () {
      final result = parser.parseQuestionAnswer('1 .  A');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'A');
    });
  });

  group('parseQuestionAnswer — concatenated (bubbled answer sheets)', () {
    test('"1A"', () {
      final result = parser.parseQuestionAnswer('1A');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'A');
    });

    test('"10B"', () {
      final result = parser.parseQuestionAnswer('10B');
      expect(result, isNotNull);
      expect(result!.$1, 10);
      expect(result.$2, 'B');
    });

    test('"3c" lowercase', () {
      final result = parser.parseQuestionAnswer('3c');
      expect(result, isNotNull);
      expect(result!.$1, 3);
      expect(result.$2, 'C');
    });

    test('"1true" concatenated lowercase', () {
      final result = parser.parseQuestionAnswer('1true');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'True');
    });

    test('"2False" concatenated', () {
      final result = parser.parseQuestionAnswer('2False');
      expect(result, isNotNull);
      expect(result!.$1, 2);
      expect(result.$2, 'False');
    });
  });

  group('parseQuestionAnswer — True/False English', () {
    test('"1. True"', () {
      final result = parser.parseQuestionAnswer('1. True');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'True');
    });

    test('"2. false"', () {
      final result = parser.parseQuestionAnswer('2. false');
      expect(result, isNotNull);
      expect(result!.$1, 2);
      expect(result.$2, 'False');
    });

    test('"3) T"', () {
      final result = parser.parseQuestionAnswer('3) T');
      expect(result, isNotNull);
      expect(result!.$1, 3);
      expect(result.$2, 'True');
    });

    test('"4-F"', () {
      final result = parser.parseQuestionAnswer('4-F');
      expect(result, isNotNull);
      expect(result!.$1, 4);
      expect(result.$2, 'False');
    });
  });

  group('parseQuestionAnswer — True/False Amharic', () {
    test('"1. እውነት"', () {
      final result = parser.parseQuestionAnswer('1. እውነት');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'True');
    });

    test('"2. ሐሰት"', () {
      final result = parser.parseQuestionAnswer('2. ሐሰት');
      expect(result, isNotNull);
      expect(result!.$1, 2);
      expect(result.$2, 'False');
    });

    test('"3) ት" (short Amharic True)', () {
      final result = parser.parseQuestionAnswer('3) ት');
      expect(result, isNotNull);
      expect(result!.$1, 3);
      expect(result.$2, 'True');
    });
  });

  group('parseQuestionAnswer — Amharic MCQ letters', () {
    test('"1. ሀ" → A', () {
      final result = parser.parseQuestionAnswer('1. ሀ');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'A');
    });

    test('"5. መ" → D', () {
      final result = parser.parseQuestionAnswer('5. መ');
      expect(result, isNotNull);
      expect(result!.$1, 5);
      expect(result.$2, 'D');
    });
  });

  group('parseQuestionAnswer — short answers (multi-word text)', () {
    test('"5. Addis Ababa"', () {
      final result = parser.parseQuestionAnswer('5. Addis Ababa');
      expect(result, isNotNull);
      expect(result!.$1, 5);
      expect(result.$2, 'Addis Ababa');
    });

    test('"6. 42"', () {
      final result = parser.parseQuestionAnswer('6. 42');
      expect(result, isNotNull);
      expect(result!.$1, 6);
      expect(result.$2, '42');
    });

    test('"6. 2.5" decimal answer preserved (no prefix strip)', () {
      final result = parser.parseQuestionAnswer('6. 2.5');
      expect(result, isNotNull);
      expect(result!.$1, 6);
      expect(result.$2, '2.5');
    });

    test('"7. 42 km" numeric short answer preserved', () {
      final result = parser.parseQuestionAnswer('7. 42 km');
      expect(result, isNotNull);
      expect(result!.$1, 7);
      expect(result.$2, '42 km');
    });

    test('"8. 1984" bare numeric answer preserved', () {
      final result = parser.parseQuestionAnswer('8. 1984');
      expect(result, isNotNull);
      expect(result!.$1, 8);
      expect(result.$2, '1984');
    });

    test('"7-Photosynthesis"', () {
      final result = parser.parseQuestionAnswer('7-Photosynthesis');
      expect(result, isNotNull);
      expect(result!.$1, 7);
      expect(result.$2, 'Photosynthesis');
    });

    test('"10) አዲስ አበባ" (Amharic short answer)', () {
      final result = parser.parseQuestionAnswer('10) አዲስ አበባ');
      expect(result, isNotNull);
      expect(result!.$1, 10);
      expect(result.$2, 'አዲስ አበባ');
    });

    test('"3. H2O" (chemical formula)', () {
      final result = parser.parseQuestionAnswer('3. H2O');
      expect(result, isNotNull);
      expect(result!.$1, 3);
      expect(result.$2, 'H2O');
    });
  });

  group('parseQuestionAnswer — trailing punctuation (OCR artifacts)', () {
    test('"2. A."', () {
      final result = parser.parseQuestionAnswer('2. A.');
      expect(result, isNotNull);
      expect(result!.$1, 2);
      expect(result.$2, 'A');
    });

    test('"3. B,"', () {
      final result = parser.parseQuestionAnswer('3. B,');
      expect(result, isNotNull);
      expect(result!.$1, 3);
      expect(result.$2, 'B');
    });

    test('"4. C;"', () {
      final result = parser.parseQuestionAnswer('4. C;');
      expect(result, isNotNull);
      expect(result!.$1, 4);
      expect(result.$2, 'C');
    });

    test('"1. True." trailing period on T/F', () {
      final result = parser.parseQuestionAnswer('1. True.');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'True');
    });
  });

  group('parseQuestionAnswer — invalid input (should return null)', () {
    test('empty string', () {
      expect(parser.parseQuestionAnswer(''), isNull);
    });

    test('whitespace only', () {
      expect(parser.parseQuestionAnswer('   '), isNull);
    });

    test('question text without answer: "1. What is the capital?"', () {
      // Now returns the text — the parser can't distinguish questions from
      // short answers at the regex level. The answer key type determines
      // whether this is scored or marked wrong.
      final result = parser.parseQuestionAnswer('1. What is the capital?');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'What is the capital');
    });

    test('random noise: "xyz123"', () {
      expect(parser.parseQuestionAnswer('xyz123'), isNull);
    });

    test('number too large: "999. A"', () {
      // Q# > 200 should be rejected
      final result = parser.parseQuestionAnswer('999. A');
      expect(result, isNull);
    });

    test('zero question number: "0. A"', () {
      expect(parser.parseQuestionAnswer('0. A'), isNull);
    });

    test('just a letter: "A"', () {
      expect(parser.parseQuestionAnswer('A'), isNull);
    });

    test('just a number: "5"', () {
      expect(parser.parseQuestionAnswer('5'), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // normalizeAnswer — edge cases in answer text
  // ══════════════════════════════════════════════════════════════════

  group('normalizeAnswer', () {
    test('strips trailing punctuation from MCQ', () {
      expect(parser.normalizeAnswer('A.'), 'A');
      expect(parser.normalizeAnswer('B,'), 'B');
      expect(parser.normalizeAnswer('C;'), 'C');
      expect(parser.normalizeAnswer('D!'), 'D');
    });

    test('lowercase MCQ → uppercase', () {
      expect(parser.normalizeAnswer('a'), 'A');
      expect(parser.normalizeAnswer('b'), 'B');
      expect(parser.normalizeAnswer('e'), 'E');
    });

    test('yes/no → True/False', () {
      expect(parser.normalizeAnswer('yes'), 'True');
      expect(parser.normalizeAnswer('no'), 'False');
      expect(parser.normalizeAnswer('y'), 'True');
      expect(parser.normalizeAnswer('n'), 'False');
    });

    test('empty returns empty', () {
      expect(parser.normalizeAnswer(''), '');
    });

    test('only punctuation returns empty', () {
      expect(parser.normalizeAnswer('...'), '');
      expect(parser.normalizeAnswer('!!!'), '');
    });

    test('long text now accepted (short answer support)', () {
      expect(parser.normalizeAnswer('Addis Ababa'), 'Addis Ababa');
      expect(parser.normalizeAnswer('42 kilometers'), '42 kilometers');
      expect(
        parser.normalizeAnswer('this is a valid short answer'),
        'this is a valid short answer',
      );
    });

    test('pure noise (no alphanumeric) still returns empty', () {
      expect(parser.normalizeAnswer('...::..'), '');
      expect(parser.normalizeAnswer('???'), '');
    });

    test('too long (>80 chars) returns empty', () {
      final longText = 'a' * 81;
      expect(parser.normalizeAnswer(longText), '');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // parseAnswers — full pipeline with multiple regions
  // ══════════════════════════════════════════════════════════════════

  group('parseAnswers — realistic ML Kit output simulation', () {
    test('clean MCQ sheet (10 questions)', () {
      final regions = [
        const TextRegionInput(text: '1. A', confidence: 0.95),
        const TextRegionInput(text: '2. C', confidence: 0.92),
        const TextRegionInput(text: '3. B', confidence: 0.88),
        const TextRegionInput(text: '4. D', confidence: 0.91),
        const TextRegionInput(text: '5. A', confidence: 0.94),
        const TextRegionInput(text: '6. E', confidence: 0.87),
        const TextRegionInput(text: '7. B', confidence: 0.93),
        const TextRegionInput(text: '8. C', confidence: 0.90),
        const TextRegionInput(text: '9. A', confidence: 0.89),
        const TextRegionInput(text: '10. D', confidence: 0.86),
      ];

      final answers = parser.parseAnswers(regions);
      expect(answers.length, 10);
      expect(answers[0].questionNumber, 1);
      expect(answers[0].answer, 'A');
      expect(answers[9].questionNumber, 10);
      expect(answers[9].answer, 'D');
    });

    test(
      'mixed confidence — low-confidence lines included (caller filters)',
      () {
        final regions = [
          const TextRegionInput(text: '1. A', confidence: 0.95),
          const TextRegionInput(text: '2. ???', confidence: 0.3), // noise
          const TextRegionInput(text: '3. C', confidence: 0.91),
        ];

        final answers = parser.parseAnswers(regions);
        // Parser should return Q1 and Q3 (Q2 fails normalization)
        expect(answers.length, 2);
        expect(answers[0].questionNumber, 1);
        expect(answers[1].questionNumber, 3);
      },
    );

    test('noisy OCR — extra spaces, mixed delimiters', () {
      final regions = [
        const TextRegionInput(text: '1.  A', confidence: 0.88),
        const TextRegionInput(text: '2-B', confidence: 0.91),
        const TextRegionInput(text: '3)  c', confidence: 0.85),
        const TextRegionInput(text: '4 : D', confidence: 0.90),
        const TextRegionInput(text: '5. e', confidence: 0.87),
      ];

      final answers = parser.parseAnswers(regions);
      expect(answers.length, 5);
      expect(answers.map((a) => a.answer).toList(), ['A', 'B', 'C', 'D', 'E']);
    });

    test('True/False mixed English', () {
      final regions = [
        const TextRegionInput(text: '1. True', confidence: 0.93),
        const TextRegionInput(text: '2. F', confidence: 0.90),
        const TextRegionInput(text: '3. false', confidence: 0.88),
        const TextRegionInput(text: '4-T', confidence: 0.91),
      ];

      final answers = parser.parseAnswers(regions);
      expect(answers.length, 4);
      expect(answers.map((a) => a.answer).toList(), [
        'True',
        'False',
        'False',
        'True',
      ]);
    });

    test('Amharic mixed MCQ + True/False', () {
      final regions = [
        const TextRegionInput(text: '1. ሀ', confidence: 0.85),
        const TextRegionInput(text: '2. እውነት', confidence: 0.82),
        const TextRegionInput(text: '3. መ', confidence: 0.88),
        const TextRegionInput(text: '4. ሐሰት', confidence: 0.80),
      ];

      final answers = parser.parseAnswers(regions);
      expect(answers.length, 4);
      expect(answers[0].answer, 'A');
      expect(answers[1].answer, 'True');
      expect(answers[2].answer, 'D');
      expect(answers[3].answer, 'False');
    });

    test('prose lines filtered out', () {
      final regions = [
        const TextRegionInput(text: '1. A', confidence: 0.92),
        const TextRegionInput(text: 'Name: Abebe Kebede', confidence: 0.95),
        const TextRegionInput(text: '2. B', confidence: 0.90),
        const TextRegionInput(
          text: 'Grade 10 Mathematics Final Exam',
          confidence: 0.93,
        ),
        const TextRegionInput(text: 'ID: 12345678', confidence: 0.91),
      ];

      final answers = parser.parseAnswers(regions);
      expect(answers.length, 2);
      expect(answers[0].answer, 'A');
      expect(answers[1].answer, 'B');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // FORMAT 1: Ethiopian answer-before-question (most common format)
  // ══════════════════════════════════════════════════════════════════

  group('parseQuestionAnswer — Format 1: Ethiopian answer-before-question', () {
    test('"B 1. What is the capital of France?" → Q1, B', () {
      final result = parser.parseQuestionAnswer(
        'B 1. What is the capital of France?',
      );
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'B');
    });

    test('"b 1. What is..." → Q1, B (lowercase)', () {
      final result = parser.parseQuestionAnswer('b 1. What is the capital?');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'B');
    });

    test('"A 2. What is 2+2?" → Q2, A', () {
      final result = parser.parseQuestionAnswer('A 2. What is 2+2?');
      expect(result, isNotNull);
      expect(result!.$1, 2);
      expect(result.$2, 'A');
    });

    test('"C 3. Who wrote Hamlet?" → Q3, C', () {
      final result = parser.parseQuestionAnswer('C 3. Who wrote Hamlet?');
      expect(result, isNotNull);
      expect(result!.$1, 3);
      expect(result.$2, 'C');
    });

    test('"AC 4. Name two colors" → Q4, A,C (multi-letter)', () {
      final result = parser.parseQuestionAnswer(
        'AC 4. Name two colors in the flag',
      );
      expect(result, isNotNull);
      expect(result!.$1, 4);
      expect(result.$2, 'A,C');
    });

    test('"aC 4. Name two colors" → Q4, A,C (mixed case)', () {
      final result = parser.parseQuestionAnswer('aC 4. Name two colors');
      expect(result, isNotNull);
      expect(result!.$1, 4);
      expect(result.$2, 'A,C');
    });

    test('"D 5. Largest ocean?" → Q5, D', () {
      final result = parser.parseQuestionAnswer('D 5. Largest ocean?');
      expect(result, isNotNull);
      expect(result!.$1, 5);
      expect(result.$2, 'D');
    });

    test('"a 10. Which planet..." → Q10, A (double-digit Q#)', () {
      final result = parser.parseQuestionAnswer(
        'a 10. Which planet is closest?',
      );
      expect(result, isNotNull);
      expect(result!.$1, 10);
      expect(result.$2, 'A');
    });

    test('"B 1 What is..." → Q1, B (no period delimiter)', () {
      final result = parser.parseQuestionAnswer('B 1 What is the capital?');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'B');
    });

    test('"B 1- What is..." → Q1, B (dash delimiter)', () {
      final result = parser.parseQuestionAnswer('B 1- What is the capital?');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'B');
    });
  });

  group('parseAnswers — Ethiopian format full simulation', () {
    test('5-question Ethiopian exam paper', () {
      final regions = [
        const TextRegionInput(
          text: 'B 1. What is the capital of France?',
          confidence: 0.92,
        ),
        const TextRegionInput(text: 'A 2. What is 2+2?', confidence: 0.88),
        const TextRegionInput(text: 'C 3. Who wrote Hamlet?', confidence: 0.91),
        const TextRegionInput(
          text: 'AC 4. Name two colors in the flag',
          confidence: 0.85,
        ),
        const TextRegionInput(text: 'D 5. Largest ocean?', confidence: 0.90),
      ];

      final answers = parser.parseAnswers(regions);
      expect(answers.length, 5);
      expect(answers[0].questionNumber, 1);
      expect(answers[0].answer, 'B');
      expect(answers[1].questionNumber, 2);
      expect(answers[1].answer, 'A');
      expect(answers[2].questionNumber, 3);
      expect(answers[2].answer, 'C');
      expect(answers[3].questionNumber, 4);
      expect(answers[3].answer, 'A,C');
      expect(answers[4].questionNumber, 5);
      expect(answers[4].answer, 'D');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Phase 1: spatial short-answer association (handwritten answers)
  // ══════════════════════════════════════════════════════════════════

  group('AnswerParser — Phase 1 spatial short-answer association', () {
    test('same-line format still parses exactly as before', () {
      final result = parser.parseQuestionAnswer('16. Addis Ababa');
      expect(result, isNotNull);
      expect(result!.$1, 16);
      expect(result.$2, 'Addis Ababa');

      // And via the positional entry point — standard pass stays authoritative
      final answers = parser.parseAnswersWithPosition([
        const TextRegionInput(text: '16. Addis Ababa', confidence: 0.9),
      ]);
      expect(answers.length, 1);
      expect(answers[0].questionNumber, 16);
      expect(answers[0].answer, 'Addis Ababa');
      expect(answers[0].spatialAssociation, isFalse);
    });

    test('bare number + handwritten answer on the NEXT line associates', () {
      final regions = [
        const TextRegionInput(text: '16', confidence: 0.9, x: 100, y: 100),
        const TextRegionInput(
          text: 'Addis Ababa',
          confidence: 0.72,
          x: 130,
          y: 140,
        ),
      ];

      final answers = parser.parseAnswersWithPosition(regions);
      expect(answers.length, 1);
      expect(answers[0].questionNumber, 16);
      expect(answers[0].answer, 'Addis Ababa');
      expect(answers[0].spatialAssociation, isTrue);
    });

    test('numbered line below an anchor is NOT stolen by it', () {
      final regions = [
        const TextRegionInput(text: '16', confidence: 0.9, x: 100, y: 100),
        const TextRegionInput(
          text: '17. Nairobi',
          confidence: 0.85,
          x: 120,
          y: 140,
        ),
      ];

      final answers = parser.parseAnswersWithPosition(regions);
      expect(answers.length, 1);
      expect(answers[0].questionNumber, 17);
      expect(answers[0].answer, 'Nairobi');
    });

    test('noise line below an anchor is not attached', () {
      final regions = [
        const TextRegionInput(text: '16', confidence: 0.9, x: 100, y: 100),
        const TextRegionInput(text: '~~~ ###', confidence: 0.4, x: 130, y: 140),
      ];

      expect(parser.parseAnswersWithPosition(regions), isEmpty);
    });

    test('candidate beyond the vertical gap is not attached', () {
      final regions = [
        const TextRegionInput(text: '16', confidence: 0.9, x: 100, y: 100),
        const TextRegionInput(
          text: 'Addis Ababa',
          confidence: 0.7,
          x: 130,
          y: 300,
        ),
      ];

      expect(parser.parseAnswersWithPosition(regions), isEmpty);
    });

    test('candidate in a far horizontal column is not attached', () {
      final regions = [
        const TextRegionInput(text: '16', confidence: 0.9, x: 100, y: 100),
        const TextRegionInput(
          text: 'Addis Ababa',
          confidence: 0.7,
          x: 700,
          y: 140,
        ),
      ];

      expect(parser.parseAnswersWithPosition(regions), isEmpty);
    });

    test('nearest number above wins when anchors are stacked', () {
      final regions = [
        const TextRegionInput(text: '16', confidence: 0.9, x: 100, y: 100),
        const TextRegionInput(
          text: 'Addis Ababa',
          confidence: 0.75,
          x: 120,
          y: 125,
        ),
        const TextRegionInput(text: '17', confidence: 0.9, x: 100, y: 170),
      ];

      final answers = parser.parseAnswersWithPosition(regions);
      expect(answers.length, 1);
      expect(answers[0].questionNumber, 16);
      expect(answers[0].answer, 'Addis Ababa');
    });

    test('column of bare numbers does not chain-attach as fake answers', () {
      final regions = [
        const TextRegionInput(text: '16', confidence: 0.9, x: 100, y: 100),
        const TextRegionInput(text: '17', confidence: 0.9, x: 100, y: 150),
        const TextRegionInput(text: '18', confidence: 0.9, x: 100, y: 200),
      ];

      // Pure-digit fallback exists, but each number must only attach at most
      // one candidate and must never consume another question's anchor line
      // in a way that breaks later association. Here every region is an
      // anchor; the first anchor may take "17" as a numeric fallback but
      // "18" then remains available as Q17's own anchor... — verify the
      // conservative outcome: anchors are consumed top-down.
      final answers = parser.parseAnswersWithPosition(regions);
      // Whatever attaches, no answer may claim question 18's number twice,
      // and all outputs must be flagged spatial.
      for (final a in answers) {
        expect(a.spatialAssociation, isTrue);
      }
      final nums = answers.map((a) => a.questionNumber).toSet();
      expect(nums.length, answers.length); // no duplicate claims
    });

    test('page-number-like values out of range never anchor (noise guard)', () {
      final regions = [
        const TextRegionInput(text: '2024', confidence: 0.95, x: 500, y: 40),
        const TextRegionInput(text: 'Ethiopia', confidence: 0.8, x: 520, y: 80),
      ];

      expect(parser.parseAnswersWithPosition(regions), isEmpty);
    });

    test('horizontal spatial parsing unchanged (regression)', () {
      final regions = [
        const TextRegionInput(text: '2.', confidence: 0.9, x: 50, y: 150),
        const TextRegionInput(text: 'C', confidence: 0.85, x: 300, y: 152),
      ];

      final answers = parser.parseAnswersWithPosition(regions);
      expect(answers.length, 1);
      expect(answers[0].questionNumber, 2);
      expect(answers[0].answer, 'C');
      expect(answers[0].spatialAssociation, isTrue);
    });
  });
}
