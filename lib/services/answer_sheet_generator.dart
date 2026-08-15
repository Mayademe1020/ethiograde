import 'dart:convert';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../models/assessment.dart';
import '../models/coordinate_map.dart';
import '../models/student.dart';

/// Generates printable OMR answer sheets as A4 PDFs with coordinate maps.
///
/// Supports two layouts:
/// - [SheetLayout.fullA4] — legacy, one full page per student
/// - [SheetLayout.halfSheet] — two half-sheets per A4, cut and share
///
/// Half-sheet layout uses table-style bubbles:
/// │ 1 │ ○ │ ○ │ ○ │ ○ │
///
/// Each half-sheet includes an answer key checkbox at the bottom.
/// Teacher fills one sheet, checks the box, scans it first.
/// Scanner detects the checkbox and saves that sheet as the answer key.
class AnswerSheetGenerator {
  // ── A4 dimensions in mm ───────────────────────────────────────────
  static const double _a4WidthMm = 210.0;
  static const double _a4HeightMm = 297.0;

  // ── Half-sheet dimensions ─────────────────────────────────────────
  // Two half-sheets per A4, separated by a 3mm gap (cut line)
  // Each half: full width, half height minus gap
  static const double _halfSheetWidthMm = _a4WidthMm; // full width
  static const double _halfSheetHeightMm = 143.0; // (297 - 3 - 8) / 2 ≈ 143
  static const double _cutLineGapMm = 3.0;

  // ── Margins (half-sheet) ──────────────────────────────────────────
  static const double _hsMarginMm = 10.0;

  // ── Anchors (half-sheet — slightly smaller than full A4) ──────────
  static const double _hsAnchorSizeMm = 7.0;
  static const double _hsAnchorInsetMm = 8.0;

  // ── Table layout (half-sheet) ─────────────────────────────────────
  static const double _hsBubbleDiameterMm = 3.5;
  static const double _hsRowHeightMm = 6.5;
  static const double _hsTableBorderWidth = 0.4;
  static const double _hsQNumColWidthMm = 10.0;
  static const double _hsOptionColWidthMm = 14.0; // width per option column
  static const double _hsHeaderRowHeightMm = 6.0;

  // ── Header (half-sheet) ───────────────────────────────────────────
  static const double _hsHeaderHeightMm = 38.0;

  // ── Answer key checkbox ───────────────────────────────────────────
  static const double _checkboxSizeMm = 5.0;
  static const double _checkboxBottomOffsetMm = 12.0; // from bottom anchor

  // ── Full A4 legacy constants ──────────────────────────────────────
  static const double _marginMm = 15.0;
  static const double _anchorSizeMm = 8.0;
  static const double _anchorInsetMm = 10.0;
  static const double _bubbleDiameterMm = 4.0;
  static const double _mcqSpacingMm = 18.0;
  static const double _tfSpacingMm = 30.0;
  static const double _rowHeightMm = 7.0;
  static const int _maxQuestionsPerColumn = 60;
  static const double _columnGapMm = 10.0;
  static const double _questionNumberWidthMm = 10.0;
  static const double _headerHeightMm = 42.0;

  // ── Conversion: mm → PDF points ──────────────────────────────────
  static const double _mmToPt = 2.83465;

  // ── Default options ───────────────────────────────────────────────
  static const List<String> _defaultMcqOptions = ['A', 'B', 'C', 'D', 'E'];
  static const List<String> _tfOptions = ['T', 'F'];

  /// Generate answer sheet PDF + coordinate map.
  ///
  /// [layout] controls full A4 vs half-sheet (2 per page).
  /// Returns (pdfFile, coordinateMapFile, relativeName).
  Future<(File, File, String)> generate({
    required Assessment assessment,
    String? outputDir,
    String schoolName = '',
    List<Student> students = const [],
    bool prefillNames = false,
    SheetLayout layout = SheetLayout.fullA4,
  }) async {
    if (layout == SheetLayout.halfSheet) {
      return _generateHalfSheet(
        assessment: assessment,
        outputDir: outputDir,
        schoolName: schoolName,students: students,
        prefillNames: prefillNames);
    }

    // Check if questions exceed single page capacity
    if (assessment.questions.length > _maxQuestionsPerPage) {
      return _generateMultiPage(
        assessment: assessment,
        outputDir: outputDir,
        schoolName: schoolName,students: students,
        prefillNames: prefillNames);
    }

    return _generateFullA4(
      assessment: assessment,
      outputDir: outputDir,
      schoolName: schoolName,students: students,
      prefillNames: prefillNames);
  }

  // ══════════════════════════════════════════════════════════════════
  //  HALF-SHEET LAYOUT (2 per A4)
  // ══════════════════════════════════════════════════════════════════

  Future<(File, File, String)> _generateHalfSheet({
    required Assessment assessment,
    String? outputDir,
    String schoolName = '',
    List<Student> students = const [],
    bool prefillNames = false,
  }) async {
    final allQuestions = assessment.questions;
    final midPoint = (allQuestions.length / 2).ceil();
    final topQuestions = allQuestions.sublist(0, midPoint);
    final bottomQuestions = allQuestions.sublist(midPoint);

    // Build coordinate maps for each half-sheet
    final topMap = _buildHalfSheetCoordMap(
      assessmentId: assessment.id,
      questions: topQuestions,
      halfSheetIndex: 0,
      offsetYMm: 0);
    final bottomMap = _buildHalfSheetCoordMap(
      assessmentId: assessment.id,
      questions: bottomQuestions,
      halfSheetIndex: 1,
      offsetYMm: _halfSheetHeightMm + _cutLineGapMm);

    // Build PDF — one A4 page per pair of students (or per pair of generic sheets)
    final pdf = pw.Document();
    final usePrefill = prefillNames && students.isNotEmpty;

    // Pair up students: [student1, student2] per page, or [null, null] for blank
    final List<(Student?, Student?)> pairs = [];
    if (usePrefill) {
      for (int i = 0; i < students.length; i += 2) {
        final top = students[i];
        final bottom = (i + 1 < students.length) ? students[i + 1] : null;
        pairs.add((top, bottom));
      }
      // If odd count, add one more page for remaining students
      // (already handled by the loop above — bottom is null)
    } else {
      // Blank mode: one page with two generic sheets
      pairs.add((null, null));
    }

    for (final (topStudent, bottomStudent) in pairs) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) => _buildTwoUpPage(
            assessment: assessment,
            topQuestions: topQuestions,
            bottomQuestions: bottomQuestions,
            schoolName: schoolName,topStudent: topStudent,
            bottomStudent: bottomStudent)));
    }

    // Save files
    final dir = outputDir ?? (await getApplicationDocumentsDirectory()).path;
    final baseName = _safeName(assessment.title);

    final pdfFile = File('$dir/answer_sheet_$baseName.pdf');
    await pdfFile.writeAsBytes(await pdf.save());

    // Save coordinate maps as a combined structure
    final combinedMap = {
      'layout': 'halfSheet',
      'assessmentId': assessment.id,
      'halfSheets': [topMap.toMap(), bottomMap.toMap()],
      'metadata': {
        'generatedAt': DateTime.now().toIso8601String(),
        'totalQuestions': allQuestions.length,
        'topSheetQuestions': topQuestions.length,
        'bottomSheetQuestions': bottomQuestions.length,
      },
    };

    final mapFile = File('$dir/answer_sheet_$baseName.coordmap.json');
    await mapFile.writeAsString(jsonEncode(combinedMap));

    final relativeName = 'answer_sheet_$baseName.coordmap.json';
    return (pdfFile, mapFile, relativeName);
  }

  /// Build coordinate map for one half-sheet.
  CoordinateMap _buildHalfSheetCoordMap({
    required String assessmentId,
    required List<Question> questions,
    required int halfSheetIndex,
    required double offsetYMm,
  }) {
    final anchors = <AnchorPoint>[];
    final questionBubbles = <QuestionBubble>[];
    const inset = _hsAnchorInsetMm;
    const size = _hsAnchorSizeMm;

    // Anchors (relative to the half-sheet origin)
    anchors.addAll([
      const AnchorPoint(
        corner: 'topLeft',
        position: BubblePosition(
          xMm: inset,
          yMm: inset,
          widthMm: size,
          heightMm: size,
          option: '')),
      const AnchorPoint(
        corner: 'topRight',
        position: BubblePosition(
          xMm: _halfSheetWidthMm - inset - size,
          yMm: inset,
          widthMm: size,
          heightMm: size,
          option: '')),
      const AnchorPoint(
        corner: 'bottomLeft',
        position: BubblePosition(
          xMm: inset,
          yMm: _halfSheetHeightMm - inset - size,
          widthMm: size,
          heightMm: size,
          option: '')),
      const AnchorPoint(
        corner: 'bottomRight',
        position: BubblePosition(
          xMm: _halfSheetWidthMm - inset - size,
          yMm: _halfSheetHeightMm - inset - size,
          widthMm: size,
          heightMm: size,
          option: '')),
    ]);

    // Table start position
    const tableStartX = _hsMarginMm;
    const tableStartY = _hsAnchorInsetMm + _hsAnchorSizeMm + 5 + _hsHeaderHeightMm;

    // Question rows
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      final rowY = tableStartY +
          _hsHeaderRowHeightMm + // skip header row
          i * _hsRowHeightMm;

      final isTf = q.type == QuestionType.trueFalse;
      final options = isTf ? _tfOptions : _defaultMcqOptions;

      // Bubble X positions: after Q# column, centered in each option column
      final bubbles = <BubblePosition>[];
      for (int j = 0; j < options.length; j++) {
        final cellX = tableStartX +
            _hsQNumColWidthMm +
            j * _hsOptionColWidthMm +
            _hsOptionColWidthMm / 2;
        bubbles.add(BubblePosition(
          xMm: cellX,
          yMm: rowY + _hsRowHeightMm / 2,
          widthMm: _hsBubbleDiameterMm,
          heightMm: _hsBubbleDiameterMm,
          option: options[j]));
      }

      questionBubbles.add(QuestionBubble(
        number: q.number,
        type: isTf ? SheetQuestionType.trueFalse : SheetQuestionType.mcq,
        bubbles: bubbles,
        column: 'left'));
    }

    // Answer key checkbox position
    const checkboxY = _halfSheetHeightMm -
        _hsAnchorInsetMm -
        _hsAnchorSizeMm -
        _checkboxBottomOffsetMm;

    final metadata = <String, dynamic>{
      'halfSheetIndex': halfSheetIndex,
      'offsetYMm': offsetYMm,
      'layout': 'halfSheet',
      'questionCount': questions.length,
      'bubbleDiameterMm': _hsBubbleDiameterMm,
      'rowHeightMm': _hsRowHeightMm,
      'optionColWidthMm': _hsOptionColWidthMm,
      'answerKeyCheckbox': {
        'xMm': _hsMarginMm + 3,
        'yMm': checkboxY,
        'widthMm': _checkboxSizeMm,
        'heightMm': _checkboxSizeMm,
      },
    };

    return CoordinateMap(
      assessmentId: assessmentId,
      page: const PageDimensions(
        widthMm: _halfSheetWidthMm,
        heightMm: _halfSheetHeightMm),
      anchors: anchors,
      questions: questionBubbles,
      metadata: metadata);
  }

  /// Build an A4 page with two half-sheets stacked vertically.
  pw.Widget _buildTwoUpPage({
    required Assessment assessment,
    required List<Question> topQuestions,
    required List<Question> bottomQuestions,
    required String schoolName,Student? topStudent,
    Student? bottomStudent,
  }) {
    return pw.Stack(
      children: [
        // ── Top half-sheet ───────────────────────────────────────
        pw.Positioned(
          left: 0,
          top: 0,
          child: _buildHalfSheet(
            assessment: assessment,
            questions: topQuestions,
            schoolName: schoolName,student: topStudent,
            offsetYMm: 0)),

        // ── Cut line ─────────────────────────────────────────────
        pw.Positioned(
          left: 10 * _mmToPt,
          top: (_halfSheetHeightMm + 0.5) * _mmToPt,
          child: pw.Row(
            children: List.generate(
              40,
              (_) => pw.Container(
                width: 3 * _mmToPt,
                height: 0.3,
                color: PdfColors.grey400,
                margin: const pw.EdgeInsets.symmetric(horizontal: 1))))),
        // Cut label
        pw.Positioned(
          left: (_halfSheetWidthMm / 2 - 12) * _mmToPt,
          top: (_halfSheetHeightMm + 1) * _mmToPt,
          child: pw.Text(
            '── CUT HERE ──',
            style: const pw.TextStyle(
              fontSize: 6,
              color: PdfColors.grey500))),

        // ── Bottom half-sheet ────────────────────────────────────
        pw.Positioned(
          left: 0,
          top: (_halfSheetHeightMm + _cutLineGapMm) * _mmToPt,
          child: _buildHalfSheet(
            assessment: assessment,
            questions: bottomQuestions,
            schoolName: schoolName,student: bottomStudent,
            offsetYMm: _halfSheetHeightMm + _cutLineGapMm)),
      ]);
  }

  /// Build one half-sheet widget (fits in ~143mm × 210mm).
  pw.Widget _buildHalfSheet({
    required Assessment assessment,
    required List<Question> questions,
    required String schoolName,Student? student,
    required double offsetYMm,
  }) {
    return pw.Container(
      width: _halfSheetWidthMm * _mmToPt,
      height: _halfSheetHeightMm * _mmToPt,
      child: pw.Stack(
        children: [
          // Corner anchors
          ..._buildHalfSheetAnchors(offsetYMm),

          // Header
          pw.Positioned(
            left: _hsMarginMm * _mmToPt,
            top: (_hsAnchorInsetMm + _hsAnchorSizeMm + 3) * _mmToPt,
            right: _hsMarginMm * _mmToPt,
            child: _buildHalfSheetHeader(
              assessment, schoolName, student: student)),

          // Question table
          pw.Positioned(
            left: _hsMarginMm * _mmToPt,
            top: (_hsAnchorInsetMm + _hsAnchorSizeMm + 5 + _hsHeaderHeightMm) *
                _mmToPt,
            child: _buildQuestionTable(questions)),

          // Answer key checkbox
          pw.Positioned(
            left: _hsMarginMm * _mmToPt,
            bottom: (_hsAnchorInsetMm + _hsAnchorSizeMm + _checkboxBottomOffsetMm) *
                _mmToPt,
            child: _buildAnswerKeyCheckbox()),
        ]));
  }

  /// Build 4 corner anchors for a half-sheet.
  List<pw.Widget> _buildHalfSheetAnchors(double offsetYMm) {
    const size = _hsAnchorSizeMm * _mmToPt;
    const inset = _hsAnchorInsetMm * _mmToPt;
    const w = _halfSheetWidthMm * _mmToPt;
    const h = _halfSheetHeightMm * _mmToPt;

    pw.Widget anchor(double left, double top) => pw.Positioned(
          left: left,
          top: top,
          child: pw.Container(
            width: size,
            height: size,
            color: PdfColors.black));

    return [
      anchor(inset, inset),
      anchor(w - inset - size, inset),
      anchor(inset, h - inset - size),
      anchor(w - inset - size, h - inset - size),
    ];
  }

  /// Compact header for half-sheet.
  pw.Widget _buildHalfSheetHeader(
    Assessment assessment,
    String schoolName, {
    Student? student,
  }) {
    final hasStudent = student != null;
    final displayName = hasStudent ? student.fullName : '________________________';
    final displayId = hasStudent
        ? (student.studentId.isNotEmpty ? student.studentId : '______')
        : '__________';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Title line
        pw.Text(
          assessment.title,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 1 * _mmToPt),

        // Name + ID on one line
        pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: '${"NAME"}: ',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold)),
              pw.TextSpan(
                text: displayName,
                style: pw.TextStyle(
                  fontSize: hasStudent ? 9 : 7.5,
                  fontWeight: hasStudent ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: hasStudent ? PdfColors.black : PdfColors.grey500)),
            ])),
        pw.SizedBox(height: 1 * _mmToPt),

        // ID + Date
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: '${"ID"}: ',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold)),
                  pw.TextSpan(
                    text: displayId,
                    style: pw.TextStyle(
                      fontSize: hasStudent ? 9 : 7.5,
                      fontWeight: hasStudent ? pw.FontWeight.bold : pw.FontWeight.normal,
                      color: hasStudent ? PdfColors.black : PdfColors.grey500)),
                ])),
            pw.Text(
              '${"Date"}: ____/____/____',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
          ]),
        pw.SizedBox(height: 1.5 * _mmToPt),
        pw.Divider(color: PdfColors.grey300, height: 0.5),
      ]);
  }

  /// Build the table-style question grid.
  ///
  /// Format:
  /// │   │ A │ B │ C │ D │ E │
  /// ├───┼───┼───┼───┼───┼───┤
  /// │ 1 │ ○ │ ○ │ ○ │ ○ │ ○ │
  /// │ 2 │ ○ │ ○ │ ○ │ ○ │ ○ │
  pw.Widget _buildQuestionTable(List<Question> questions) {
    const border = pw.BorderSide(color: PdfColors.black, width: _hsTableBorderWidth);

    pw.Widget cell({
      required double width,
      required double height,
      required pw.Widget child,
      pw.BorderSide? topBorder,
      pw.BorderSide? bottomBorder,
    }) {
      return pw.Container(
        width: width * _mmToPt,
        height: height * _mmToPt,
        decoration: pw.BoxDecoration(
          border: pw.Border(
            left: border,
            right: border,
            top: topBorder ?? border,
            bottom: bottomBorder ?? border)),
        alignment: pw.Alignment.center,
        child: child);
    }

    // Header row: │   │ A │ B │ C │ D │ E │
    final headerCells = <pw.Widget>[
      cell(
        width: _hsQNumColWidthMm,
        height: _hsHeaderRowHeightMm,
        child: pw.Text('')),
    ];
    final isTfQuestion = questions.isNotEmpty &&
        questions.every((q) => q.type == QuestionType.trueFalse);
    final options = isTfQuestion ? _tfOptions : _defaultMcqOptions;

    for (final opt in options) {
      headerCells.add(
        cell(
          width: _hsOptionColWidthMm,
          height: _hsHeaderRowHeightMm,
          child: pw.Text(
            opt,
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold))));
    }

    // Question rows
    final rows = <pw.Widget>[];
    for (final q in questions) {
      final qIsTf = q.type == QuestionType.trueFalse;
      final qOptions = qIsTf ? _tfOptions : _defaultMcqOptions;
      const bubbleSize = _hsBubbleDiameterMm * _mmToPt;

      final rowCells = <pw.Widget>[
        // Question number
        cell(
          width: _hsQNumColWidthMm,
          height: _hsRowHeightMm,
          child: pw.Text(
            '${q.number}',
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold))),
      ];

      for (int j = 0; j < qOptions.length; j++) {
        rowCells.add(
          cell(
            width: _hsOptionColWidthMm,
            height: _hsRowHeightMm,
            child: pw.Container(
              width: bubbleSize,
              height: bubbleSize,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: PdfColors.black,
                  width: 0.6),
                borderRadius: pw.BorderRadius.circular(bubbleSize / 2)))));
      }

      rows.add(
        pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: rowCells));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: headerCells),
        ...rows,
      ]);
  }

  /// Build the answer key checkbox at the bottom of the sheet.
  pw.Widget _buildAnswerKeyCheckbox() {
    const size = _checkboxSizeMm * _mmToPt;
    return pw.Row(
      children: [
        pw.Container(
          width: size,
          height: size,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 0.8))),
        pw.SizedBox(width: 2 * _mmToPt),
        pw.Text(
          'This is the answer key',
          style: pw.TextStyle(
            fontSize: 7,
            fontStyle: pw.FontStyle.italic,
            color: PdfColors.grey700)),
      ]);
  }

  // ══════════════════════════════════════════════════════════════════
  //  MULTI-PAGE LAYOUT (when questions exceed single page capacity)
  // ══════════════════════════════════════════════════════════════════

  /// Maximum questions that fit on a single A4 page (two columns).
  static const int _maxQuestionsPerPage = _maxQuestionsPerColumn * 2; // 120

  /// Generate multi-page answer sheets when questions exceed single page capacity.
  ///
  /// Returns multiple A4 pages, each with its own coordinate map.
  /// Used when assessment has >120 questions (or >60 for single-column layout).
  Future<(File, File, String)> _generateMultiPage({
    required Assessment assessment,
    String? outputDir,
    String schoolName = '',
    List<Student> students = const [],
    bool prefillNames = false,
  }) async {
    final questions = assessment.questions;
    const questionsPerPage = _maxQuestionsPerPage;
    final totalPages = (questions.length / questionsPerPage).ceil();

    // Split questions into pages
    final pages = <List<Question>>[];
    for (int i = 0; i < totalPages; i++) {
      final start = i * questionsPerPage;
      final end = (start + questionsPerPage).clamp(0, questions.length);
      pages.add(questions.sublist(start, end));
    }

    // Build coordinate maps for each page
    final coordMaps = <CoordinateMap>[];
    for (int i = 0; i < totalPages; i++) {
      final pageQuestions = pages[i];
      final hasRightColumn = pageQuestions.length > _maxQuestionsPerColumn;
      final leftQuestions = hasRightColumn
          ? pageQuestions.sublist(0, _maxQuestionsPerColumn)
          : pageQuestions;
      final rightQuestions = hasRightColumn
          ? pageQuestions.sublist(_maxQuestionsPerColumn)
          : <Question>[];

      final coordMap = _buildFullA4CoordinateMap(
        assessmentId: assessment.id,
        leftQuestions: leftQuestions,
        rightQuestions: rightQuestions,
      );
      coordMaps.add(coordMap);
    }

    // Build PDF
    final pdf = pw.Document();

    for (final pageQuestions in pages) {
      final hasRightColumn = pageQuestions.length > _maxQuestionsPerColumn;
      final leftQuestions = hasRightColumn
          ? pageQuestions.sublist(0, _maxQuestionsPerColumn)
          : pageQuestions;
      final rightQuestions = hasRightColumn
          ? pageQuestions.sublist(_maxQuestionsPerColumn)
          : <Question>[];

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) => _buildFullA4Page(
            assessment: assessment,
            leftQuestions: leftQuestions,
            rightQuestions: rightQuestions,
            hasRightColumn: hasRightColumn,
            schoolName: schoolName,
            student: null,
          ),
        ),
      );
    }

    // Save files
    final dir = outputDir ?? (await getApplicationDocumentsDirectory()).path;
    final baseName = _safeName(assessment.title);

    final pdfFile = File('$dir/answer_sheet_$baseName.pdf');
    await pdfFile.writeAsBytes(await pdf.save());

    // Save coordinate maps as multi-page structure
    final combinedMap = {
      'layout': 'multiPage',
      'assessmentId': assessment.id,
      'totalPages': totalPages,
      'pages': coordMaps.map((m) => m.toMap()).toList(),
      'metadata': {
        'generatedAt': DateTime.now().toIso8601String(),
        'totalQuestions': questions.length,
        'questionsPerPage': questionsPerPage,
      },
    };

    final mapFile = File('$dir/answer_sheet_$baseName.coordmap.json');
    await mapFile.writeAsString(jsonEncode(combinedMap));

    final relativeName = 'answer_sheet_$baseName.coordmap.json';
    return (pdfFile, mapFile, relativeName);
  }

  // ══════════════════════════════════════════════════════════════════
  //  FULL A4 LAYOUT (legacy — one page per student)
  // ══════════════════════════════════════════════════════════════════

  Future<(File, File, String)> _generateFullA4({
    required Assessment assessment,
    String? outputDir,
    String schoolName = '',
    List<Student> students = const [],
    bool prefillNames = false,
  }) async {
    final questions = assessment.questions;
    final hasRightColumn = questions.length > _maxQuestionsPerColumn;
    final leftQuestions = hasRightColumn
        ? questions.sublist(0, _maxQuestionsPerColumn)
        : questions;
    final rightQuestions = hasRightColumn
        ? questions.sublist(_maxQuestionsPerColumn)
        : <Question>[];

    final coordMap = _buildFullA4CoordinateMap(
      assessmentId: assessment.id,
      leftQuestions: leftQuestions,
      rightQuestions: rightQuestions);

    final pdf = pw.Document();
    final usePrefill = prefillNames && students.isNotEmpty;
    final pageStudents = usePrefill ? students : [null];

    for (final student in pageStudents) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) => _buildFullA4Page(
            assessment: assessment,
            leftQuestions: leftQuestions,
            rightQuestions: rightQuestions,
            hasRightColumn: hasRightColumn,
            schoolName: schoolName,student: student)));
    }

    final dir = outputDir ?? (await getApplicationDocumentsDirectory()).path;
    final baseName = _safeName(assessment.title);

    final pdfFile = File('$dir/answer_sheet_$baseName.pdf');
    await pdfFile.writeAsBytes(await pdf.save());

    final mapFile = File('$dir/answer_sheet_$baseName.coordmap.json');
    await mapFile.writeAsString(jsonEncode(coordMap.toMap()));

    final relativeName = 'answer_sheet_$baseName.coordmap.json';
    return (pdfFile, mapFile, relativeName);
  }

  CoordinateMap _buildFullA4CoordinateMap({
    required String assessmentId,
    required List<Question> leftQuestions,
    required List<Question> rightQuestions,
  }) {
    final anchors = <AnchorPoint>[];
    final questionBubbles = <QuestionBubble>[];

    const anchorInset = _anchorInsetMm;
    const anchorSize = _anchorSizeMm;
    anchors.addAll([
      const AnchorPoint(
        corner: 'topLeft',
        position: BubblePosition(
          xMm: anchorInset, yMm: anchorInset,
          widthMm: anchorSize, heightMm: anchorSize, option: '')),
      const AnchorPoint(
        corner: 'topRight',
        position: BubblePosition(
          xMm: _a4WidthMm - anchorInset - anchorSize, yMm: anchorInset,
          widthMm: anchorSize, heightMm: anchorSize, option: '')),
      const AnchorPoint(
        corner: 'bottomLeft',
        position: BubblePosition(
          xMm: anchorInset, yMm: _a4HeightMm - anchorInset - anchorSize,
          widthMm: anchorSize, heightMm: anchorSize, option: '')),
      const AnchorPoint(
        corner: 'bottomRight',
        position: BubblePosition(
          xMm: _a4WidthMm - anchorInset - anchorSize,
          yMm: _a4HeightMm - anchorInset - anchorSize,
          widthMm: anchorSize, heightMm: anchorSize, option: '')),
    ]);

    const leftStartX = _marginMm + _questionNumberWidthMm;
    const startY = _anchorInsetMm + _anchorSizeMm + 5 + _headerHeightMm;

    for (int i = 0; i < leftQuestions.length; i++) {
      final q = leftQuestions[i];
      final yMm = startY + i * _rowHeightMm;
      final bubbles = _buildBubblesForQuestionFullA4(
        question: q, startX: leftStartX, yMm: yMm);
      questionBubbles.add(QuestionBubble(
        number: q.number,
        type: q.type == QuestionType.trueFalse
            ? SheetQuestionType.trueFalse
            : SheetQuestionType.mcq,
        bubbles: bubbles,
        column: 'left'));
    }

    if (rightQuestions.isNotEmpty) {
      const rightStartX = _a4WidthMm / 2 + _columnGapMm + _questionNumberWidthMm;
      for (int i = 0; i < rightQuestions.length; i++) {
        final q = rightQuestions[i];
        final yMm = startY + i * _rowHeightMm;
        final bubbles = _buildBubblesForQuestionFullA4(
          question: q, startX: rightStartX, yMm: yMm);
        questionBubbles.add(QuestionBubble(
          number: q.number,
          type: q.type == QuestionType.trueFalse
              ? SheetQuestionType.trueFalse
              : SheetQuestionType.mcq,
          bubbles: bubbles,
          column: 'right'));
      }
    }

    return CoordinateMap(
      assessmentId: assessmentId,
      page: const PageDimensions(),
      anchors: anchors,
      questions: questionBubbles,
      metadata: {
        'layout': 'fullA4',
        'generatedAt': DateTime.now().toIso8601String(),
        'questionCount': leftQuestions.length + rightQuestions.length,
        'hasDualColumn': rightQuestions.isNotEmpty,
        'bubbleDiameterMm': _bubbleDiameterMm,
        'mcqSpacingMm': _mcqSpacingMm,
        'tfSpacingMm': _tfSpacingMm,
        'rowHeightMm': _rowHeightMm,
      });
  }

  List<BubblePosition> _buildBubblesForQuestionFullA4({
    required Question question,
    required double startX,
    required double yMm,
  }) {
    final isTf = question.type == QuestionType.trueFalse;
    final options = isTf ? _tfOptions : question.options;
    final spacing = isTf ? _tfSpacingMm : _mcqSpacingMm;

    return List.generate(options.length, (i) {
      return BubblePosition(
        xMm: startX + i * spacing,
        yMm: yMm,
        widthMm: _bubbleDiameterMm,
        heightMm: _bubbleDiameterMm,
        option: options[i]);
    });
  }

  pw.Widget _buildFullA4Page({
    required Assessment assessment,
    required List<Question> leftQuestions,
    required List<Question> rightQuestions,
    required bool hasRightColumn,
    required String schoolName,Student? student,
  }) {
    return pw.Stack(
      children: [
        ..._buildFullA4Anchors(),
        pw.Positioned(
          left: _marginMm * _mmToPt,
          top: (_anchorInsetMm + _anchorSizeMm + 5) * _mmToPt,
          right: _marginMm * _mmToPt,
          child: _buildFullA4Header(assessment, schoolName, student: student)),
        pw.Positioned(
          left: _marginMm * _mmToPt,
          top: (_anchorInsetMm + _anchorSizeMm + 5 + _headerHeightMm) * _mmToPt,
          child: _buildFullA4QuestionColumn(questions: leftQuestions)),
        if (hasRightColumn)
          pw.Positioned(
            left: (_a4WidthMm / 2 + _columnGapMm / 2) * _mmToPt,
            top: (_anchorInsetMm + _anchorSizeMm + 5 + _headerHeightMm) * _mmToPt,
            child: _buildFullA4QuestionColumn(questions: rightQuestions)),
        if (hasRightColumn)
          pw.Positioned(
            left: (_a4WidthMm / 2) * _mmToPt,
            top: (_anchorInsetMm + _anchorSizeMm + 5) * _mmToPt,
            child: pw.Container(
              width: 0.5,
              height: (_a4HeightMm - 2 * (_anchorInsetMm + _anchorSizeMm + 5)) * _mmToPt,
              color: PdfColors.grey400)),
      ]);
  }

  List<pw.Widget> _buildFullA4Anchors() {
    const size = _anchorSizeMm * _mmToPt;
    const inset = _anchorInsetMm * _mmToPt;
    pw.Widget anchor(double left, double top) => pw.Positioned(
          left: left,
          top: top,
          child: pw.Container(width: size, height: size, color: PdfColors.black));
    return [
      anchor(inset, inset),
      anchor(_a4WidthMm * _mmToPt - inset - size, inset),
      anchor(inset, _a4HeightMm * _mmToPt - inset - size),
      anchor(_a4WidthMm * _mmToPt - inset - size, _a4HeightMm * _mmToPt - inset - size),
    ];
  }

  pw.Widget _buildFullA4Header(
    Assessment assessment,
    String schoolName, {
    Student? student,
  }) {
    final hasStudent = student != null;
    final displayName = hasStudent ? student.fullName : '________________________________';
    final displayId = hasStudent
        ? (student.studentId.isNotEmpty ? student.studentId : '________')
        : '________________';
    final displayClass = hasStudent
        ? (student.className.isNotEmpty
            ? student.className
            : (assessment.className.isNotEmpty ? assessment.className : '________'))
        : '________';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              schoolName.isNotEmpty ? schoolName : ('School'),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text(
              assessment.title,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ]),
        pw.SizedBox(height: 1.5 * _mmToPt),
        pw.Text(
          '${"Date"}: ___/___/______',
          style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 2.5 * _mmToPt),
        pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(
              text: '${"NAME"}: ',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.TextSpan(
              text: displayName,
              style: pw.TextStyle(
                fontSize: hasStudent ? 11 : 9,
                fontWeight: hasStudent ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: hasStudent ? PdfColors.black : PdfColors.grey500)),
          ])),
        pw.SizedBox(height: 1.5 * _mmToPt),
        pw.Row(children: [
          pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(
                text: '${"ID"}: ',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.TextSpan(
                text: displayId,
                style: pw.TextStyle(
                  fontSize: hasStudent ? 11 : 9,
                  fontWeight: hasStudent ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: hasStudent ? PdfColors.black : PdfColors.grey500)),
            ])),
          pw.SizedBox(width: 10 * _mmToPt),
          pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(
                text: '${"Class"}: ',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.TextSpan(
                text: displayClass,
                style: pw.TextStyle(
                  fontSize: hasStudent ? 11 : 9,
                  fontWeight: hasStudent ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: hasStudent ? PdfColors.black : PdfColors.grey500)),
            ])),
        ]),
        pw.SizedBox(height: 2 * _mmToPt),
        pw.Text(
          'Fill ONE bubble per question. Use pencil.',
          style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600)),
        pw.SizedBox(height: 1 * _mmToPt),
        pw.Divider(color: PdfColors.grey300, height: 1),
      ]);
  }

  pw.Widget _buildFullA4QuestionColumn({
    required List<Question> questions,}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: questions.map(_buildFullA4QuestionRow).toList());
  }

  pw.Widget _buildFullA4QuestionRow(Question question) {
    final isTf = question.type == QuestionType.trueFalse;
    final options = isTf ? _tfOptions : question.options;
    final spacing = (isTf ? _tfSpacingMm : _mcqSpacingMm) * _mmToPt;
    const bubbleSize = _bubbleDiameterMm * _mmToPt;
    const rowH = _rowHeightMm * _mmToPt;

    return pw.Container(
      height: rowH,
      margin: const pw.EdgeInsets.only(bottom: 0.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: _questionNumberWidthMm * _mmToPt,
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              '${question.number}.',
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
          ...options.map((opt) => pw.Container(
                width: spacing,
                child: pw.Row(children: [
                  pw.Container(
                    width: bubbleSize,
                    height: bubbleSize,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 0.8),
                      borderRadius: pw.BorderRadius.circular(bubbleSize / 2))),
                  pw.SizedBox(width: 1.5),
                  pw.Text(
                    opt,
                    style: pw.TextStyle(fontSize: isTf ? 6 : 5.5, color: PdfColors.grey700)),
                ]))),
        ]));
  }

  // ══════════════════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ══════════════════════════════════════════════════════════════════

  /// Resolve a coordinate map filename to its full path.
  static Future<String> resolveCoordinateMapPath(String storedValue) async {
    if (storedValue.startsWith('/')) return storedValue;
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$storedValue';
  }

  /// Regenerate coordinate map from assessment (fallback when file is missing).
  static Future<File?> regenerateCoordinateMap(Assessment assessment) async {
    try {
      final gen = AnswerSheetGenerator();
      final (_, mapFile, __) = await gen.generate(
        assessment: assessment,
        schoolName: '');
      return mapFile;
    } catch (_) {
      return null;
    }
  }

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[<>:"/\\|?*\s]'), '_').toLowerCase();
}

/// Sheet layout options.
enum SheetLayout {
  /// Full A4 — one page per student (legacy, higher scanning reliability).
  fullA4,

  /// Half-sheet — two per A4, cut and share (50% paper savings).
  halfSheet,
}
