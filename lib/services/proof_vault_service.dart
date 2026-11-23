import 'package:hive_flutter/hive_flutter.dart';
import '../models/proof_vault_entry.dart';
import 'hive_box_mixin.dart';

/// Service managing the Digital Proof Vault.
///
/// Stores unalterable, timestamped bubble density vectors and scan proof
/// records in Hive. Serves as the teacher's shield against post-grading
/// student alterations or parent disputes.
class ProofVaultService with HiveBoxMixin {
  static const String boxName = 'proof_vault';

  /// Saves a scan proof entry to Hive.
  /// Key format: `<assessmentId>_<studentId>`
  Future<void> saveEntry(ProofVaultEntry entry) async {
    final box = await Hive.openBox<Map>(boxName);
    final key = '${entry.assessmentId}_${entry.studentId}';
    await box.put(key, entry.toJson());
  }

  /// Retrieves a proof entry for a specific student and assessment.
  Future<ProofVaultEntry?> getEntry(String assessmentId, String studentId) async {
    final box = await Hive.openBox<Map>(boxName);
    final key = '${assessmentId}_${studentId}';
    final raw = box.get(key);
    if (raw == null) return null;
    return ProofVaultEntry.fromJson(Map<String, dynamic>.from(raw));
  }

  /// Retrieves all scan proofs for an assessment (e.g. for whole-class audit).
  Future<List<ProofVaultEntry>> getEntriesForAssessment(String assessmentId) async {
    final box = await Hive.openBox<Map>(boxName);
    final prefix = '${assessmentId}_';
    final entries = <ProofVaultEntry>[];

    for (final key in box.keys) {
      if (key is String && key.startsWith(prefix)) {
        final raw = box.get(key);
        if (raw != null) {
          entries.add(ProofVaultEntry.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
    }
    return entries;
  }

  /// Deletes all scan proofs associated with an assessment.
  Future<void> deleteEntriesForAssessment(String assessmentId) async {
    final box = await Hive.openBox<Map>(boxName);
    final prefix = '${assessmentId}_';
    final keysToDelete = box.keys
        .where((k) => k is String && k.startsWith(prefix))
        .toList();
    await box.deleteAll(keysToDelete);
  }

  /// Verifies whether the entry's integrity hash matches its density vectors.
  bool verifyIntegrity(ProofVaultEntry entry) {
    return entry.verifyIntegrity();
  }
}
