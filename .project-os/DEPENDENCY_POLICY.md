# Dependency Policy

EthioGrade should not add dependencies casually.

Dependencies affect:

- APK/AAB size
- Android compatibility
- offline reliability
- teacher data privacy
- build stability
- maintenance burden
- release risk

## Default Rule

Do not add a dependency without dependency review.

Prefer existing code, Flutter/Dart standard APIs, and already-installed packages when reasonable.

## Required Review Before Adding

Every proposed dependency must answer:

- What exact problem does it solve?
- Why can existing code or current packages not solve it safely?
- Does it work offline?
- Does it collect, transmit, or expose teacher/student data?
- What is the APK/AAB size impact?
- What Android build impact is expected?
- Is it actively maintained?
- Is the license acceptable?
- What tests will prove it works?
- What rollback path exists if it causes build or runtime issues?

## High-Risk Dependency Areas

Treat these as High/Strong/Deep model work:

- OCR
- OMR/computer vision
- camera/scanning
- storage/encryption
- database/sync
- Android build tooling
- analytics/telemetry
- payments
- cloud services

## Current Product Direction

Do not add Supabase or any cloud database now.

Cloud sync/database work requires explicit owner approval and a separate architecture decision.
