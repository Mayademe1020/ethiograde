import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/services/answer_key_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSectionBulkPaste (section-aware, no inference)', () {
    test('maps answers in order to the section range with the section type', () {
      const section = AnswerKeySection(start: 1, end: 3, type: QuestionType.mcq);
      final parsed = parseSectionBulkPaste('A, B, C', section)!;
      expect(parsed.length, 3);
      expect(parsed[0], {'num': 1, 'answer': 'A', 'type': 'MCQ'});
      expect(parsed[1], {'num': 2, 'answer': 'B', 'type': 'MCQ'});
      expect(parsed[2], {'num': 3, 'answer': 'C', 'type': 'MCQ'});
    });

    test('uses the section type even when content looks like another type', () {
      // Same raw text as above, but the section is short-answer: no MCQ guess.
      const section =
          AnswerKeySection(start: 1, end: 3, type: QuestionType.shortAnswer);
      final parsed = parseSectionBulkPaste('A, B, C', section)!;
      expect(parsed.every((p) => p['type'] == 'SHORT'), isTrue);
      expect(parsed.map((p) => p['answer']).toList(), ['A', 'B', 'C']);
    });

    test('true/false section keeps T/F coding without guessing', () {
      const section =
          AnswerKeySection(start: 11, end: 12, type: QuestionType.trueFalse);
      final parsed = parseSectionBulkPaste('T, F', section)!;
      expect(parsed[0], {'num': 11, 'answer': 'T', 'type': 'T/F'});
      expect(parsed[1], {'num': 12, 'answer': 'F', 'type': 'T/F'});
    });

    test('stops at the section end (no overflow into the next section)', () {
      const section = AnswerKeySection(start: 1, end: 2, type: QuestionType.mcq);
      final parsed = parseSectionBulkPaste('A, B, C, D', section)!;
      expect(parsed.length, 2);
      expect(parsed.last['num'], 2);
    });

    test('empty / whitespace returns null', () {
      const section = AnswerKeySection(start: 1, end: 3, type: QuestionType.mcq);
      expect(parseSectionBulkPaste('', section), isNull);
      expect(parseSectionBulkPaste('   ', section), isNull);
    });
  });

  group('parseBulkPaste (global Paste All, mixed structure)', () {
    test('infers per-answer types so a mixed exam can be pasted at once', () {
      final parsed = parseBulkPaste('A, B, T, F, mitochondria', 5)!;
      expect(parsed.map((p) => p['type']).toList(),
          ['MCQ', 'MCQ', 'T/F', 'T/F', 'SHORT']);
      expect(parsed.map((p) => p['num']).toList(), [1, 2, 3, 4, 5]);
    });

    test('multi-answer tokens (A+C) are detected', () {
      final parsed = parseBulkPaste('A+C, B', 2)!;
      expect(parsed[0], {'num': 1, 'answer': 'A+C', 'type': 'MULTI'});
      expect(parsed[1], {'num': 2, 'answer': 'B', 'type': 'MCQ'});
    });

    test('number+letter tokens are matching type', () {
      final parsed = parseBulkPaste('1C, 2A', 2)!;
      expect(parsed.map((p) => p['type']).toList(), ['MATCH', 'MATCH']);
    });

    test('quoted text is short answer', () {
      final parsed = parseBulkPaste('"Addis Ababa"', 1)!;
      expect(parsed[0], {'num': 1, 'answer': 'Addis Ababa', 'type': 'SHORT'});
    });

    test('unrecognized token is flagged as SHORT in the preview (not applied silently)', () {
      // "ABC" is ambiguous but the preview still reveals the chosen type;
      // Apply only happens on an explicit tap after review.
      final parsed = parseBulkPaste('ABC', 1)!;
      expect(parsed.length, 1);
      expect(parsed[0]['type'], 'SHORT');
      expect(parsed[0]['answer'], 'ABC');
    });

    test('empty returns null', () {
      expect(parseBulkPaste('', 5), isNull);
    });
  });
}
