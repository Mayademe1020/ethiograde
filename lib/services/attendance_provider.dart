import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/attendance_record.dart';
import 'hive_box_mixin.dart';
import 'result.dart';

/// Tracks daily attendance per class.
///
/// Stores [AttendanceRecord] as plain maps (see [HiveBoxMixin] convention).
/// One record per class per day; re-saving the same day overwrites it.
class AttendanceProvider extends ChangeNotifier with HiveBoxMixin {
  static const _boxName = 'attendance';

  final List<AttendanceRecord> _records = [];
  bool _loaded = false;
  bool _loadFailed = false;

  List<AttendanceRecord> get records => List.unmodifiable(_records);
  bool get isLoaded => _loaded;
  bool get loadFailed => _loadFailed;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final box = await openBox(_boxName);
      _records
        ..clear()
        ..addAll(
          box.values
              .map(
                (data) => AttendanceRecord.fromMap(
                  Map<String, dynamic>.from(data as Map),
                ),
              )
              .toList(),
        )
        ..sort((a, b) => b.date.compareTo(a.date));
      _loaded = true;
      _loadFailed = false;
    } catch (e) {
      debugPrint('AttendanceProvider: load failed ($e)');
      _records.clear();
      _loaded = true;
      _loadFailed = true;
    }
    notifyListeners();
  }

  Future<void> reload() async {
    _loaded = false;
    _loadFailed = false;
    await load();
  }

  /// Find the record for a specific class on a specific calendar day.
  AttendanceRecord? recordForDate(String classId, DateTime date) {
    return _records.cast<AttendanceRecord?>().firstWhere(
          (r) =>
              r != null &&
              r.classId == classId &&
              _sameDay(r.date, date),
          orElse: () => null,
        );
  }

  /// All records for a class, newest first.
  List<AttendanceRecord> historyForClass(String classId) =>
      _records.where((r) => r.classId == classId).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  /// Save (insert or overwrite) a record. Keyed by `${classId}_${date}`.
  Future<Result<AttendanceRecord>> saveRecord(AttendanceRecord record) async {
    if (record.classId.isEmpty) {
      return const Result.failure('Class is required');
    }
    if (record.entries.isEmpty) {
      return const Result.failure('No students recorded');
    }
    try {
      final box = await openBox(_boxName);
      final key = _key(record.classId, record.date);
      final updated = AttendanceRecord(
        id: record.id.isNotEmpty ? record.id : const Uuid().v4(),
        classId: record.classId,
        date: record.date,
        entries: record.entries,
        updatedAt: DateTime.now(),
      );
      await box.put(key, updated.toMap());
      final index = _records.indexWhere((r) => r.id == updated.id);
      if (index >= 0) {
        _records[index] = updated;
      } else {
        _records.add(updated);
      }
      _records.sort((a, b) => b.date.compareTo(a.date));
      notifyListeners();
      return Result.success(updated);
    } catch (e) {
      debugPrint('AttendanceProvider: saveRecord failed ($e)');
      return const Result.failure('Failed to save attendance');
    }
  }

  Future<Result<void>> deleteRecord(String id) async {
    try {
      final box = await openBox(_boxName);
      final rec = _records.where((r) => r.id == id).firstOrNull;
      if (rec == null) return const Result.failure('Record not found');
      await box.delete(_key(rec.classId, rec.date));
      _records.removeWhere((r) => r.id == id);
      notifyListeners();
      return const Result.success(null);
    } catch (e) {
      debugPrint('AttendanceProvider: deleteRecord failed ($e)');
      return const Result.failure('Failed to delete record');
    }
  }

  String _key(String classId, DateTime date) =>
      '${classId}_${_dayKey(date)}';

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
