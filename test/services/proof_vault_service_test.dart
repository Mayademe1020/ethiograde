import 'package:flutter_test/flutter_test.dart';
import 'package:ethiograde/models/proof_vault_entry.dart';

void main() {
  group('ProofVaultEntry Tests', () {
    test('Calculates and verifies tamper-proof SHA-256 integrity hash', () {
      final entry = ProofVaultEntry(
        id: 'pv-001',
        assessmentId: 'assess-101',
        studentId: 'stud-202',
        studentName: 'Abebe Kebede',
        scannedAt: DateTime(2026, 11, 23, 10, 30),
        bubbleDensities: {
          1: {'A': 0.85, 'B': 0.12, 'C': 0.05, 'D': 0.02},
          2: {'A': 0.04, 'B': 0.91, 'C': 0.08, 'D': 0.01},
        },
        detectedAnswers: {1: 'A', 2: 'B'},
        totalScore: 2.0,
      );

      // Verify hash is generated
      expect(entry.integrityHash.isNotEmpty, isTrue);

      // Verify integrity check passes
      expect(entry.verifyIntegrity(), isTrue);

      // Verify tampering detection
      final tamperedEntry = ProofVaultEntry(
        id: entry.id,
        assessmentId: entry.assessmentId,
        studentId: entry.studentId,
        studentName: entry.studentName,
        scannedAt: entry.scannedAt,
        bubbleDensities: entry.bubbleDensities,
        detectedAnswers: {1: 'C', 2: 'B'}, // student tampered answer!
        totalScore: 2.0,
        integrityHash: entry.integrityHash, // old hash
      );

      expect(tamperedEntry.verifyIntegrity(), isFalse);
    });

    test('Serialization toMap and fromMap roundtrip', () {
      final entry = ProofVaultEntry(
        id: 'pv-002',
        assessmentId: 'a1',
        studentId: 's1',
        studentName: 'Almaz',
        scannedAt: DateTime(2026, 11, 23),
        bubbleDensities: {
          1: {'A': 0.9},
        },
        detectedAnswers: {1: 'A'},
        totalScore: 1.0,
      );

      final map = entry.toMap();
      final revived = ProofVaultEntry.fromMap(map);

      expect(revived.id, equals(entry.id));
      expect(revived.integrityHash, equals(entry.integrityHash));
      expect(revived.verifyIntegrity(), isTrue);
    });
  });
}
