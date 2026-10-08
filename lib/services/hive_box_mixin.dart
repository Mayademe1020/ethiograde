import 'package:hive_flutter/hive_flutter.dart';
import 'app_log.dart';

/// Mixin for consistent Hive box access across all providers.
///
/// Provides two patterns:
/// 1. **Lazy open** — opens the box if not already open (safe for any timing)
/// 2. **Assume open** — throws if box isn't open (for boxes opened at startup)
///
/// Usage:
/// ```dart
/// class StudentProvider extends ChangeNotifier with HiveBoxMixin {
///   static const _boxName = 'students';
///
///   Future<void> loadStudents() async {
///     final box = await openBox(_boxName);
///     // ... use box
///   }
/// }
/// ```
mixin HiveBoxMixin {
  /// Safely open a Hive box — opens it if not already open.
  ///
  /// This is the recommended pattern for all providers.
  /// It handles the case where the box was opened at startup
  /// OR needs to be opened on-demand.
  Future<Box<T>> openBox<T>(String name) async {
    if (Hive.isBoxOpen(name)) {
      return Hive.box<T>(name);
    }
    AppLog.warn(this, 'openBox', 'Box "$name" was not pre-opened, opening now');
    return await Hive.openBox<T>(name);
  }

  /// Safely open a lazy Hive box.
  Future<LazyBox<T>> openLazyBox<T>(String name) async {
    if (Hive.isBoxOpen(name)) {
      return Hive.lazyBox<T>(name);
    }
    AppLog.warn(this, 'openLazyBox', 'Lazy box "$name" was not pre-opened, opening now');
    return await Hive.openLazyBox<T>(name);
  }

  /// Read all values from a box, mapping each to a typed model.
  ///
  /// Usage:
  /// ```dart
  /// final students = await readAll<Student>(
  ///   'students',
  ///   (data) => Student.fromMap(Map<String, dynamic>.from(data as Map)),
  /// );
  /// ```
  Future<List<T>> readAll<T>(
    String boxName,
    T Function(dynamic data) mapper,
  ) async {
    final box = await openBox(boxName);
    return box.values.map(mapper).toList();
  }

  /// Read all values from a box as raw maps (for backup/export).
  Future<List<Map<String, dynamic>>> readAllRaw(String boxName) async {
    final box = await openBox(boxName);
    return box.values
        .map((data) => Map<String, dynamic>.from(data as Map))
        .toList();
  }

  /// Write a single value to a box.
  Future<void> writeBox(String boxName, String key, dynamic value) async {
    final box = await openBox(boxName);
    await box.put(key, value);
  }

  /// Delete a single value from a box.
  Future<void> deleteBox(String boxName, String key) async {
    final box = await openBox(boxName);
    await box.delete(key);
  }

  /// Clear all values from a box.
  Future<void> clearBox(String boxName) async {
    final box = await openBox(boxName);
    await box.clear();
  }

  /// Check if a key exists in a box.
  Future<bool> boxContains(String boxName, String key) async {
    final box = await openBox(boxName);
    return box.containsKey(key);
  }

  /// Get the count of items in a box.
  Future<int> boxLength(String boxName) async {
    final box = await openBox(boxName);
    return box.length;
  }
}
