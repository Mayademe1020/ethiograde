import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/coordinate_map.dart';

void main() {
  group('CoordinateMap', () {
    test('toMap / fromMap roundtrip', () {
      const map = CoordinateMap(
        assessmentId: 'test-1',
        page: PageDimensions(),
        anchors: [
          AnchorPoint(
            corner: 'topLeft',
            position: BubblePosition(
              xMm: 10,
              yMm: 10,
              widthMm: 8,
              heightMm: 8,
              option: '')),
        ],
        questions: [
          QuestionBubble(
            number: 1,
            type: SheetQuestionType.mcq,
            bubbles: [
              BubblePosition(xMm: 30, yMm: 50, option: 'A'),
              BubblePosition(xMm: 48, yMm: 50, option: 'B'),
              BubblePosition(xMm: 66, yMm: 50, option: 'C'),
              BubblePosition(xMm: 84, yMm: 50, option: 'D'),
            ],
            column: 'left'),
        ]);

      final json = jsonEncode(map.toMap());
      final restored = CoordinateMap.fromMap(jsonDecode(json));

      expect(restored.assessmentId, 'test-1');
      expect(restored.page.widthMm, 210.0);
      expect(restored.anchors, hasLength(1));
      expect(restored.anchors.first.corner, 'topLeft');
      expect(restored.questions, hasLength(1));
      expect(restored.questions.first.number, 1);
      expect(restored.questions.first.bubbles, hasLength(4));
    });

    test('findBubble returns correct position', () {
      const map = CoordinateMap(
        assessmentId: 'test-2',
        page: PageDimensions(),
        anchors: [],
        questions: [
          QuestionBubble(
            number: 5,
            type: SheetQuestionType.trueFalse,
            bubbles: [
              BubblePosition(xMm: 30, yMm: 80, option: 'T'),
              BubblePosition(xMm: 60, yMm: 80, option: 'F'),
            ]),
        ]);

      final bubble = map.findBubble(5, 'T');
      expect(bubble, isNotNull);
      expect(bubble!.xMm, 30);
      expect(bubble.yMm, 80);

      expect(map.findBubble(5, 'X'), isNull);
      expect(map.findBubble(99, 'A'), isNull);
    });

    test('findBubble is case-insensitive', () {
      const map = CoordinateMap(
        assessmentId: 'test-3',
        page: PageDimensions(),
        anchors: [],
        questions: [
          QuestionBubble(
            number: 1,
            type: SheetQuestionType.mcq,
            bubbles: [
              BubblePosition(xMm: 0, yMm: 0, option: 'A'),
            ]),
        ]);

      expect(map.findBubble(1, 'a'), isNotNull);
      expect(map.findBubble(1, 'A'), isNotNull);
    });

    test('anchorPositions flattens anchors', () {
      const map = CoordinateMap(
        assessmentId: 'test-4',
        page: PageDimensions(),
        anchors: [
          AnchorPoint(
            corner: 'topLeft',
            position: BubblePosition(
              xMm: 10,
              yMm: 10,
              widthMm: 8,
              heightMm: 8,
              option: '')),
          AnchorPoint(
            corner: 'bottomRight',
            position: BubblePosition(
              xMm: 192,
              yMm: 279,
              widthMm: 8,
              heightMm: 8,
              option: '')),
        ],
        questions: []);

      final positions = map.anchorPositions;
      expect(positions, hasLength(2));
      expect(positions[0].xMm, 10);
      expect(positions[1].xMm, 192);
    });
  });

  group('QuestionBubble', () {
    test('serializes type correctly', () {
      const mcq = QuestionBubble(
        number: 1,
        type: SheetQuestionType.mcq,
        bubbles: []);
      expect(mcq.toMap()['type'], 'mcq');

      const tf = QuestionBubble(
        number: 2,
        type: SheetQuestionType.trueFalse,
        bubbles: []);
      expect(tf.toMap()['type'], 'trueFalse');
    });

    test('column defaults to left', () {
      const q = QuestionBubble(
        number: 1,
        type: SheetQuestionType.mcq,
        bubbles: []);
      expect(q.column, 'left');
    });
  });

  group('BubblePosition', () {
    test('default dimensions are 4mm', () {
      const pos = BubblePosition(xMm: 0, yMm: 0, option: 'A');
      expect(pos.widthMm, 4.0);
      expect(pos.heightMm, 4.0);
    });

    test('toMap / fromMap roundtrip', () {
      const pos = BubblePosition(
        xMm: 25.5,
        yMm: 60.0,
        widthMm: 5.0,
        heightMm: 5.0,
        option: 'C');
      final restored = BubblePosition.fromMap(pos.toMap());
      expect(restored.xMm, 25.5);
      expect(restored.option, 'C');
    });
  });

  group('PageDimensions', () {
    test('defaults to A4', () {
      const page = PageDimensions();
      expect(page.widthMm, 210.0);
      expect(page.heightMm, 297.0);
    });
  });
}
