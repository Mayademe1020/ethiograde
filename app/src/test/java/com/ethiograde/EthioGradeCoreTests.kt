package com.ethiograde

import com.ethiograde.model.*
import com.ethiograde.service.*
import org.junit.Assert.*
import org.junit.Test
import java.security.SecureRandom
import java.time.LocalDate

class EthioGradeCoreTests {

    @Test
    fun scoringService_handlesMcqTrueFalseMultiAndShortAnswer() {
        val mcq = Question(number = 1, type = QuestionType.MCQ, correctAnswer = "B", points = 2.0)
        val tf = Question(number = 2, type = QuestionType.TRUE_FALSE, correctAnswer = "True", points = 1.0)
        val multi = Question(number = 3, type = QuestionType.MULTI_ANSWER, correctAnswer = "A,C", points = 2.0)
        val shortQ = Question(number = 4, type = QuestionType.SHORT_ANSWER, correctAnswer = "Photosynthesis", points = 3.0)
        val numQ = Question(number = 5, type = QuestionType.SHORT_ANSWER, correctAnswer = "3.14", points = 2.0)

        assertEquals(true to 2.0, ScoringService.checkAnswer("b", mcq))
        assertEquals(false to 0.0, ScoringService.checkAnswer("A", mcq))

        assertEquals(true to 1.0, ScoringService.checkAnswer("እውነት", tf))
        assertEquals(false to 0.0, ScoringService.checkAnswer("ሐሰት", tf))

        assertEquals(true to 2.0, ScoringService.checkAnswer("A, C", multi))
        val (partialOk, partialPts) = ScoringService.checkAnswer("A", multi)
        assertFalse(partialOk)
        assertEquals(1.0, partialPts, 0.01)

        // Typo within Levenshtein <= 2 for >=7 char word
        assertEquals(true to 3.0, ScoringService.checkAnswer("Photosyntesis", shortQ))
        // Numeric tolerance
        assertEquals(true to 2.0, ScoringService.checkAnswer("3.142", numQ))
    }

    @Test
    fun scoringService_recalculatesKeyChangesWithoutClobberingOverrides() {
        val original = Assessment(
            id = "a1",
            title = "Math Quiz",
            questions = listOf(
                Question(number = 1, type = QuestionType.MCQ, correctAnswer = "A", points = 2.0),
                Question(number = 2, type = QuestionType.MCQ, correctAnswer = "B", points = 2.0)
            )
        )
        val priorResult = ScanResult(
            id = "r1",
            assessmentId = "a1",
            studentId = "s1",
            studentName = "Abel",
            answers = listOf(
                AnswerMatch(1, "C", "A", false, 0.0, 2.0, isOverridden = false),
                AnswerMatch(2, "B", "B", true, 2.0, 2.0, isOverridden = true)
            ),
            totalScore = 2.0,
            maxScore = 4.0,
            percentage = 50.0,
            grade = "D"
        )
        val updated = original.copy(
            questions = listOf(
                Question(number = 1, type = QuestionType.MCQ, correctAnswer = "C", points = 2.0),
                Question(number = 2, type = QuestionType.MCQ, correctAnswer = "D", points = 2.0)
            ),
            answerKeyRevision = 2
        ).let { it.copy(answerKeyFingerprint = it.computeAnswerKeyFingerprint()) }

        val rescored = ScoringService.recalculateForUpdatedKey(updated, listOf(priorResult))
        assertEquals(1, rescored.size)
        // Q1 re-graded as correct (+2), Q2 preserved teacher override (+2) -> 4/4 = 100% (A)
        assertEquals(4.0, rescored[0].totalScore, 0.01)
        assertEquals("A", rescored[0].grade)
        assertEquals(2, rescored[0].scoredWithKeyRevision)
    }

    @Test
    fun gradingScales_mapMoEAndCustomBandsAccurately() {
        assertEquals("A", ScoringService.calculateGrade(92.0, "moe_national"))
        assertEquals("B", ScoringService.calculateGrade(85.0, "moe_national"))
        assertEquals("C", ScoringService.calculateGrade(65.0, "moe_national"))
        assertEquals("F", ScoringService.calculateGrade(40.0, "moe_national"))

        val custom = GradingScale(
            id = "school-1",
            name = "Honors",
            ranges = listOf(
                GradeRange("Pass+", 80.0, 100.0),
                GradeRange("Pass", 60.0, 79.99),
                GradeRange("Needs Support", 0.0, 59.99)
            )
        )
        assertEquals("Pass+", ScoringService.calculateGrade(88.0, "custom:school-1", listOf(custom)))
        assertEquals("Needs Support", ScoringService.calculateGrade(55.0, "custom:school-1", listOf(custom)))
    }

    @Test
    fun answerParser_supportsEnglishAmharicAndSpatialMatching() {
        assertEquals(1 to "A", AnswerParser.parseQuestionAnswer("1. ሀ"))
        assertEquals(2 to "B", AnswerParser.parseQuestionAnswer("2) ለ"))
        assertEquals(3 to "True", AnswerParser.parseQuestionAnswer("3. እውነት"))
        assertEquals(4 to "False", AnswerParser.parseQuestionAnswer("4: False"))

        val regions = listOf(
            TextRegionInput("5.", 0.9, x = 50.0, y = 200.0),
            TextRegionInput("C", 0.9, x = 140.0, y = 203.0),
            TextRegionInput("6", 0.9, x = 50.0, y = 300.0),
            TextRegionInput("True", 0.85, x = 55.0, y = 340.0)
        )
        val parsed = AnswerParser.parseAnswersWithPosition(regions).associateBy { it.questionNumber }
        assertEquals("C", parsed[5]?.answer)
        assertEquals("True", parsed[6]?.answer)
    }

    @Test
    fun ethiopianCalendar_convertsKnownGregorianDate() {
        // September 11, 2024 -> Meskerem 1, 2017 E.C.
        val eth = EthiopianCalendarService.toEthiopic(LocalDate.of(2024, 9, 11))
        assertEquals(2017, eth.year)
        assertEquals(1, eth.month)
        assertEquals(1, eth.day)
        assertTrue(eth.formatted().contains("Meskerem 1, 2017"))
    }

    @Test
    fun phoneUtils_normalizesAndValidatesEthiopianNumbers() {
        assertEquals("+251911223344", PhoneUtils.normalize("0911 22 33 44"))
        assertEquals("+251712345678", PhoneUtils.normalize("712345678"))
        assertEquals("+251911223344", PhoneUtils.normalize("251911223344"))
        assertTrue(PhoneUtils.isValid("+251911223344"))
        assertFalse(PhoneUtils.isValid("+251511223344"))
    }

    @Test
    fun backupService_portablePassphraseBackupWorksAcrossDevicesAndRejectsTampering() {
        val students = listOf(Student(id = "s1", studentId = "101", firstName = "Abel", lastName = "Tesfaye"))
        val classes = listOf(ClassInfo(id = "c1", name = "Grade 5A"))
        val assessments = listOf(Assessment(id = "a1", title = "Quiz 1"))

        val portableBytes = BackupService.createPassphraseBackup(
            passphrase = "School-2017-Key!",
            students = students,
            classes = classes,
            assessments = assessments,
            scanResults = emptyList()
        )
        assertTrue(BackupService.isPortablePassphraseBackup(portableBytes))

        // Restore without any device AES key (simulating a brand new phone)
        val restored = BackupService.decryptBackup(portableBytes, passphrase = "School-2017-Key!", fallbackDeviceAesKey = null)
        assertTrue(restored.isSuccess)
        assertEquals("Abel", restored.getOrThrow().students.single().firstName)

        // Blank or wrong passphrase must fail cleanly
        assertTrue(BackupService.decryptBackup(portableBytes, passphrase = "", fallbackDeviceAesKey = null).isFailure)
        assertTrue(BackupService.decryptBackup(portableBytes, passphrase = "wrong-password", fallbackDeviceAesKey = null).isFailure)

        // Corrupt ciphertext must fail cleanly
        val tampered = portableBytes.copyOf().also { it[it.lastIndex] = (it.last().toInt() xor 0xFF).toByte() }
        assertTrue(BackupService.decryptBackup(tampered, passphrase = "School-2017-Key!", fallbackDeviceAesKey = null).isFailure)

        // Legacy device-key backup remains readable
        val deviceKey = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val legacyBytes = BackupService.createEncryptedBackup(deviceKey, students, classes, assessments, emptyList())
        assertFalse(BackupService.isPortablePassphraseBackup(legacyBytes))
        val legacyRestored = BackupService.decryptBackup(legacyBytes, passphrase = null, fallbackDeviceAesKey = deviceKey)
        assertTrue(legacyRestored.isSuccess)
        assertEquals("Quiz 1", legacyRestored.getOrThrow().assessments.single().title)
    }

    @Test
    fun csvImport_parsesStudentsSplitsFullNameAndFlagsBadPhone() {
        val csv = """
            ID,Full Name,Gender,Phone
            101,Abel Tesfaye,Male,0911223344
            102,Sara Kebede,F,12345
        """.trimIndent()

        val result = PdfExportAndCsvService.parseStudentsFromCsv(csv, classId = "c1", className = "5A")
        assertTrue(result.success)
        assertEquals(2, result.students.size)
        assertEquals("Abel", result.students[0].firstName)
        assertEquals("Tesfaye", result.students[0].lastName)
        assertEquals("M", result.students[0].gender)
        assertEquals("+251911223344", result.students[0].parentPhone)
        assertNull(result.students[1].parentPhone)
        assertEquals(1, result.warnings.size)
    }

    @Test
    fun proofVault_detectsScoreTamperingAndVerifiesValidRecord() {
        val densities = mapOf(1 to mapOf("A" to 0.85, "B" to 0.12))
        val detected = mapOf(1 to "A")
        val ts = 1_700_000_000_000L
        val hash = ProofVaultEntry.computeProofHash("a1", "s1", 10.0, densities, detected, ts)
        val valid = ProofVaultEntry(
            id = "a1_s1",
            assessmentId = "a1",
            studentId = "s1",
            studentName = "Abel",
            totalScore = 10.0,
            maxScore = 10.0,
            bubbleDensities = densities,
            detectedAnswers = detected,
            integrityHash = hash,
            scannedAtMillis = ts
        )
        assertTrue(valid.verifyIntegrity())
        assertFalse(valid.copy(totalScore = 9.0).verifyIntegrity())
    }

    @Test
    fun homeroomConsolidation_ranksTiesCorrectlyAndTracksAttendanceAndHold() {
        val cls = ClassInfo(id = "c1", name = "Grade 5A", grade = 5, section = "A", subject = "Math", academicYear = "2024-2025", isHomeroom = true)
        val s1 = Student(id = "s1", studentId = "1", firstName = "Abel", classIds = listOf("c1"))
        val s2 = Student(id = "s2", studentId = "2", firstName = "Beth", classIds = listOf("c1"))
        val s3 = Student(id = "s3", studentId = "3", firstName = "Dawit", classIds = listOf("c1"))
        val quiz = Assessment(id = "a1", title = "Quiz", subject = "Math", classId = "c1", academicYear = "2024-2025", semester = "Semester 1", questions = listOf(Question(1, type = QuestionType.MCQ, correctAnswer = "A", points = 10.0)))

        val results = listOf(
            ScanResult(assessmentId = "a1", studentId = "s1", studentName = "Abel", totalScore = 9.0, maxScore = 10.0, percentage = 90.0),
            ScanResult(assessmentId = "a1", studentId = "s2", studentName = "Beth", totalScore = 9.0, maxScore = 10.0, percentage = 90.0),
            ScanResult(assessmentId = "a1", studentId = "s3", studentName = "Dawit", totalScore = 7.0, maxScore = 10.0, percentage = 70.0)
        )
        val attendance = listOf(
            AttendanceRecord(classId = "c1", dateIso = "2024-10-01", entries = mapOf("s3" to AttendanceStatus.ABSENT))
        )
        val overrides = mapOf("c1_s3" to HomeroomOverride(id = "c1_s3", classId = "c1", studentId = "s3", conduct = "B", hasFinanceHold = true))

        val report = HomeroomConsolidationService.consolidate(
            classInfo = cls,
            students = listOf(s1, s2, s3),
            assessments = listOf(quiz),
            allResults = results,
            attendanceRecords = attendance,
            overrides = overrides,
            semester = "Semester 1",
            academicYear = "2024-2025",
            homeroomTeacherName = "Teacher"
        )
        val byId = report.students.associateBy { it.studentId }
        // Tied #1, #1, then #3
        assertEquals(1, byId["s1"]?.classRank)
        assertEquals(1, byId["s2"]?.classRank)
        assertEquals(3, byId["s3"]?.classRank)
        assertEquals(1, byId["s3"]?.absentDays)
        assertTrue(byId["s3"]?.hasFinanceHold == true)
        assertEquals("B", byId["s3"]?.conduct)
    }

    @Test
    fun bubbleTemplate_matchesAssessmentCountsAndPreservesOffsets() {
        assertEquals(StandardTemplates.moe20x5.name, StandardTemplates.matchAssessment(20, false).name)
        assertEquals(StandardTemplates.tf10.name, StandardTemplates.matchAssessment(10, true).name)
        assertEquals(StandardTemplates.moe120x5.name, StandardTemplates.matchAssessment(120, false).name)

        val shifted = StandardTemplates.moe20x5.copy(
            startX = StandardTemplates.moe20x5.startX + 24.0,
            startY = StandardTemplates.moe20x5.startY - 12.0,
            fillThreshold = 0.42
        )
        val (cx, cy) = shifted.bubbleCenter(0, 0)
        assertEquals(304.0, cx, 0.01)
        assertEquals(278.0, cy, 0.01)
        assertEquals(0.42, shifted.fillThreshold, 0.001)
    }
}
