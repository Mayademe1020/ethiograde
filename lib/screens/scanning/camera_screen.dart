import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../services/assessment_provider.dart';
import '../../services/image_hash_service.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/ocr_service.dart';
import '../../services/weighted_grade_provider.dart';
import '../assessment/exam_day_create_screen.dart';
import '../../widgets/paper_guide_overlay.dart';

/// Arguments for re-scan mode: replaces an existing ScanResult with a fresh scan.
class ReScanArguments {
  final ScanResult existingResult;
  final Assessment assessment;

  const ReScanArguments({
    required this.existingResult,
    required this.assessment,
  });
}

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
  bool _isCameraStarting = true;
  String? _cameraError;
  final List<Timer> _cameraStartupTimers = [];
  final List<String> _capturedImages = [];
  final List<int?> _capturedHashes = []; // Parallel hash cache for batch
  List<int?> _existingHashes = []; // Hashes from previously saved scans
  bool _existingHashesLoaded = false;

  /// Track whether images were handed off to batch processing.
  /// If teacher backs out without scanning, clean up captured files.
  bool _batchStarted = false;
  Assessment? _selectedAssessment;
  PaperGuideState _guideState = PaperGuideState.idle;

  /// Re-scan mode: non-null when re-scanning a specific student's paper.
  ReScanArguments? _reScanArgs;
  bool _isReScanProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isCameraStarting = true;
      _cameraError = null;
      _isInitialized = false;
    });

    try {
      _cameras = await _withCameraTimeout<List<CameraDescription>>(
        availableCameras(),
        const Duration(seconds: 8),
      );
    } on TimeoutException {
      _showCameraError(
        'The camera is taking too long to start. Check app permission, close other camera apps, then try again.',
      );
      return;
    } on CameraException catch (e) {
      _showCameraError(
        e.description ?? 'Camera permission is required to scan papers.',
      );
      return;
    } catch (_) {
      _showCameraError(
        'The camera could not start on this device. You can retry or enter the answer key manually.',
      );
      return;
    }

    if (_cameras.isEmpty) {
      _showCameraError(
        'No camera was found on this device. You can still enter the answer key manually.',
      );
      return;
    }

    _cameraController = CameraController(
      _cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _withCameraTimeout<void>(
        _cameraController!.initialize(),
        const Duration(seconds: 10),
      );
      await _cameraController!.setFlashMode(FlashMode.off);
      await _cameraController!.setExposureMode(ExposureMode.auto);
      await _cameraController!.setFocusMode(FocusMode.auto);
    } on TimeoutException {
      _showCameraError(
        'The camera opened but did not finish starting. Try again in a moment.',
      );
      return;
    } on CameraException catch (e) {
      _showCameraError(
        e.description ?? 'Camera permission is required to scan papers.',
      );
      return;
    } catch (_) {
      _showCameraError(
        'The camera could not start. Try again or use manual answer entry.',
      );
      return;
    }

    if (mounted) {
      setState(() {
        _isInitialized = true;
        _isCameraStarting = false;
      });
    }
  }

  void _showCameraError(String message) {
    if (!mounted) return;
    setState(() {
      _cameraError = message;
      _isCameraStarting = false;
      _isInitialized = false;
    });
  }

  Future<T> _withCameraTimeout<T>(Future<T> operation, Duration duration) {
    final completer = Completer<T>();
    late final Timer timer;
    timer = Timer(duration, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Camera startup timed out'));
      }
    });
    _cameraStartupTimers.add(timer);

    operation
        .then(
          (value) {
            if (!completer.isCompleted) completer.complete(value);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
        )
        .whenComplete(() {
          timer.cancel();
          _cameraStartupTimers.remove(timer);
        });

    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final assessments = context.watch<AssessmentProvider>().assessments;

    // Detect re-scan mode from route arguments
    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    if (_reScanArgs == null && routeArgs is ReScanArguments) {
      _reScanArgs = routeArgs;
      _selectedAssessment = routeArgs.assessment;
    }
    _selectedAssessment ??= routeArgs is Assessment ? routeArgs : null;

    // Load existing hashes once when assessment is known
    if (_selectedAssessment != null && !_existingHashesLoaded) {
      _loadExistingHashes(_selectedAssessment!);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: !_isInitialized
          ? _CameraUnavailableView(
              isStarting: _isCameraStarting,
              message: _cameraError,
              onBack: () => Navigator.pop(context),
              onRetry: _initializeCamera,
              onManualEntry: () {
                if (_selectedAssessment != null) {
                  Navigator.pushReplacementNamed(
                    context,
                    AppRoutes.answerKey,
                    arguments: _selectedAssessment,
                  );
                  return;
                }
                Navigator.pushReplacementNamed(
                  context,
                  AppRoutes.createAssessment,
                  arguments: ExamDayStartMode.manualKey,
                );
              },
            )
          : Stack(
              children: [
                // Camera preview
                Positioned.fill(child: CameraPreview(_cameraController!)),

                // Scan guide overlay
                Positioned.fill(child: PaperGuideOverlay(state: _guideState)),

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
                                  _reScanArgs != null
                                      ? ("Re-Scan — ${_reScanArgs!.existingResult.studentName}")
                                      : ('Scanning Mode'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_reScanArgs == null)
                                  Text(
                                    '${_capturedImages.length} '
                                    '${'papers captured'}',
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

                // Assessment selector (hidden in re-scan mode)
                if (_selectedAssessment == null && _reScanArgs == null)
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
                            'Select Assessment',
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
                                  (a) => a.status == AssessmentStatus.active,
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
                          // Re-scan mode: single capture + process
                          if (_reScanArgs != null) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                _isReScanProcessing
                                    ? ('Re-grading...')
                                    : ('Align paper, then tap to re-scan'),
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            GestureDetector(
                              onTap: (_isCapturing || _isReScanProcessing)
                                  ? null
                                  : _captureAndReGrade,
                              child: Container(
                                width: 80,
                                height: 80,
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
                                    color: (_isCapturing || _isReScanProcessing)
                                        ? Colors.grey
                                        : AppTheme.primaryYellow,
                                  ),
                                  child: (_isCapturing || _isReScanProcessing)
                                      ? const CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        )
                                      : const Icon(
                                          Icons.refresh,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                ),
                              ),
                            ),
                          ] else ...[
                            // Capture hint when no images yet
                            if (_capturedImages.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  'Align paper in frame, then tap capture',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),

                            // Capture button row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Thumbnail of last captured image
                                GestureDetector(
                                  onTap: _capturedImages.isNotEmpty
                                      ? _showCapturedImages
                                      : null,
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white38),
                                    ),
                                    child: _capturedImages.isNotEmpty
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
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

                                // Capture button
                                GestureDetector(
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

                                // Done Scanning button
                                GestureDetector(
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
                                        borderRadius: BorderRadius.circular(12),
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
                                      'Tap ✓ when done scanning',
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select an assessment first')),
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
            try {
              await File(image.path).delete();
            } catch (_) {}
            return;
          }
        }
      }

      _capturedImages.add(image.path);
      _capturedHashes.add(hash);
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Capture failed — try again')));
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
                '${'Papers Captured'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: AppTheme.primaryYellow,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text('Possible Duplicate'),
          ],
        ),
        content: Text(
          'This looks similar to a paper already captured. Not sure? '
          'Answers will be double-checked after processing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), // Keep
            child: Text('Keep'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, false), // Skip
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryRed,
            ),
            child: Text('Skip'),
          ),
        ],
      ),
    );
    return result ?? false; // Default: keep (safe default)
  }

  /// Capture a single image and immediately re-grade it, replacing the
  /// existing ScanResult. Only used in re-scan mode.
  Future<void> _captureAndReGrade() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isCapturing ||
        _isReScanProcessing ||
        _reScanArgs == null) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final image = await _cameraController!.takePicture();
      setState(() {
        _isCapturing = false;
        _isReScanProcessing = true;
      });

      final existing = _reScanArgs!.existingResult;
      final assessment = _reScanArgs!.assessment;
      final grading = HybridGradingService();

      // Load weighted scale if configured
      final weightedScale = assessment.weightedScaleId != null
          ? context.read<WeightedGradeProvider>().getForExam(assessment.id)
          : null;

      // Grade the new image with the same student identity
      final newResult = await grading.gradePaper(
        imagePath: image.path,
        assessment: assessment,
        studentId: existing.studentId,
        studentName: existing.studentName,
        weightedScale: weightedScale,
      );

      // Delete old result from Hive
      await grading.deleteScanResult(existing.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newResult.status == ScanStatus.graded
                  ? ("${existing.studentName} re-graded — ${newResult.percentage.toStringAsFixed(0)}%")
                  : ('Re-scan failed — try again'),
            ),
          ),
        );

        // Pop back to review with the new result
        Navigator.pop(context, newResult);
      }
    } catch (e, st) {
      debugPrint('Re-scan error: $e\n$st');
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _isReScanProcessing = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error — try again')));
      }
    }
  }

  /// Navigate to BatchScanScreen for batch processing.
  void _finishBatch() {
    _batchStarted = true;
    Navigator.pushNamed(
      context,
      AppRoutes.batchScan,
      arguments: {'images': _capturedImages, 'assessment': _selectedAssessment},
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
    for (final timer in _cameraStartupTimers) {
      timer.cancel();
    }
    _cameraStartupTimers.clear();
    _cameraController?.dispose();
    // Clean up captured images if teacher backed out without scanning
    if (!_batchStarted && _capturedImages.isNotEmpty) {
      OcrService().cleanupImages(_capturedImages);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }
}

class _CameraUnavailableView extends StatelessWidget {
  final bool isStarting;
  final String? message;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final VoidCallback onManualEntry;

  const _CameraUnavailableView({
    required this.isStarting,
    required this.message,
    required this.onBack,
    required this.onRetry,
    required this.onManualEntry,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = isStarting ? 'Camera is starting' : 'Camera not ready';
    final helperText =
        message ?? 'Hold the phone steady while EthioGrade opens the camera.';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: 'Back',
              ),
            ),
            const Spacer(),
            Icon(
              isStarting ? Icons.camera_alt : Icons.no_photography_outlined,
              color: Colors.white,
              size: 56,
            ),
            const SizedBox(height: 18),
            Text(
              statusText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              helperText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
                height: 1.35,
              ),
            ),
            if (isStarting) ...[
              const SizedBox(height: 22),
              const Center(child: CircularProgressIndicator()),
            ],
            const Spacer(),
            FilledButton.icon(
              onPressed: isStarting ? null : onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try camera again'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onManualEntry,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              icon: const Icon(Icons.edit_note),
              label: const Text('Enter answer key manually'),
            ),
            TextButton(onPressed: onBack, child: const Text('Go back')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
