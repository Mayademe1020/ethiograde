import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/widgets/assessment/section_header.dart';

void main() {
  group('autoFixSections', () {
    test('single section already covers 1..total', () {
      final fixed = autoFixSections(
        [const ExamSection(name: 'A', startQ: 1, endQ: 20, type: 'mcq')],
        20,
      );
      expect(fixed.length, 1);
      expect(fixed.first.startQ, 1);
      expect(fixed.first.endQ, 20);
    });

    test('first 1-12, second overlaps at 10 -> 1-12 then 13-20', () {
      final sections = [
        const ExamSection(name: 'A', startQ: 1, endQ: 12, type: 'mcq'),
        const ExamSection(name: 'B', startQ: 10, endQ: 20, type: 'trueFalse'),
      ];
      final fixed = autoFixSections(sections, 20);
      expect(fixed.length, 2);
      expect(fixed[0].startQ, 1);
      expect(fixed[0].endQ, 12);
      expect(fixed[1].startQ, 13);
      expect(fixed[1].endQ, 20);
      expect(fixed[1].type, 'trueFalse');
    });

    test('gap between sections is filled', () {
      final sections = [
        const ExamSection(name: 'A', startQ: 1, endQ: 5, type: 'mcq'),
        const ExamSection(name: 'B', startQ: 10, endQ: 20, type: 'trueFalse'),
      ];
      final fixed = autoFixSections(sections, 20);
      expect(fixed[0].endQ, 5);
      expect(fixed[1].startQ, 6);
      expect(fixed[1].endQ, 20);
    });

    test('three sections with overlap and gap resolve contiguously', () {
      final sections = [
        const ExamSection(name: 'A', startQ: 1, endQ: 10, type: 'mcq'),
        const ExamSection(name: 'B', startQ: 8, endQ: 15, type: 'trueFalse'),
        const ExamSection(name: 'C', startQ: 18, endQ: 20, type: 'essay'),
      ];
      final fixed = autoFixSections(sections, 20);
      expect(
        fixed.map((s) => '${s.startQ}-${s.endQ}').toList(),
        ['1-10', '11-15', '16-20'],
      );
      expect(fixed[2].type, 'essay');
    });

    test('empty list yields a single uniform section', () {
      final fixed = autoFixSections([], 20);
      expect(fixed.length, 1);
      expect(fixed.single.startQ, 1);
      expect(fixed.single.endQ, 20);
    });

    test('describeSections formats each line', () {
      final fixed = autoFixSections(
        [
          const ExamSection(name: 'A', startQ: 1, endQ: 12, type: 'mcq'),
          const ExamSection(name: 'B', startQ: 13, endQ: 20, type: 'trueFalse'),
        ],
        20,
      );
      expect(
        describeSections(fixed),
        'A (MCQ): Questions 1–12\nB (T/F): Questions 13–20',
      );
    });
  });
}
