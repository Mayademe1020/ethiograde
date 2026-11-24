# EthioGrade (Native Android)

**100% Offline-First Grading, OMR/OCR Exam Scanning & Classroom Management for Ethiopian Teachers**

EthioGrade is a native Android application built with **Kotlin**, **Jetpack Compose**, **Material 3**, **Room + KSP**, **DataStore**, **CameraX**, and **on-device ML Kit Text Recognition**.

## Core Features

- **100% Offline Classroom Database**: Classes, students, assessments, scan results, attendance rolls, lesson notes, audit trail entries, and cryptographic Proof Vault records persisted locally in Room.
- **Ethiopian Calendar & Academic Years**: Dual Gregorian/Ethiopian date display and academic year scoping.
- **Exam Creation & Answer Keys**: Multi-section exams (MCQ, True/False, Multi-Answer, Short Answer, Fill-in-Blank), bulk key paste, key lock, fingerprint recalculation, and printable bubble sheet PDFs.
- **CameraX + ML Kit OMR/OCR Scanning**: Live camera scanning, zero-permission Android Photo Picker image import, EXIF orientation normalization, bubble fill density sampling, duplicate image `dHash` detection, OMR template calibration, and offline TTS score readouts.
- **Rapid Grading Workflows**: Quick Grade presets, Quick Enter with auto-saved drafts, and Fast Enter CA (`ፈጣን ምዘና`) rapid numeric keypad.
- **Grade Review, Audit Trail & Proof Vault**: Flagged paper queue, per-question & total score overrides, revertible audit trail, and SHA-256 Proof Vault verification.
- **Card Day (`የካርድ ቀን`) & Broadsheet Exports**: Homeroom semester consolidation with tied competition ranking, conduct/finance hold (`እዳ ያለበት`) overrides, 4-up Ministry PDF Report Cards, and Ministry Broadsheet CSV export.
- **Class Analytics & Item Analysis**: Subject averages, at-risk student alerts, per-student score trends, and per-question difficulty & discrimination metrics.
- **Parent SMS & AES-256 Backups**: Bilingual English/Amharic SMS templates launched via device SMS composer (`smsto:`) and offline `.egb` encrypted archive export/import via SAF.

## Tech Stack

- **Language**: Kotlin
- **UI**: Jetpack Compose + Material Design 3 (`PlusJakartaSans` typography, adaptive `NavigationBar` / `NavigationRail`)
- **Navigation**: Navigation Compose with `@Serializable` type-safe routes
- **Persistence**: Room (`ksp`) + Preferences DataStore
- **Scanning & Vision**: CameraX, Android ExifInterface, Google ML Kit Text Recognition (Latin/on-device), Coil
- **Exports**: Native Android `PdfDocument`, `FileProvider`, Storage Access Framework (`CreateDocument` / `OpenDocument`)

## Build Requirements

- JDK 21
- Android Gradle Plugin 9.1.1 / Gradle 9.3.1
- Android `compileSdk` / `targetSdk` 36 (`minSdk` 26)
