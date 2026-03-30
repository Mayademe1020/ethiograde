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

  group('parseQuestionAnswer — Amharic numerals as question numbers', () {
    test('"፩. A" → Q1 answer A', () {
      final result = parser.parseQuestionAnswer('፩. A');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'A');
    });

    test('"፪. B" → Q2 answer B', () {
      final result = parser.parseQuestionAnswer('፪. B');
      expect(result, isNotNull);
      expect(result!.$1, 2);
      expect(result.$2, 'B');
    });

    test('"፫. C" → Q3 answer C', () {
      final result = parser.parseQuestionAnswer('፫. C');
      expect(result, isNotNull);
      expect(result!.$1, 3);
      expect(result.$2, 'C');
    });

    test('"፬. D" → Q4 answer D', () {
      final result = parser.parseQuestionAnswer('፬. D');
      expect(result, isNotNull);
      expect(result!.$1, 4);
      expect(result.$2, 'D');
    });

    test('"፭. E" → Q5 answer E', () {
      final result = parser.parseQuestionAnswer('፭. E');
      expect(result, isNotNull);
      expect(result!.$1, 5);
      expect(result.$2, 'E');
    });

    test('"፮-True" → Q6 True (dash delimiter)', () {
      final result = parser.parseQuestionAnswer('፮-True');
      expect(result, isNotNull);
      expect(result!.$1, 6);
      expect(result.$2, 'True');
    });

    test('"፯) False" → Q7 False', () {
      final result = parser.parseQuestionAnswer('፯) False');
      expect(result, isNotNull);
      expect(result!.$1, 7);
      expect(result.$2, 'False');
    });

    test('"፰: A" → Q8 answer A (colon delimiter)', () {
      final result = parser.parseQuestionAnswer('፰: A');
      expect(result, isNotNull);
      expect(result!.$1, 8);
      expect(result.$2, 'A');
    });

    test('"፱. B" → Q9 answer B', () {
      final result = parser.parseQuestionAnswer('፱. B');
      expect(result, isNotNull);
      expect(result!.$1, 9);
      expect(result.$2, 'B');
    });

    test('"፩፪. C" → Q12 answer C (multi-digit Amharic)', () {
      final result = parser.parseQuestionAnswer('፩፪. C');
      expect(result, isNotNull);
      expect(result!.$1, 12);
      expect(result.$2, 'C');
    });

    test('"፪፫. D" → Q23 answer D', () {
      final result = parser.parseQuestionAnswer('፪፫. D');
      expect(result, isNotNull);
      expect(result!.$1, 23);
      expect(result.$2, 'D');
    });

    test('"፱፱. A" → Q99 answer A (max 2-digit Amharic)', () {
      final result = parser.parseQuestionAnswer('፱፱. A');
      expect(result, isNotNull);
      expect(result!.$1, 99);
      expect(result.$2, 'A');
    });

    test('"፩፩፩. B" → Q111 answer B (3-digit Amharic)', () {
      final result = parser.parseQuestionAnswer('፩፩፩. B');
      expect(result, isNotNull);
      expect(result!.$1, 111);
      expect(result.$2, 'B');
    });

    test('concatenated Amharic: "፩A" → Q1 answer A', () {
      final result = parser.parseQuestionAnswer('፩A');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'A');
    });

    test('concatenated Amharic: "፪፫B" → Q23 answer B', () {
      final result = parser.parseQuestionAnswer('፪፫B');
      expect(result, isNotNull);
      expect(result!.$1, 23);
      expect(result.$2, 'B');
    });

    test('Amharic numeral with Amharic answer: "፩. ሀ" → Q1 A', () {
      final result = parser.parseQuestionAnswer('፩. ሀ');
      expect(result, isNotNull);
      expect(result!.$1, 1);
      expect(result.$2, 'A');
    });

    test('Amharic numeral with Amharic T/F: "፪. እውነት" → Q2 True', () {
      final result = parser.parseQuestionAnswer('፪. እውነት');
      expect(result, isNotNull);
      expect(result!.$1, 2);
      expect(result.$2, 'True');
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
      // This SHOULD return null — it's a question, not an answer
      // But the current regex (1. pattern) would match it as number=1, answer="What is the capital?"
      // That answer would fail normalization → empty string → null
      final result = parser.parseQuestionAnswer('1. What is the capital?');
      expect(result, isNull);
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

    test('long nonsense returns empty', () {
      expect(parser.normalizeAnswer('this is definitely not an answer'), '');
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

    test('mixed confidence — low-confidence lines included (caller filters)', () {
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
    });

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
      expect(answers.map((a) => a.answer).toList(), ['True', 'False', 'False', 'True']);
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
        const TextRegionInput(text: 'Grade 10 Mathematics Final Exam', confidence: 0.93),
        const TextRegionInput(text: 'ID: 12345678', confidence: 0.91),
      ];

      final answers = parser.parseAnswers(regions);
      expect(answers.length, 2);
      expect(answers[0].answer, 'A');
      expect(answers[1].answer, 'B');
    });
  });
}
