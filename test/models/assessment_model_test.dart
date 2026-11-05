import 'package:ethiograde/models/assessment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Question model regression', () {
    test('fromMap restores structured question fields', () {
      final question = Question.fromMap({
        'id': 'q-1',
        'number': 3,
        'type': QuestionType.shortAnswer.index,
        'text': 'Name one noble gas',
        'points': 2,
        'options': ['A', 'B'],
        'correctAnswer': ['neon', 'argon'],
        'explanation': 'Any valid noble gas earns credit.',
        'topicTag': 'chemistry',
        'keywords': ['gas', 'element'],
        'essayRubric': {
          'contentWeight': 0.4,
          'structureWeight': 0.2,
          'grammarWeight': 0.2,
          'analysisWeight': 0.2,
          'criteriaDescriptions': {'content': 'Correct element named'},
        },
      });

      expect(question.id, 'q-1');
      expect(question.number, 3);
      expect(question.type, QuestionType.shortAnswer);
      expect(question.text, 'Name one noble gas');
      expect(question.points, 2.0);
      expect(question.options, ['A', 'B']);
      expect(question.correctAnswer, ['neon', 'argon']);
      expect(question.explanation, 'Any valid noble gas earns credit.');
      expect(question.topicTag, 'chemistry');
      expect(question.keywords, ['gas', 'element']);
      expect(question.essayRubric, isNotNull);
      expect(question.essayRubric!.contentWeight, 0.4);
      expect(
        question.essayRubric!.criteriaDescriptions['content'],
        'Correct element named',
      );
    });

    test('copyWith updates selected fields and preserves the rest', () {
      final original = Question(
        id: 'q-2',
        number: 1,
        type: QuestionType.mcq,
        text: 'Original',
        points: 1.5,
        options: const ['A', 'B', 'C'],
        correctAnswer: 'A',
        explanation: 'Original explanation',
        topicTag: 'algebra',
        keywords: const ['factor'],
      );

      final updated = original.copyWith(
        text: 'Updated',
        points: 3.0,
        correctAnswer: 'B',
      );

      expect(updated.id, 'q-2');
      expect(updated.number, 1);
      expect(updated.type, QuestionType.mcq);
      expect(updated.text, 'Updated');
      expect(updated.points, 3.0);
      expect(updated.options, ['A', 'B', 'C']);
      expect(updated.correctAnswer, 'B');
      expect(updated.explanation, 'Original explanation');
      expect(updated.topicTag, 'algebra');
      expect(updated.keywords, ['factor']);
    });

    test('copyWith can clear nullable question metadata', () {
      final original = Question(
        id: 'q-3',
        number: 4,
        type: QuestionType.shortAnswer,
        text: 'Explain the process',
        correctAnswer: ['draft'],
        explanation: 'Teacher note',
        topicTag: 'biology',
        keywords: const ['cell'],
        essayRubric: const EssayRubric(),
      );

      final updated = original.copyWith(
        correctAnswer: null,
        explanation: null,
        topicTag: null,
        keywords: null,
        essayRubric: null,
      );

      expect(updated.correctAnswer, isNull);
      expect(updated.explanation, isNull);
      expect(updated.topicTag, isNull);
      expect(updated.keywords, isNull);
      expect(updated.essayRubric, isNull);
    });
  });
}
