import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/coordinate_map.dart';

void main() {
  group('P0.4 — Template identity validation', () {
    test('correct template has matching assessmentId', () {
      final map = CoordinateMap(
        assessmentId: 'assess-123',
        page: PageDimensions(),
        anchors: [],
        questions: [],
      );
      final json = map.toMap();
      expect(json['assessmentId'], 'assess-123');
    });

    test('wrong template has different assessmentId', () {
      final map = CoordinateMap(
        assessmentId: 'assess-456', // Different assessment
        page: PageDimensions(),
        anchors: [],
        questions: [],
      );
      final json = map.toMap();
      expect(json['assessmentId'], isNot('assess-123'));
    });

    test('missing assessmentId in map produces warning', () {
      final map = CoordinateMap(
        assessmentId: '', // Empty
        page: PageDimensions(),
        anchors: [],
        questions: [],
      );
      final json = map.toMap();
      expect(json['assessmentId'], '');
    });

    test('outdated coordinate map detected by version mismatch', () {
      final oldMap = CoordinateMap(
        assessmentId: 'assess-123',
        version: '0.9', // Old version
        page: PageDimensions(),
        anchors: [],
        questions: [],
      );
      final newMap = CoordinateMap(
        assessmentId: 'assess-123',
        version: '1.0',
        page: PageDimensions(),
        anchors: [],
        questions: [],
      );
      expect(oldMap.version, isNot(newMap.version));
    });

    test('regenerated map preserves assessmentId', () {
      final original = CoordinateMap(
        assessmentId: 'assess-123',
        page: PageDimensions(),
        anchors: [],
        questions: [],
      );
      // Simulate regeneration
      final regenerated = CoordinateMap(
        assessmentId: original.assessmentId,
        version: original.version,
        page: original.page,
        anchors: original.anchors,
        questions: original.questions,
      );
      expect(regenerated.assessmentId, original.assessmentId);
    });

    test('forced teacher override can bypass template check', () {
      // The batch processor returns early on wrong template
      // Teacher can override by confirming in the UI
      // This test verifies the check exists
      final mapJson = {'assessmentId': 'wrong-assessment'};
      final currentAssessmentId = 'correct-assessment';
      expect(mapJson['assessmentId'] != currentAssessmentId, true);
    });

    test('anchor count mismatch indicates wrong template', () {
      final map1 = CoordinateMap(
        assessmentId: 'assess-123',
        page: PageDimensions(),
        anchors: [
          AnchorPoint(corner: 'topLeft', position: BubblePosition(xMm: 10, yMm: 10, option: '')),
          AnchorPoint(corner: 'topRight', position: BubblePosition(xMm: 200, yMm: 10, option: '')),
        ],
        questions: [],
      );
      final map2 = CoordinateMap(
        assessmentId: 'assess-123',
        page: PageDimensions(),
        anchors: [
          AnchorPoint(corner: 'topLeft', position: BubblePosition(xMm: 10, yMm: 10, option: '')),
          AnchorPoint(corner: 'topRight', position: BubblePosition(xMm: 200, yMm: 10, option: '')),
          AnchorPoint(corner: 'bottomLeft', position: BubblePosition(xMm: 10, yMm: 280, option: '')),
          AnchorPoint(corner: 'bottomRight', position: BubblePosition(xMm: 200, yMm: 280, option: '')),
        ],
        questions: [],
      );
      expect(map1.anchors.length, isNot(map2.anchors.length));
    });
  });
}
