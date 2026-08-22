import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/bubble_template.dart';

void main() {
  group('BubbleTemplate', () {
    test('bubbleCenter calculates correct position', () {
      const template = BubbleTemplate(
        name: 'test',
        questionCount: 5,
        startX: 100,
        startY: 200,
        columnSpacing: 50,
        rowSpacing: 30);

      // Q1 (index 0), A (index 0)
      expect(template.bubbleCenter(0, 0), (100.0, 200.0));
      // Q1, C (index 2)
      expect(template.bubbleCenter(0, 2), (200.0, 200.0));
      // Q3 (index 2), B (index 1)
      expect(template.bubbleCenter(2, 1), (150.0, 260.0));
    });

    test('optionCount returns options length', () {
      const t5 = BubbleTemplate(
        name: 't5',
        questionCount: 10,
        startX: 0,
        startY: 0,
        columnSpacing: 10,
        rowSpacing: 10);
      expect(t5.optionCount, 5);

      const t2 = BubbleTemplate(
        name: 't2',
        questionCount: 10,
        options: ['True', 'False'],
        startX: 0,
        startY: 0,
        columnSpacing: 10,
        rowSpacing: 10);
      expect(t2.optionCount, 2);
    });

    test('default values are correct', () {
      const t = BubbleTemplate(
        name: 'test',
        questionCount: 20,
        startX: 0,
        startY: 0,
        columnSpacing: 10,
        rowSpacing: 10);
      expect(t.options, ['A', 'B', 'C', 'D', 'E']);
      expect(t.bubbleRadius, 8.0);
      expect(t.fillThreshold, 0.45);
    });

    test('toMap and fromMap roundtrip', () {
      const original = BubbleTemplate(
        name: 'custom',
        questionCount: 25,
        options: ['A', 'B', 'C'],
        startX: 150,
        startY: 300,
        columnSpacing: 60,
        rowSpacing: 40,
        bubbleRadius: 10,
        fillThreshold: 0.5);

      final map = original.toMap();
      final restored = BubbleTemplate.fromMap(map);

      expect(restored.name, 'custom');
      expect(restored.questionCount, 25);
      expect(restored.options, ['A', 'B', 'C']);
      expect(restored.startX, 150);
      expect(restored.startY, 300);
      expect(restored.columnSpacing, 60);
      expect(restored.rowSpacing, 40);
      expect(restored.bubbleRadius, 10);
      expect(restored.fillThreshold, 0.5);
    });

    test('fromMap handles missing fields with defaults', () {
      final restored = BubbleTemplate.fromMap({});
      expect(restored.name, 'custom');
      expect(restored.questionCount, 20);
      expect(restored.options, ['A', 'B', 'C', 'D', 'E']);
      expect(restored.startX, 0);
      expect(restored.startY, 0);
      expect(restored.bubbleRadius, 8.0);
      expect(restored.fillThreshold, 0.45);
    });

    test('toString shows name and dimensions', () {
      const t = BubbleTemplate(
        name: 'MoE 20×5',
        questionCount: 20,
        startX: 0,
        startY: 0,
        columnSpacing: 10,
        rowSpacing: 10);
      expect(t.toString(), 'BubbleTemplate(MoE 20×5, 20 Q × 5 opts)');
    });
  });

  group('StandardTemplates', () {
    test('all returns 7 templates', () {
      expect(StandardTemplates.all.length, 7);
    });

    test('byName finds templates case-insensitively', () {
      expect(StandardTemplates.byName('MoE 20×5'), isNotNull);
      expect(StandardTemplates.byName('moe 20×5'), isNotNull);
      expect(StandardTemplates.byName('MOE 20×5'), isNotNull);
      expect(StandardTemplates.byName('nonexistent'), isNull);
    });

    test('matchAssessment returns correct MCQ templates', () {
      // ≤20 → moe20x5
      expect(StandardTemplates.matchAssessment(questionCount: 10, isTrueFalse: false).name, 'MoE 20×5');
      expect(StandardTemplates.matchAssessment(questionCount: 20, isTrueFalse: false).name, 'MoE 20×5');
      // ≤30 → moe30x5
      expect(StandardTemplates.matchAssessment(questionCount: 25, isTrueFalse: false).name, 'MoE 30×5');
      expect(StandardTemplates.matchAssessment(questionCount: 30, isTrueFalse: false).name, 'MoE 30×5');
      // >30 → uni50x4
      expect(StandardTemplates.matchAssessment(questionCount: 50, isTrueFalse: false).name, 'University 50×4');
    });

    test('matchAssessment returns correct T/F templates', () {
      expect(StandardTemplates.matchAssessment(questionCount: 5, isTrueFalse: true).name, 'True/False 10');
      expect(StandardTemplates.matchAssessment(questionCount: 10, isTrueFalse: true).name, 'True/False 10');
      expect(StandardTemplates.matchAssessment(questionCount: 15, isTrueFalse: true).name, 'True/False 20');
      expect(StandardTemplates.matchAssessment(questionCount: 20, isTrueFalse: true).name, 'True/False 20');
    });

    test('standard templates have valid coordinates', () {
      for (final t in StandardTemplates.all) {
        expect(t.startX, greaterThan(0));
        expect(t.startY, greaterThan(0));
        expect(t.columnSpacing, greaterThan(0));
        expect(t.rowSpacing, greaterThan(0));
        expect(t.bubbleRadius, greaterThan(0));
        expect(t.questionCount, greaterThan(0));
        expect(t.options.length, greaterThanOrEqualTo(2));
      }
    });
  });
}
