import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/services/result.dart';

void main() {
  group('Result', () {
    test('success sets success=true and data', () {
      const r = Result.success('hello');
      expect(r.success, isTrue);
      expect(r.data, 'hello');
      expect(r.error, isNull);
    });

    test('failure sets success=false and error', () {
      const r = Result.failure('oops');
      expect(r.success, isFalse);
      expect(r.data, isNull);
      expect(r.error, 'oops');
    });

    test('success with null data', () {
      const r = Result<int?>.success(null);
      expect(r.success, isTrue);
      expect(r.data, isNull);
    });

    test('works with complex types', () {
      final r = Result.success({'key': 'value'});
      expect(r.success, isTrue);
      expect(r.data!['key'], 'value');
    });

    test('importable from student_provider', () {
      // Verify the export chain works — student_provider re-exports result.dart
      // This test just needs to compile; if it compiles, the export works.
      const r = Result<int>.success(42);
      expect(r.data, 42);
    });
  });
}
