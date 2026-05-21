import 'package:flutter_test/flutter_test.dart';

import 'package:ethiograde/models/audit_entry.dart';

void main() {
  group('AuditEntry', () {
    test('auto-generates id and timestamp', () {
      final entry = AuditEntry(
        scanResultId: 'scan1',
        action: 'created',
        teacherId: 't1',
        teacherName: 'Mr. A');

      expect(entry.id, isNotEmpty);
      expect(entry.timestamp, isNotNull);
    });

    test('round-trips through toMap/fromMap', () {
      final original = AuditEntry(
        scanResultId: 'scan1',
        action: 'score_override',
        teacherId: 't1',
        teacherName: 'Mr. A',
        previousValues: {'totalScore': 50, 'grade': 'D'},
        newValues: {'totalScore': 60, 'grade': 'C'},
        reason: 'OCR misread');

      final map = original.toMap();
      final restored = AuditEntry.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.scanResultId, 'scan1');
      expect(restored.action, 'score_override');
      expect(restored.teacherName, 'Mr. A');
      expect(restored.previousValues['totalScore'], 50);
      expect(restored.newValues['totalScore'], 60);
      expect(restored.reason, 'OCR misread');
    });

    test('changeDescription is human-readable', () {
      final created = AuditEntry(
        scanResultId: 's1',
        action: 'created',
        teacherId: 't1',
        teacherName: 'A',
        newValues: {'grade': 'B+', 'percentage': 82.5});
      expect(created.changeDescription, contains('B+'));

      final override = AuditEntry(
        scanResultId: 's1',
        action: 'score_override',
        teacherId: 't1',
        teacherName: 'A',
        previousValues: {'totalScore': 45},
        newValues: {'totalScore': 55});
      expect(override.changeDescription, contains('45'));
      expect(override.changeDescription, contains('55'));

      final reassigned = AuditEntry(
        scanResultId: 's1',
        action: 'reassigned',
        teacherId: 't1',
        teacherName: 'A',
        previousValues: {'studentName': 'Abebe'},
        newValues: {'studentName': 'Kebede'});
      expect(reassigned.changeDescription, contains('Abebe'));
      expect(reassigned.changeDescription, contains('Kebede'));
    });

    test('description returns change description', () {
      final entry = AuditEntry(
        scanResultId: 's1',
        action: 'created',
        teacherId: 't1',
        teacherName: 'A',
        newValues: {'grade': 'A'});

      final desc = entry.description;
      expect(desc, contains('Grade created'));
    });

    test('scale_change entry round-trips with ranges', () {
      final entry = AuditEntry(
        scanResultId: 'scale:abc123',
        action: 'scale_change',
        teacherId: 't1',
        teacherName: 'Mr. A',
        previousValues: {
          'name': 'School Scale',
          'ranges': [
            {'grade': 'A', 'minScore': 90, 'maxScore': 100},
          ],
        },
        newValues: {
          'name': 'School Scale',
          'ranges': [
            {'grade': 'A', 'minScore': 85, 'maxScore': 100},
            {'grade': 'B', 'minScore': 70, 'maxScore': 84},
          ],
        },
        reason: 'Scale updated');

      final map = entry.toMap();
      final restored = AuditEntry.fromMap(map);

      expect(restored.action, 'scale_change');
      expect(restored.scanResultId, 'scale:abc123');
      expect(restored.previousValues['name'], 'School Scale');
      expect(restored.newValues['ranges'], hasLength(2));
      expect(restored.reason, 'Scale updated');
    });
  });
}
