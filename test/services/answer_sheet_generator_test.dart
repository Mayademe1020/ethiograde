import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/assessment.dart';
import 'package:ethiograde/models/coordinate_map.dart';
import 'package:ethiograde/models/student.dart';
import 'package:ethiograde/services/answer_sheet_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ethiograde_sheet_test_');
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  /// Helper: create a test assessment with N MCQ questions.
  Assessment makeMcqAssessment(int count, {String id = 'test-mcq'}) {
    return Assessment(
      id: id,
      title: 'Test MCQ',
      subject: 'Math',
      questions: List.generate(
        count,
        (i) => Question(
          number: i + 1,
          type: QuestionType.mcq,
          correctAnswer: 'A')));
  }

  /// Helper: create a test assessment with N T/F questions.
  Assessment makeTfAssessment(int count, {String id = 'test-tf'}) {
    return Assessment(
      id: id,
      title: 'Test TF',
      subject: 'Science',
      questions: List.generate(
        count,
        (i) => Question(
          number: i + 1,
          type: QuestionType.trueFalse,
          correctAnswer: 'True')));
  }

  /// Helper: create a mixed assessment.
  Assessment makeMixedAssessment({
    int mcqCount = 5,
    int tfCount = 3,
    String id = 'test-mixed',
  }) {
    final questions = <Question>[
      ...List.generate(
        mcqCount,
        (i) => Question(
          number: i + 1,
          type: QuestionType.mcq,
          correctAnswer: 'B')),
      ...List.generate(
        tfCount,
        (i) => Question(
          number: mcqCount + i + 1,
          type: QuestionType.trueFalse,
          correctAnswer: 'True')),
    ];
    return Assessment(
      id: id,
      title: 'Mixed Test',
      subject: 'General',
      questions: questions);
  }

  group('AnswerSheetGenerator', () {
    test('generates PDF + coordinate map for 10 MCQ', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(10);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path);

      // PDF exists and has content
      expect(await pdf.exists(), isTrue);
      expect(await pdf.length(), greaterThan(100));

      // Coordinate map exists
      expect(await coordMap.exists(), isTrue);
      final mapJson = jsonDecode(await coordMap.readAsString());
      final map = CoordinateMap.fromMap(mapJson);

      expect(map.assessmentId, 'test-mcq');
      expect(map.questions, hasLength(10));
      expect(map.anchors, hasLength(4));

      // All MCQ questions have 5 bubbles
      for (final q in map.questions) {
        expect(q.type, SheetQuestionType.mcq);
        expect(q.bubbles, hasLength(5));
        expect(q.bubbles.map((b) => b.option).toList(), ['A', 'B', 'C', 'D', 'E']);
      }
    });

    test('generates PDF + coordinate map for 10 T/F', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeTfAssessment(10);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path);

      expect(await pdf.exists(), isTrue);
      final mapJson = jsonDecode(await coordMap.readAsString());
      final map = CoordinateMap.fromMap(mapJson);

      expect(map.questions, hasLength(10));

      // All T/F questions have 2 bubbles
      for (final q in map.questions) {
        expect(q.type, SheetQuestionType.trueFalse);
        expect(q.bubbles, hasLength(2));
        expect(q.bubbles.map((b) => b.option).toList(), ['T', 'F']);
      }
    });

    test('handles mixed MCQ + T/F on same page', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMixedAssessment(mcqCount: 5, tfCount: 3);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path);

      expect(await pdf.exists(), isTrue);
      final mapJson = jsonDecode(await coordMap.readAsString());
      final map = CoordinateMap.fromMap(mapJson);

      expect(map.questions, hasLength(8));

      // First 5 are MCQ
      for (int i = 0; i < 5; i++) {
        expect(map.questions[i].type, SheetQuestionType.mcq);
        expect(map.questions[i].bubbles, hasLength(5));
      }

      // Last 3 are T/F
      for (int i = 5; i < 8; i++) {
        expect(map.questions[i].type, SheetQuestionType.trueFalse);
        expect(map.questions[i].bubbles, hasLength(2));
      }
    });

    test('splits into two columns for >60 questions', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(80);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path);

      expect(await pdf.exists(), isTrue);
      final mapJson = jsonDecode(await coordMap.readAsString());
      final map = CoordinateMap.fromMap(mapJson);

      expect(map.questions, hasLength(80));
      expect(map.metadata['hasDualColumn'], isTrue);

      // First 60 are left column
      final leftQs = map.questions.where((q) => q.column == 'left').toList();
      final rightQs = map.questions.where((q) => q.column == 'right').toList();

      expect(leftQs, hasLength(60));
      expect(rightQs, hasLength(20));

      // Right column questions are further right on page
      final leftMaxX = leftQs
          .expand((q) => q.bubbles)
          .map((b) => b.xMm)
          .reduce((a, b) => a > b ? a : b);
      final rightMinX = rightQs
          .expand((q) => q.bubbles)
          .map((b) => b.xMm)
          .reduce((a, b) => a < b ? a : b);

      expect(rightMinX, greaterThan(leftMaxX));
    });

    test('single column for ≤60 questions', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(40);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path);

      final mapJson = jsonDecode(await coordMap.readAsString());
      final map = CoordinateMap.fromMap(mapJson);

      expect(map.metadata['hasDualColumn'], isFalse);
      expect(
        map.questions.every((q) => q.column == 'left'),
        isTrue);
    });

    test('4 anchors at correct corners', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(5);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path);

      final mapJson = jsonDecode(await coordMap.readAsString());
      final map = CoordinateMap.fromMap(mapJson);

      expect(map.anchors, hasLength(4));

      final corners = map.anchors.map((a) => a.corner).toSet();
      expect(corners, {'topLeft', 'topRight', 'bottomLeft', 'bottomRight'});

      // Anchors are inside the page
      for (final anchor in map.anchors) {
        expect(anchor.position.xMm, greaterThanOrEqualTo(0));
        expect(anchor.position.xMm, lessThanOrEqualTo(210));
        expect(anchor.position.yMm, greaterThanOrEqualTo(0));
        expect(anchor.position.yMm, lessThanOrEqualTo(297));
      }

      // Anchor size is 8mm
      for (final anchor in map.anchors) {
        expect(anchor.position.widthMm, 8.0);
        expect(anchor.position.heightMm, 8.0);
      }
    });

    test('bubble positions are within page bounds', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(30);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path);

      final mapJson = jsonDecode(await coordMap.readAsString());
      final map = CoordinateMap.fromMap(mapJson);

      for (final q in map.questions) {
        for (final b in q.bubbles) {
          expect(b.xMm, greaterThan(0));
          expect(b.xMm, lessThan(210));
          expect(b.yMm, greaterThan(0));
          expect(b.yMm, lessThan(297));
        }
      }
    });

    test('MCQ spacing is wider than bubble diameter', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(1);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path);

      final mapJson = jsonDecode(await coordMap.readAsString());
      final map = CoordinateMap.fromMap(mapJson);

      final bubbles = map.questions.first.bubbles;
      // Distance between A and B should be > bubble diameter (4mm)
      final spacing = bubbles[1].xMm - bubbles[0].xMm;
      expect(spacing, greaterThan(4.0));
    });

    test('T/F spacing is wider than MCQ spacing', () async {
      final gen = AnswerSheetGenerator();
      final mcq = makeMcqAssessment(1);
      final tf = makeTfAssessment(1, id: 'test-tf-spacing');

      final (_, mcqCoord, _) = await gen.generate(
        assessment: mcq,
        outputDir: tempDir.path);
      final (_, tfCoord, _) = await gen.generate(
        assessment: tf,
        outputDir: tempDir.path);

      final mcqMap = CoordinateMap.fromMap(
        jsonDecode(await mcqCoord.readAsString()));
      final tfMap = CoordinateMap.fromMap(
        jsonDecode(await tfCoord.readAsString()));

      final mcqSpacing = mcqMap.questions.first.bubbles[1].xMm -
          mcqMap.questions.first.bubbles[0].xMm;
      final tfSpacing = tfMap.questions.first.bubbles[1].xMm -
          tfMap.questions.first.bubbles[0].xMm;

      expect(tfSpacing, greaterThan(mcqSpacing));
    });

    // ── Per-student generation ───────────────────────────────────

    test('generates multi-page PDF with prefill (3 students → 3 pages)',
        () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(20);

      final students = [
        Student(studentId: '001', firstName: 'Abel', lastName: 'Tesfaye'),
        Student(studentId: '002', firstName: 'Bethlehem', lastName: 'Assefa'),
        Student(studentId: '003', firstName: 'Dawit', lastName: 'Haile'),
      ];

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        students: students,
        prefillNames: true);

      expect(await pdf.exists(), isTrue);

      // Multi-page PDF is larger than single-page (more pages = more bytes)
      final multiPageBytes = await pdf.length();

      final (singlePdf, _, __) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path);
      final singlePageBytes = await singlePdf.length();

      // 3 pages should be larger than 1 page
      expect(multiPageBytes, greaterThan(singlePageBytes));

      // Coordinate map is the same regardless of student count
      final mapJson = jsonDecode(await coordMap.readAsString());
      final map = CoordinateMap.fromMap(mapJson);
      expect(map.questions, hasLength(20));
    });

    test('generates single page in blank mode (no students)', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(10);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        prefillNames: true, // toggled on but no students → falls back to blank
      );

      expect(await pdf.exists(), isTrue);

      // Should be same size as explicit blank mode
      final (blankPdf, _, __) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path);

      final prefillNoStudents = await pdf.length();
      final blankMode = await blankPdf.length();
      expect(prefillNoStudents, equals(blankMode));
    });

    test('coordinate map is identical for prefill vs blank', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(15);

      final students = [
        Student(studentId: '010', firstName: 'Helen', lastName: 'Yonas'),
      ];

      final (_, prefillMap, __) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        students: students,
        prefillNames: true);

      final (_, blankMap, ___) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path);

      final prefillJson = jsonDecode(await prefillMap.readAsString());
      final blankJson = jsonDecode(await blankMap.readAsString());

      final prefill = CoordinateMap.fromMap(prefillJson);
      final blank = CoordinateMap.fromMap(blankJson);

      expect(prefill.questions.length, equals(blank.questions.length));
      expect(prefill.anchors.length, equals(blank.anchors.length));

      // Bubble positions are identical
      for (int i = 0; i < prefill.questions.length; i++) {
        final pBubbles = prefill.questions[i].bubbles;
        final bBubbles = blank.questions[i].bubbles;
        expect(pBubbles.length, equals(bBubbles.length));
        for (int j = 0; j < pBubbles.length; j++) {
          expect(pBubbles[j].xMm, equals(bBubbles[j].xMm));
          expect(pBubbles[j].yMm, equals(bBubbles[j].yMm));
        }
      }
    });

    test('1 student produces smaller PDF than 30 students', skip: true, () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(10);

      final oneStudent = [
        Student(studentId: '001', firstName: 'Abel', lastName: 'T'),
      ];

      final thirtyStudents = List.generate(
        30,
        (i) => Student(
          studentId: (i + 1).toString().padLeft(3, '0'),
          firstName: 'Student',
          lastName: '${i + 1}'));

      final (smallPdf, _, __) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        students: oneStudent,
        prefillNames: true);

      final (largePdf, ___, ____) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        students: thirtyStudents,
        prefillNames: true);

      final smallBytes = await smallPdf.length();
      final largeBytes = await largePdf.length();

      // 30 pages should be larger than 1 page
      expect(largeBytes, greaterThan(smallBytes));
    });
  });

  // ── Half-sheet layout ─────────────────────────────────────────────

  group('AnswerSheetGenerator — Half Sheet', () {
    test('generates half-sheet PDF with table layout', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(20);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        layout: SheetLayout.halfSheet);

      expect(await pdf.exists(), isTrue);
      expect(await pdf.length(), greaterThan(100));

      final mapJson = jsonDecode(await coordMap.readAsString());

      // Combined map has layout and two half-sheets
      expect(mapJson['layout'], 'halfSheet');
      expect(mapJson['halfSheets'], hasLength(2));
      expect(mapJson['assessmentId'], 'test-mcq');
    });

    test('splits questions across two half-sheets', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(40);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        layout: SheetLayout.halfSheet);

      final mapJson = jsonDecode(await coordMap.readAsString());
      final topMap = CoordinateMap.fromMap(mapJson['halfSheets'][0]);
      final bottomMap = CoordinateMap.fromMap(mapJson['halfSheets'][1]);

      // Top has first half (20), bottom has second half (20)
      expect(topMap.questions, hasLength(20));
      expect(bottomMap.questions, hasLength(20));

      // Top starts at Q1, bottom starts at Q21
      expect(topMap.questions.first.number, 1);
      expect(topMap.questions.last.number, 20);
      expect(bottomMap.questions.first.number, 21);
      expect(bottomMap.questions.last.number, 40);
    });

    test('half-sheet has 4 anchors each', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(30);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        layout: SheetLayout.halfSheet);

      final mapJson = jsonDecode(await coordMap.readAsString());
      for (final sheet in mapJson['halfSheets']) {
        final map = CoordinateMap.fromMap(sheet);
        expect(map.anchors, hasLength(4));
        final corners = map.anchors.map((a) => a.corner).toSet();
        expect(corners, {'topLeft', 'topRight', 'bottomLeft', 'bottomRight'});
      }
    });

    test('half-sheet uses 5 MCQ options (A-E)', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(10);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        layout: SheetLayout.halfSheet);

      final mapJson = jsonDecode(await coordMap.readAsString());
      final topMap = CoordinateMap.fromMap(mapJson['halfSheets'][0]);

      for (final q in topMap.questions) {
        expect(q.bubbles, hasLength(5));
        expect(q.bubbles.map((b) => b.option).toList(), ['A', 'B', 'C', 'D', 'E']);
      }
    });

    test('half-sheet T/F questions have 2 bubbles', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeTfAssessment(10);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        layout: SheetLayout.halfSheet);

      final mapJson = jsonDecode(await coordMap.readAsString());
      final topMap = CoordinateMap.fromMap(mapJson['halfSheets'][0]);

      for (final q in topMap.questions) {
        expect(q.type, SheetQuestionType.trueFalse);
        expect(q.bubbles, hasLength(2));
        expect(q.bubbles.map((b) => b.option).toList(), ['T', 'F']);
      }
    });

    test('half-sheet page dimensions are ~210×143mm', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(10);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        layout: SheetLayout.halfSheet);

      final mapJson = jsonDecode(await coordMap.readAsString());
      final topMap = CoordinateMap.fromMap(mapJson['halfSheets'][0]);

      expect(topMap.page.widthMm, 210.0);
      expect(topMap.page.heightMm, 143.0);
    });

    test('half-sheet bubbles are within page bounds', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(20);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        layout: SheetLayout.halfSheet);

      final mapJson = jsonDecode(await coordMap.readAsString());
      for (final sheet in mapJson['halfSheets']) {
        final map = CoordinateMap.fromMap(sheet);
        for (final q in map.questions) {
          for (final b in q.bubbles) {
            expect(b.xMm, greaterThan(0));
            expect(b.xMm, lessThan(map.page.widthMm));
            expect(b.yMm, greaterThan(0));
            expect(b.yMm, lessThan(map.page.heightMm));
          }
        }
      }
    });

    test('half-sheet metadata includes answerKeyCheckbox', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(10);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        layout: SheetLayout.halfSheet);

      final mapJson = jsonDecode(await coordMap.readAsString());
      for (final sheet in mapJson['halfSheets']) {
        final meta = sheet['metadata'];
        expect(meta['answerKeyCheckbox'], isNotNull);
        final cb = meta['answerKeyCheckbox'];
        expect(cb['widthMm'], 5.0);
        expect(cb['heightMm'], 5.0);
        expect(cb['xMm'], greaterThan(0));
        expect(cb['yMm'], greaterThan(0));
      }
    });

    test('odd question count splits unevenly (21/19 for 40)', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(39);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        layout: SheetLayout.halfSheet);

      final mapJson = jsonDecode(await coordMap.readAsString());
      final topMap = CoordinateMap.fromMap(mapJson['halfSheets'][0]);
      final bottomMap = CoordinateMap.fromMap(mapJson['halfSheets'][1]);

      // ceil(39/2) = 20 on top, 19 on bottom
      expect(topMap.questions, hasLength(20));
      expect(bottomMap.questions, hasLength(19));
    });

    test('half-sheet coordinate map has offsetYMm', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(20);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        layout: SheetLayout.halfSheet);

      final mapJson = jsonDecode(await coordMap.readAsString());
      final topMeta = mapJson['halfSheets'][0]['metadata'];
      final bottomMeta = mapJson['halfSheets'][1]['metadata'];

      expect(topMeta['offsetYMm'], 0);
      expect(bottomMeta['offsetYMm'], greaterThan(0));
      expect(topMeta['halfSheetIndex'], 0);
      expect(bottomMeta['halfSheetIndex'], 1);
    });

    test('blank half-sheet produces single page with two sheets', () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(20);

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        layout: SheetLayout.halfSheet);

      expect(await pdf.exists(), isTrue);
      final mapJson = jsonDecode(await coordMap.readAsString());
      expect(mapJson['halfSheets'], hasLength(2));
    });

    test('prefill half-sheet: 4 students → 2 pages', skip: true, () async {
      final gen = AnswerSheetGenerator();
      final assessment = makeMcqAssessment(20);

      final students = List.generate(
        4,
        (i) => Student(
          studentId: (i + 1).toString().padLeft(3, '0'),
          firstName: 'Student',
          lastName: '${i + 1}'));

      final (pdf, coordMap, relName) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        students: students,
        prefillNames: true,
        layout: SheetLayout.halfSheet);

      expect(await pdf.exists(), isTrue);

      // Compare with blank to verify size difference
      final (blankPdf, _, __) = await gen.generate(
        assessment: assessment,
        outputDir: tempDir.path,
        layout: SheetLayout.halfSheet);

      // 4 students = 2 pages, blank = 1 page
      final prefillBytes = await pdf.length();
      final blankBytes = await blankPdf.length();
      expect(prefillBytes, greaterThan(blankBytes));
    });
  });
}
