import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/services/answer_key_fingerprint_service.dart';
import 'package:flutter_test/flutter_test.dart';

List<Question> _qs(int count) => List.generate(
      count,
      (i) => Question(
        id: 'q-${i + 1}',
        number: i + 1,
        type: QuestionType.mcq,
        text: 'Question ${i + 1}',
        points: 1,
        options: const ['A', 'B', 'C', 'D', 'E'],
        correctAnswer: '',
      ),
    );

void main() {
  group('AnswerKeySection model', () {
    test('covers / count / label', () {
      const s = AnswerKeySection(start: 3, end: 5, type: QuestionType.mcq);
      expect(s.count, 3);
      expect(s.covers(2), isFalse);
      expect(s.covers(3), isTrue);
      expect(s.covers(5), isTrue);
      expect(s.covers(6), isFalse);
      expect(s.label, 'Q3–5');
      expect(
        const AnswerKeySection(start: 4, end: 4, type: QuestionType.mcq).label,
        'Q4',
      );
    });

    test('toMap / fromMap round-trips', () {
      const s = AnswerKeySection(start: 1, end: 10, type: QuestionType.trueFalse);
      final m = s.toMap();
      final back = AnswerKeySection.fromMap(m);
      expect(back.start, 1);
      expect(back.end, 10);
      expect(back.type, QuestionType.trueFalse);
    });

    test('invalid type name falls back to mcq', () {
      final s = AnswerKeySection.fromMap({'start': 1, 'end': 2, 'type': 'bogus'});
      expect(s.type, QuestionType.mcq);
    });
  });

  group('collapseSections', () {
    test('uniform exam collapses to a single section', () {
      final qs = _qs(20);
      final secs = collapseSections(qs, const {});
      expect(secs.length, 1);
      expect(secs.first.start, 1);
      expect(secs.first.end, 20);
      expect(secs.first.type, QuestionType.mcq);
    });

    test('mixed types are split at boundaries', () {
      final qs = _qs(20);
      final mixed = qs.asMap().map((i, q) {
        // Q11-15 -> trueFalse
        final t = (i + 1 >= 11 && i + 1 <= 15)
            ? QuestionType.trueFalse
            : QuestionType.mcq;
        return MapEntry(i, q.copyWith(type: t));
      }).values.toList();
      final secs = collapseSections(mixed, const {});
      expect(secs.length, 3);
      expect(secs[0], const AnswerKeySection(start: 1, end: 10, type: QuestionType.mcq));
      expect(
        secs[1],
        const AnswerKeySection(start: 11, end: 15, type: QuestionType.trueFalse),
      );
      expect(secs[2], const AnswerKeySection(start: 16, end: 20, type: QuestionType.mcq));
    });

    test('override changes only the targeted question', () {
      final qs = _qs(5);
      final secs = collapseSections(qs, {3: QuestionType.essay});
      expect(secs.length, 3);
      expect(secs[1], const AnswerKeySection(start: 3, end: 3, type: QuestionType.essay));
    });
  });

  group('Assessment structure', () {
    test('legacy (no sections) derives from question types', () {
      final a = Assessment(title: 'T', subject: 'Sub', questions: _qs(10));
      expect(a.hasExplicitSections, isFalse);
      final secs = a.effectiveSections;
      expect(secs.length, 1);
      expect(secs.first, const AnswerKeySection(start: 1, end: 10, type: QuestionType.mcq));
    });

    test('explicit sections take precedence', () {
      final a = Assessment(
        title: 'T', subject: 'Sub',
        questions: _qs(20),
        sections: const [
          AnswerKeySection(start: 1, end: 10, type: QuestionType.mcq),
          AnswerKeySection(start: 11, end: 20, type: QuestionType.shortAnswer),
        ],
      );
      expect(a.hasExplicitSections, isTrue);
      final secs = a.effectiveSections;
      expect(secs.length, 2);
      expect(secs.last.type, QuestionType.shortAnswer);
    });

    test('validateStructure rejects overlaps, gaps, out-of-range', () {
      final a = Assessment(
        title: 'T', subject: 'Sub',
        questions: _qs(20),
        sections: const [
          AnswerKeySection(start: 1, end: 12, type: QuestionType.mcq),
          AnswerKeySection(start: 10, end: 20, type: QuestionType.shortAnswer),
        ],
      );
      final errors = a.validateStructure();
      expect(errors.any((e) => e.contains('overlap')), isTrue);
      expect(a.isStructureValid, isFalse);
      expect(a.canProceedToAnswers, isFalse);
    });

    test('valid explicit structure is complete and can proceed', () {
      final a = Assessment(
        title: 'T', subject: 'Sub',
        questions: _qs(20),
        sections: const [
          AnswerKeySection(start: 1, end: 15, type: QuestionType.mcq),
          AnswerKeySection(start: 16, end: 20, type: QuestionType.shortAnswer),
        ],
      );
      expect(a.validateStructure(), isEmpty);
      expect(a.isStructureValid, isTrue);
      expect(a.canProceedToAnswers, isTrue);
      expect(a.isStructureComplete, isTrue);
    });

    test('legacy assessment is always valid to proceed', () {
      final a = Assessment(title: 'T', subject: 'Sub', questions: _qs(20));
      expect(a.validateStructure(), isEmpty);
      expect(a.canProceedToAnswers, isTrue);
    });

    test('sections round-trip through toMap/fromMap', () {
      final a = Assessment(
        title: 'T', subject: 'Sub',
        questions: _qs(20),
        sections: const [
          AnswerKeySection(start: 1, end: 10, type: QuestionType.mcq),
          AnswerKeySection(start: 11, end: 20, type: QuestionType.trueFalse),
        ],
      );
      final m = a.toMap();
      final back = Assessment.fromMap(m);
      expect(back.hasExplicitSections, isTrue);
      expect(back.sections!.length, 2);
      expect(back.sections!.last.type, QuestionType.trueFalse);
    });
  });

  group('applySectionsToQuestions compatibility guard', () {
    test('compatible type change keeps the answer', () {
      final qs = [
        Question(
          id: 'q1',
          number: 1,
          type: QuestionType.mcq,
          text: 'Q1',
          points: 1,
          options: const ['A', 'B', 'C'],
          correctAnswer: 'A',
        ),
      ];
      const sections = [
        AnswerKeySection(start: 1, end: 1, type: QuestionType.multiAnswer),
      ];
      final r = applySectionsToQuestions(qs, sections);
      expect(r.incompatibleQuestionNumbers, isEmpty);
      expect(r.questions.first.type, QuestionType.multiAnswer);
      expect(r.questions.first.correctAnswer, 'A'); // preserved
    });

    test('incompatible change is reported, not silently applied', () {
      final qs = [
        Question(
          id: 'q1',
          number: 1,
          type: QuestionType.mcq,
          text: 'Q1',
          points: 1,
          options: const ['A', 'B', 'C'],
          correctAnswer: 'A',
        ),
      ];
      const sections = [
        AnswerKeySection(start: 1, end: 1, type: QuestionType.shortAnswer),
      ];
      final r = applySectionsToQuestions(qs, sections);
      expect(r.incompatibleQuestionNumbers, [1]);
      expect(r.questions.first.correctAnswer, 'A'); // untouched before confirm
      expect(r.questions.first.type, QuestionType.mcq);
    });

    test('clearIncompatible clears the incompatible answer', () {
      final qs = [
        Question(
          id: 'q1',
          number: 1,
          type: QuestionType.mcq,
          text: 'Q1',
          points: 1,
          options: const ['A', 'B', 'C'],
          correctAnswer: 'A',
        ),
      ];
      const sections = [
        AnswerKeySection(start: 1, end: 1, type: QuestionType.shortAnswer),
      ];
      final r = applySectionsToQuestions(
        qs,
        sections,
        clearIncompatible: true,
      );
      expect(r.incompatibleQuestionNumbers, isEmpty);
      expect(r.questions.first.type, QuestionType.shortAnswer);
      expect(r.questions.first.correctAnswer, '');
    });

    test('per-question points are preserved (not overwritten by section)', () {
      final qs = [
        Question(
          id: 'q1',
          number: 1,
          type: QuestionType.mcq,
          text: 'Q1',
          points: 3,
          options: const ['A', 'B'],
          correctAnswer: 'A',
        ),
        Question(
          id: 'q2',
          number: 2,
          type: QuestionType.mcq,
          text: 'Q2',
          points: 2,
          options: const ['A', 'B'],
          correctAnswer: 'B',
        ),
      ];
      const sections = [
        AnswerKeySection(start: 1, end: 2, type: QuestionType.mcq),
      ];
      final r = applySectionsToQuestions(qs, sections);
      expect(r.questions[0].points, 3);
      expect(r.questions[1].points, 2);
    });
  });

  group('structure validation (gap / out-of-range / incomplete)', () {
    test('gap between sections is rejected and blocks progression', () {
      final a = Assessment(
        title: 'T',
        subject: 'Sub',
        questions: _qs(20),
        sections: const [
          AnswerKeySection(start: 1, end: 5, type: QuestionType.mcq),
          AnswerKeySection(start: 10, end: 20, type: QuestionType.shortAnswer),
        ],
      );
      final errors = a.validateStructure();
      expect(
        errors.any((e) => e.contains('not covered') || e.contains('covered')),
        isTrue,
      );
      expect(a.isStructureValid, isFalse);
      expect(a.canProceedToAnswers, isFalse);
    });

    test('out-of-range section is rejected', () {
      final a = Assessment(
        title: 'T',
        subject: 'Sub',
        questions: _qs(20),
        sections: const [
          AnswerKeySection(start: 5, end: 25, type: QuestionType.mcq),
        ],
      );
      final errors = a.validateStructure();
      expect(
        errors.any((e) => e.contains('outside')),
        isTrue,
      );
      expect(a.canProceedToAnswers, isFalse);
    });

    test('overlap is rejected', () {
      final a = Assessment(
        title: 'T',
        subject: 'Sub',
        questions: _qs(20),
        sections: const [
          AnswerKeySection(start: 1, end: 12, type: QuestionType.mcq),
          AnswerKeySection(start: 10, end: 20, type: QuestionType.shortAnswer),
        ],
      );
      expect(a.validateStructure().any((e) => e.contains('overlap')), isTrue);
      expect(a.canProceedToAnswers, isFalse);
    });

    test('missing start-at-1 is rejected', () {
      final a = Assessment(
        title: 'T',
        subject: 'Sub',
        questions: _qs(20),
        sections: const [
          AnswerKeySection(start: 3, end: 20, type: QuestionType.mcq),
        ],
      );
      expect(a.validateStructure().any((e) => e.contains('must start')), isTrue);
      expect(a.canProceedToAnswers, isFalse);
    });
  });

  group('legacy persistence & consistency contract', () {
    test('legacy (sections == null) derives effectiveSections and is valid', () {
      final a = Assessment(title: 'T', subject: 'Sub', questions: _qs(15));
      expect(a.hasExplicitSections, isFalse);
      final secs = a.effectiveSections;
      expect(secs.length, 1);
      expect(secs.first, const AnswerKeySection(start: 1, end: 15, type: QuestionType.mcq));
      expect(a.validateStructure().isEmpty, isTrue);
      expect(a.canProceedToAnswers, isTrue);
    });

    test('legacy settings["sections"] is ignored at model level (derive wins)', () {
      final map = Assessment(title: 'T', subject: 'Sub', questions: _qs(10))
          .toMap()
        ..['settings'] = {
          'sections': [
            {'name': 'A', 'startQ': 1, 'endQ': 10, 'type': 'mcq'},
          ],
        };
      final a = Assessment.fromMap(map);
      expect(a.hasExplicitSections, isFalse);
      // Derivation still works from the question types.
      expect(a.effectiveSections.first.end, 10);
    });

    test('edit → save (toMap) → reload (fromMap) preserves explicit sections', () {
      final a = Assessment(title: 'T', subject: 'Sub', questions: _qs(20));
      final edited = a.copyWith(
        sections: const [
          AnswerKeySection(start: 1, end: 15, type: QuestionType.mcq),
          AnswerKeySection(start: 16, end: 20, type: QuestionType.trueFalse),
        ],
      );
      final reloaded = Assessment.fromMap(edited.toMap());
      expect(reloaded.hasExplicitSections, isTrue);
      expect(reloaded.sections!.length, 2);
      expect(
        reloaded.sections,
        const [
          AnswerKeySection(start: 1, end: 15, type: QuestionType.mcq),
          AnswerKeySection(start: 16, end: 20, type: QuestionType.trueFalse),
        ],
      );
    });

    test('applying structure synchronizes Question.type (canonical)', () {
      final a = Assessment(title: 'T', subject: 'Sub', questions: _qs(20));
      const sections = [
        AnswerKeySection(start: 1, end: 10, type: QuestionType.mcq),
        AnswerKeySection(start: 11, end: 20, type: QuestionType.trueFalse),
      ];
      final r = applySectionsToQuestions(a.questions, sections);
      final updated = a.copyWith(questions: r.questions, sections: sections);
      // Every question's operational type matches the structure.
      for (final q in updated.questions) {
        final sec = sections.firstWhere(
          (s) => q.number >= s.start && q.number <= s.end,
        );
        expect(q.type, sec.type);
      }
      expect(updated.hasExplicitSections, isTrue);
    });

    test('fingerprint depends on type/answer/points, not on the sections field', () {
      final base = Assessment(title: 'T', subject: 'Sub', questions: _qs(20));
      final withSections = base.copyWith(
        sections: const [
          AnswerKeySection(start: 1, end: 20, type: QuestionType.mcq),
        ],
      );
      final fpBase = const AnswerKeyFingerprintService().compute(base);
      final fpSections = const AnswerKeyFingerprintService().compute(withSections);
      // Sections are not part of the fingerprint → identical.
      expect(fpSections, fpBase);
    });
  });
}
