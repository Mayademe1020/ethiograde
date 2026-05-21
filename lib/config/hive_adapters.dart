import 'package:hive/hive.dart';

import '../models/student.dart';
import '../models/class_info.dart';
import '../models/assessment.dart';
import '../models/scan_result.dart';
import '../models/audit_entry.dart';
import '../models/grading_scale.dart';
import '../models/teacher.dart';
import '../models/weighted_grade.dart';

/// Register all Hive TypeAdapters.
///
/// Must be called BEFORE opening any typed box.
/// Adapters enable type-safe binary serialization instead of raw Map storage.
void registerHiveAdapters() {
  // Student
  Hive.registerAdapter(StudentAdapter());

  // ClassInfo
  Hive.registerAdapter(ClassInfoAdapter());

  // Assessment + nested types
  Hive.registerAdapter(AssessmentAdapter());
  Hive.registerAdapter(AssessmentStatusAdapter());
  Hive.registerAdapter(QuestionAdapter());
  Hive.registerAdapter(QuestionTypeAdapter());
  Hive.registerAdapter(EssayRubricAdapter());

  // ScanResult + nested types
  Hive.registerAdapter(ScanResultAdapter());
  Hive.registerAdapter(ScanStatusAdapter());
  Hive.registerAdapter(AnswerMatchAdapter());
  Hive.registerAdapter(BoundingBoxAdapter());


  // Audit
  Hive.registerAdapter(AuditEntryAdapter());

  // Grading scales
  Hive.registerAdapter(GradingScaleAdapter());
  Hive.registerAdapter(GradeRangeAdapter());

  // Teacher
  Hive.registerAdapter(TeacherAdapter());


  // Weighted grades
  Hive.registerAdapter(WeightedGradeScaleAdapter());
  Hive.registerAdapter(GradeComponentAdapter());
}
