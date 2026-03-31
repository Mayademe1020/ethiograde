import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../services/locale_provider.dart';
import '../../services/assessment_provider.dart';
import '../../services/image_hash_service.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/ocr_service.dart';
import '../../services/session_service.dart';
import '../../widgets/paper_guide_overlay.dart';

/// Camera screen with continuous batch capture flow.
///
/// Teacher taps capture → image stored, counter increments.
/// No per-scan processing — all images are batch-processed when the
/// teacher taps "Done Scanning" (navigates to BatchScanScreen).
///
/// This keeps the capture loop fast and uninterrupted on 2GB devices.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isCapturing = false;
  bool _isFlashOn = false;
  final List<String> _capturedImages = [];
  final List<int?> _capturedHashes = []; // Parallel hash cache for batch
  List<int?> _existingHashes = []; // Hashes from previously saved scans
  bool _existingHashesLoaded = false;
  /// Track whether images were handed off to batch processing.
  /// If teacher backs out without scanning, clean up captured files.
  bool _batchStarted = false;
  Assessment? _selectedAssessment;
  PaperGuideState _guideState = PaperGuideState.idle;
  // Re-scan mode: single capture → immediate regrade → return result
  String? _reScanStudentId;
  String? _reScanStudentName;
  bool _isReScanMode = false;
  bool _isReScanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<LocaleProvider>().isAmharic
                  ? 'የካሜራ ፈቃድ ያስፈልጋል'
                  : 'Camera permission required',
            ),
          ),
        );
        Navigator.pop(context);
      }
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      _cameraController = CameraController(
        _cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      await _cameraController!.setFlashMode(FlashMode.off);
      await _cameraController!.setExposureMode(ExposureMode.auto);
      await _cameraController!.setFocusMode(FocusMode.auto);

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAm = context.watch<LocaleProvider>().isAmharic;
    final assessments = context.watch<AssessmentProvider>().assessments;

    _selectedAssessment ??=
        ModalRoute.of(context)?.settings.arguments as Assessment?;

    // Check for re-scan mode via Map arguments
    if (!_isReScanMode) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _selectedAssessment ??= args['assessment'] as Assessment?;
        _reScanStudentId = args['studentId'] as String?;
        _reScanStudentName = args['studentName'] as String?;
        if (_reScanStudentId != null && _reScanStudentName != null) {
          _isReScanMode = true;
        }
        // Resume: pre-populate captured images from incomplete session
        final existingImages = args['existingImages'] as List<String>?;
        if (existingImages != null && existingImages.isNotEmpty && _capturedImages.isEmpty) {
          _capturedImages.addAll(existingImages);
          // Look up assessment by ID if not already set
          final assessmentId = args['assessmentId'] as String?;
          if (assessmentId != null && _selectedAssessment == null) {
            _selectedAssessment = context
                .read<AssessmentProvider>()
                .assessments
                .cast<Assessment?>()
                .firstWhere((a) => a?.id == assessmentId, orElse: () => null);
          }
        }
      }
    }

    // Load existing hashes once when assessment is known
    if (_selectedAssessment != null && !_existingHashesLoaded) {
      _loadExistingHashes(_selectedAssessment!);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Camera preview
                Positioned.fill(
                  child: CameraPreview(_cameraController!),
                ),

                // Scan guide overlay
                Positioned.fill(
                  child: PaperGuideOverlay(
                    state: _guideState,
                    isAmharic: isAm,
                  ),
                ),

                // Top bar with counter
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.6),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  isAm ? 'ፈተና ማሰስ' : 'Scanning Mode',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${_capturedImages.length} '
                                  '${isAm ? 'ወረቀት ተይዟል' : 'papers captured'}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isFlashOn ? Icons.flash_on : Icons.flash_off,
                              color: Colors.white,
                            ),
                            onPressed: _toggleFlash,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Assessment selector
                if (_selectedAssessment == null)
                  Positioned(
                    top: 100,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAm ? 'ፈተና ይምረጡ' : 'Select Assessment',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<Assessment>(
                            dropdownColor: Colors.grey.shade900,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.grey.shade800,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            items: assessments
                                .where(
                                  (a) =>
                                      a.status == AssessmentStatus.active,
                                )
                                .map(
                                  (a) => DropdownMenuItem(
                                    value: a,
                                    child: Text(
                                      '${a.title} (${a.subject})',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (a) {
                              setState(() => _selectedAssessment = a);
                              if (a != null) _loadExistingHashes(a);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                // Bottom controls
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.8),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Column(
                        children: [
                          // Capture hint when no images yet
                          if (_capturedImages.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                isAm
                                    ? 'ወረቀቱን ካሜራው ውስጥ ካስተካከሉ በኋላ ይያዙ'
                                    : 'Align paper in frame, then tap capture',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),

                          // Capture button row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Thumbnail of last captured image
                              Semantics(
                                label: isAm
                                    ? 'የተያዙ ወረቀቶች ዝርዝር'
                                    : 'View captured papers',
                                button: true,
                                child: GestureDetector(
                                  onTap: _capturedImages.isNotEmpty
                                      ? _showCapturedImages
                                      : null,
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.white38,
                                      ),
                                    ),
                                    child: _capturedImages.isNotEmpty
                                        ? ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Image.file(
                                              File(_capturedImages.last),
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.photo_library,
                                            color: Colors.white54,
                                          ),
                                  ),
                                ),
                              ),

                              // Capture button
                              Semantics(
                                label: isAm ? 'ወረቀት ያዙ' : 'Capture photo',
                                button: true,
                                child: GestureDetector(
                                  onTap: _isCapturing ? null : _captureImage,
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 4,
                                      ),
                                    ),
                                    child: Container(
                                      margin: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _isCapturing
                                            ? Colors.grey
                                            : AppTheme.primaryGreen,
                                      ),
                                      child: _isCapturing
                                          ? const CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            )
                                          : const Icon(
                                              Icons.camera,
                                              color: Colors.white,
                                              size: 32,
                                            ),
                                    ),
                                  ),
                                ),
                              ),

                              // Done Scanning button
                              Semantics(
                                label: isAm
                                    ? 'ማሰስ ጨርስ'
                                    : 'Done scanning',
                                button: true,
                                child: GestureDetector(
                                  onTap: _capturedImages.isNotEmpty
                                      ? _finishBatch
                                      : null,
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: _capturedImages.isNotEmpty
                                          ? AppTheme.primaryGreen
                                          : Colors.white24,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.check,
                                      color: _capturedImages.isNotEmpty
                                          ? Colors.white
                                          : Colors.white54,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // "Done Scanning" label + counter
                          if (_capturedImages.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  // Captured count badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${_capturedImages.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    isAm
                                        ? 'ይዘት ካለ ማሰስ ያልቁ'
                                        : 'Tap ✓ when done scanning',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Capture an image and add it to the batch — no processing.
  Future<void> _captureImage() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    if (_selectedAssessment == null) {
      final isAm = context.read<LocaleProvider>().isAmharic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAm ? 'ፈተና ይምረጡ' : 'Please select an assessment first',
          ),
        ),
      );
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final image = await _cameraController!.takePicture();
      final hash = ImageHashService().computeHash(image.path);

      // Check for duplicates against current batch + existing scans
      if (hash != null) {
        final allHashes = [..._existingHashes, ..._capturedHashes];
        final dupIndex = ImageHashService().findDuplicate(hash, allHashes);

        if (dupIndex >= 0) {
          final isDuplicate = await _showDuplicateDialog();
          if (!isDuplicate) {
            // Teacher chose to skip — delete the captured file
            try { await File(image.path).delete(); } catch (_) {}
            return;
          }
        }
      }

      _capturedImages.add(image.path);
      _capturedHashes.add(hash);

      // Persist scan session to Hive immediately (minimizes crash window)
      if (_selectedAssessment != null) {
        await SessionService().saveSession(
          assessmentId: _selectedAssessment!.id,
          assessmentTitle: '${_selectedAssessment!.title} (${_selectedAssessment!.subject})',
          imagePaths: List<String>.from(_capturedImages),
        );
      }

      // Re-scan mode: process immediately and return result
      if (_isReScanMode && _selectedAssessment != null) {
        await _processReScan(image.path);
        // Re-scan done — clean up session (single paper, not a batch)
        await SessionService().completeSession();
        return;
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<LocaleProvider>().isAmharic
                  ? 'ስህተት ተከስቷል፣ እንደገና ይሞክሩ'
                  : 'Capture failed — try again',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// Show grid of captured images for review.
  void _showCapturedImages() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (c, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                '${_capturedImages.length} '
                '${context.read<LocaleProvider>().isAmharic ? 'ወረቀት ተይዟል' : 'Papers Captured'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _capturedImages.length,
                  itemBuilder: (context, index) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_capturedImages[index]),
                        fit: BoxFit.cover,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Load hashes from previously saved scan results for this assessment.
  Future<void> _loadExistingHashes(Assessment assessment) async {
    if (_existingHashesLoaded) return;
    _existingHashesLoaded = true;
    try {
      final grading = HybridGradingService();
      final existingScans = await grading.loadScanResults(assessment.id);
      _existingHashes = existingScans.map((s) => s.imageHash).toList();
    } catch (_) {
      _existingHashes = [];
    }
  }

  /// Show bilingual possible-duplicate warning. Returns true if teacher wants to keep.
  Future<bool> _showDuplicateDialog() async {
    final isAm = context.read<LocaleProvider>().isAmharic;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppTheme.primaryYellow, size: 22),
            const SizedBox(width: 8),
            Text(isAm ? 'ሊመሰሉ የሚችሉ ቅጂዎች' : 'Possible Duplicate'),
          ],
        ),
        content: Text(
          isAm
              ? 'ይህ ወረቀት አስቀድሞ እንደተሰካን ይመስላል። እርግጠኛ አይደሉም? መልሶቹ ከተሰሩ በኋላ እንደገና ይመረመራሉ።'
              : 'This looks similar to a paper already captured. Not sure? '
                  'Answers will be double-checked after processing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),  // Keep
            child: Text(isAm ? 'ተቀምጥ' : 'Keep'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, false), // Skip
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryRed,
            ),
            child: Text(isAm ? 'ዝለል' : 'Skip'),
          ),
        ],
      ),
    );
    return result ?? false; // Default: keep (safe default)
  }

  /// Re-scan mode: process single image immediately and return to review.
  Future<void> _processReScan(String imagePath) async {
    setState(() => _isReScanning = true);
    try {
      final result = await HybridGradingService().regradePaper(
        imagePath: imagePath,
        assessment: _selectedAssessment!,
        studentId: _reScanStudentId!,
        studentName: _reScanStudentName!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<LocaleProvider>().isAmharic
                  ? 'ድጋሜ ተሰልቷል — ውጤቱ ተዘምኗል'
                  : 'Re-scan complete — score updated',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, result);
      }
    } catch (e) {
      debugPrint('Re-scan error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<LocaleProvider>().isAmharic
                  ? 'ስህተት ተከስቷል፣ እንደገና ይሞክሩ'
                  : 'Re-scan failed — try again',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isReScanning = false);
    }
  }

  /// Navigate to BatchScanScreen for batch processing.
  Future<void> _finishBatch() async {
    _batchStarted = true;
    // Session is complete — batch processing will handle results
    await SessionService().completeSession();
    if (!mounted) return;
    Navigator.pushNamed(
      context,
      AppRoutes.batchScan,
      arguments: {
        'images': _capturedImages,
        'assessment': _selectedAssessment,
      },
    );
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;
    setState(() => _isFlashOn = !_isFlashOn);
    await _cameraController!.setFlashMode(
      _isFlashOn ? FlashMode.torch : FlashMode.off,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    // Clean up captured images if teacher backed out without scanning
    if (!_batchStarted && _capturedImages.isNotEmpty) {
      OcrService().cleanupImages(_capturedImages);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }
}
