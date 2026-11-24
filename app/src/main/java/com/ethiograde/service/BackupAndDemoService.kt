package com.ethiograde.service

import com.ethiograde.model.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

@Serializable
data class BackupPayload(
    val version: Int = 1,
    val exportDateMillis: Long = System.currentTimeMillis(),
    val students: List<Student>,
    val classes: List<ClassInfo>,
    val assessments: List<Assessment>,
    val scanResults: List<ScanResult>,
    val checksum: String = ""
)

object BackupService {
    private val json = Json { ignoreUnknownKeys = true; prettyPrint = true; encodeDefaults = true }
    private val MAGIC_V2 = "EGB2".toByteArray(Charsets.US_ASCII)
    private const val PBKDF2_ITERATIONS = 65_536

    fun deriveKeyFromPassphrase(passphrase: String, salt: ByteArray): ByteArray {
        val spec = PBEKeySpec(passphrase.toCharArray(), salt, PBKDF2_ITERATIONS, 256)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        return factory.generateSecret(spec).encoded
    }

    fun createPassphraseBackup(
        passphrase: String,
        students: List<Student>,
        classes: List<ClassInfo>,
        assessments: List<Assessment>,
        scanResults: List<ScanResult>
    ): ByteArray {
        require(passphrase.isNotBlank()) { "Passphrase is required for portable encrypted backups" }
        val signed = encodeSignedPayload(students, classes, assessments, scanResults)
        val rng = SecureRandom()
        val salt = ByteArray(16).also { rng.nextBytes(it) }
        val iv = ByteArray(16).also { rng.nextBytes(it) }
        val key = deriveKeyFromPassphrase(passphrase, salt)
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        val encrypted = cipher.doFinal(signed)
        return MAGIC_V2 + salt + iv + encrypted
    }

    fun createEncryptedBackup(
        aesKey: ByteArray,
        students: List<Student>,
        classes: List<ClassInfo>,
        assessments: List<Assessment>,
        scanResults: List<ScanResult>
    ): ByteArray {
        val signed = encodeSignedPayload(students, classes, assessments, scanResults)
        val iv = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(aesKey, "AES"), IvParameterSpec(iv))
        val encrypted = cipher.doFinal(signed)
        return iv + encrypted
    }

    private fun encodeSignedPayload(
        students: List<Student>,
        classes: List<ClassInfo>,
        assessments: List<Assessment>,
        scanResults: List<ScanResult>
    ): ByteArray {
        val raw = BackupPayload(
            students = students,
            classes = classes,
            assessments = assessments,
            scanResults = scanResults
        )
        val hash = sha256(json.encodeToString(raw))
        return json.encodeToString(raw.copy(checksum = hash)).toByteArray(Charsets.UTF_8)
    }

    fun decryptBackup(
        bytes: ByteArray,
        passphrase: String? = null,
        fallbackDeviceAesKey: ByteArray? = null
    ): Result<BackupPayload> {
        return runCatching {
            val rawString = when {
                bytes.size > 36 && bytes.copyOfRange(0, 4).contentEquals(MAGIC_V2) -> {
                    val pass = passphrase?.takeIf { it.isNotBlank() }
                        ?: error("Enter the backup passphrase to decrypt this portable .egb archive")
                    val salt = bytes.copyOfRange(4, 20)
                    val iv = bytes.copyOfRange(20, 36)
                    val encrypted = bytes.copyOfRange(36, bytes.size)
                    val key = deriveKeyFromPassphrase(pass, salt)
                    try {
                        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
                        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
                        String(cipher.doFinal(encrypted), Charsets.UTF_8)
                    } catch (_: Exception) {
                        error("Wrong passphrase or corrupt backup file")
                    }
                }
                bytes.isNotEmpty() && bytes.first().toInt().toChar() == '{' -> {
                    String(bytes, Charsets.UTF_8)
                }
                bytes.size > 16 && fallbackDeviceAesKey != null -> {
                    val iv = bytes.copyOfRange(0, 16)
                    val encrypted = bytes.copyOfRange(16, bytes.size)
                    val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
                    cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(fallbackDeviceAesKey, "AES"), IvParameterSpec(iv))
                    String(cipher.doFinal(encrypted), Charsets.UTF_8)
                }
                else -> error("Unrecognized backup format")
            }
            val payload = json.decodeFromString<BackupPayload>(rawString)
            if (payload.checksum.isNotBlank()) {
                val expected = sha256(json.encodeToString(payload.copy(checksum = "")))
                require(expected == payload.checksum) { "Backup checksum verification failed" }
            }
            payload
        }
    }

    fun isPortablePassphraseBackup(bytes: ByteArray): Boolean =
        bytes.size > 36 && bytes.copyOfRange(0, 4).contentEquals(MAGIC_V2)

    private fun sha256(text: String): String {
        return MessageDigest.getInstance("SHA-256")
            .digest(text.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }
}

data class DemoDataset(
    val classes: List<ClassInfo>,
    val students: List<Student>,
    val assessments: List<Assessment>,
    val scanResults: List<ScanResult>
)

object DemoDataService {
    fun buildDemoData(academicYear: String): DemoDataset {
        val demoClass = ClassInfo(
            id = "demo-class-001",
            name = "Grade 5A — Mathematics",
            grade = 5,
            section = "A",
            subject = "Mathematics",
            academicYear = academicYear,
            studentCount = 5,
            isHomeroom = true
        )

        val students = listOf(
            Student(id = "demo-s1", studentId = "101", firstName = "Abel", lastName = "Tesfaye", gender = "M", classIds = listOf(demoClass.id), className = demoClass.name, section = "A", grade = 5, parentPhone = "+251911223344"),
            Student(id = "demo-s2", studentId = "102", firstName = "Bethlehem", lastName = "Assefa", gender = "F", classIds = listOf(demoClass.id), className = demoClass.name, section = "A", grade = 5, parentPhone = "+251911223345"),
            Student(id = "demo-s3", studentId = "103", firstName = "Dawit", lastName = "Haile", gender = "M", classIds = listOf(demoClass.id), className = demoClass.name, section = "A", grade = 5, parentPhone = "+251911223346"),
            Student(id = "demo-s4", studentId = "104", firstName = "Helen", lastName = "Kebede", gender = "F", classIds = listOf(demoClass.id), className = demoClass.name, section = "A", grade = 5, parentPhone = "+251911223347"),
            Student(id = "demo-s5", studentId = "105", firstName = "Yonas", lastName = "Alemu", gender = "M", classIds = listOf(demoClass.id), className = demoClass.name, section = "A", grade = 5, parentPhone = "+251911223348")
        )

        val keys20 = listOf("A", "B", "C", "D", "A", "B", "C", "D", "E", "A", "B", "C", "D", "A", "B", "C", "D", "E", "A", "B")
        val test20Q = Assessment(
            id = "test-20q-001",
            title = "20Q Practice Test",
            subject = "Mathematics",
            classId = demoClass.id,
            className = demoClass.name,
            gradeLevel = 5,
            academicYear = academicYear,
            category = "Quiz",
            questions = keys20.mapIndexed { idx, ans ->
                Question(number = idx + 1, text = "Question ${idx + 1}", type = QuestionType.MCQ, correctAnswer = ans, points = 1.0)
            },
            sections = listOf(AnswerKeySection(title = "Part I — MCQ", type = QuestionType.MCQ, start = 1, end = 20)),
            isAnswerKeyConfirmed = true
        ).let { it.copy(answerKeyFingerprint = it.computeAnswerKeyFingerprint()) }

        val quiz1Keys = listOf("B", "C", "A", "D", "B", "A", "C", "D", "B", "A")
        val quiz1 = Assessment(
            id = "demo-assessment-001",
            title = "Unit 1 Math Quiz",
            subject = "Mathematics",
            classId = demoClass.id,
            className = demoClass.name,
            gradeLevel = 5,
            academicYear = academicYear,
            category = "Quiz",
            questions = quiz1Keys.mapIndexed { idx, ans ->
                Question(number = idx + 1, text = "Math Q${idx + 1}", type = QuestionType.MCQ, correctAnswer = ans, points = 1.0)
            },
            sections = listOf(AnswerKeySection(title = "Multiple Choice", type = QuestionType.MCQ, start = 1, end = 10)),
            isCompleted = true,
            isAnswerKeyConfirmed = true
        ).let { it.copy(answerKeyFingerprint = it.computeAnswerKeyFingerprint()) }

        val quiz2 = Assessment(
            id = "demo-assessment-002",
            title = "Midterm Examination",
            subject = "Mathematics",
            classId = demoClass.id,
            className = demoClass.name,
            gradeLevel = 5,
            academicYear = academicYear,
            category = "Midterm",
            questions = quiz1Keys.mapIndexed { idx, ans ->
                Question(number = idx + 1, text = "Midterm Q${idx + 1}", type = QuestionType.MCQ, correctAnswer = ans, points = 2.0)
            },
            sections = listOf(AnswerKeySection(title = "Core Problems", type = QuestionType.MCQ, start = 1, end = 10, pointsPerQuestion = 2.0)),
            isAnswerKeyConfirmed = true
        ).let { it.copy(answerKeyFingerprint = it.computeAnswerKeyFingerprint()) }

        val studentScores = listOf(9, 8, 6, 10, 4)
        val scanResults = students.mapIndexed { sIdx, student ->
            val targetCorrect = studentScores[sIdx]
            val matches = quiz1.questions.mapIndexed { qIdx, q ->
                val ok = qIdx < targetCorrect
                val det = if (ok) q.correctAnswer else if (q.correctAnswer == "A") "B" else "A"
                AnswerMatch(q.number, det, q.correctAnswer, ok, if (ok) q.points else 0.0, q.points, 0.94)
            }
            val total = matches.sumOf { it.score }
            val pct = total / quiz1.maxScore * 100.0
            ScanResult(
                id = "demo-res-q1-${student.id}",
                assessmentId = quiz1.id,
                studentId = student.id,
                studentName = student.fullName,
                answers = matches,
                totalScore = total,
                maxScore = quiz1.maxScore,
                percentage = pct,
                grade = ScoringService.calculateGrade(pct, quiz1.rubricType),
                status = if (sIdx == 4) ScanStatus.GRADED else ScanStatus.REVIEWED,
                confidence = 0.93,
                detectedMethod = "omr-only",
                scoredWithKeyFingerprint = quiz1.answerKeyFingerprint
            )
        }

        val midScores = listOf(8, 9, 5, 10, 4)
        val midResults = students.mapIndexed { sIdx, student ->
            val targetCorrect = midScores[sIdx]
            val matches = quiz2.questions.mapIndexed { qIdx, q ->
                val ok = qIdx < targetCorrect
                val det = if (ok) q.correctAnswer else if (q.correctAnswer == "A") "C" else "A"
                AnswerMatch(q.number, det, q.correctAnswer, ok, if (ok) q.points else 0.0, q.points, 0.88)
            }
            val total = matches.sumOf { it.score }
            val pct = total / quiz2.maxScore * 100.0
            ScanResult(
                id = "demo-res-q2-${student.id}",
                assessmentId = quiz2.id,
                studentId = student.id,
                studentName = student.fullName,
                answers = matches,
                totalScore = total,
                maxScore = quiz2.maxScore,
                percentage = pct,
                grade = ScoringService.calculateGrade(pct, quiz2.rubricType),
                status = if (sIdx == 2) ScanStatus.NEEDS_RESCAN else ScanStatus.GRADED,
                confidence = if (sIdx == 2) 0.55 else 0.91,
                uncertainQuestions = if (sIdx == 2) listOf(6, 7) else emptyList(),
                detectedMethod = "hybrid",
                scoredWithKeyFingerprint = quiz2.answerKeyFingerprint
            )
        }

        return DemoDataset(
            classes = listOf(demoClass),
            students = students,
            assessments = listOf(quiz1, quiz2, test20Q),
            scanResults = scanResults + midResults
        )
    }
}
