import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../../config/theme.dart';
import '../../config/responsive.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../models/student.dart';
import '../../services/assessment_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/ocr_service.dart';
import '../../services/student_provider.dart';
import '../assessment/exam_day_create_screen.dart';
import '../../widgets/paper_guide_overlay.dart';
import 'camera_unavailable_view.dart';
import 'camera_assistant_panel.dart';
import 'camera_processor.dart';
import 'camera_controls.dart';
import 'assessment_selector.dart';

/// Arguments for re-scan mode: replaces an existing ScanResult with a fresh scan.
class ReScanArguments {
  final ScanResult existingResult;
  final Assessment assessment;

  const ReScanArguments({
    required this.existingResult,
    required this.assessment,
  });
}

enum _CameraScanMode { batch, masterKey }

/// Camera screen with continuous batch capture flow.
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
  int _flashModeIndex = 0; // 0 = off, 1 = auto, 2 = torch
  bool _isFrontCamera = false;
  bool _isCameraStarting = true;
  String? _cameraError;
  final List<Timer> _cameraStartupTimers = [];
  final List<String> _capturedImages = [];
  final List<int?> _capturedHashes = [];
  List<int?> _existingHashes = [];
  bool _existingHashesLoaded = false;

  bool _batchStarted = false;
  Assessment? _selectedAssessment;
  PaperGuideState _guideState = PaperGuideState.idle;
  _CameraScanMode _scanMode = _CameraScanMode.batch;

  ReScanArguments? _reScanArgs;
  bool _isReScanProcessing = false;

  String? _classId;
  final List<ScanResult> _autoGradedResults = [];
  String _lastCaptureTitle = '';
  String _lastCaptureDetail = '';
  String? _captureErrorMessage;
  VoidCallback? _captureErrorOnRetry;
  Assessment? _captureErrorAssessment;
  int? _countdown;
  String? _feedbackText;
  bool _isDisposed = false;

  late final CameraProcessor _processor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _processor = CameraProcessor(
      callbacks: CameraProcessorCallbacks(
        onCapturingChanged: (capturing) {
          if (mounted && !_isDisposed) setState(() => _isCapturing = capturing);
        },
        onCaptureFeedbackChanged: (title, detail) {
          if (mounted && !_isDisposed) {
            setState(() {
              _lastCaptureTitle = title;
              _lastCaptureDetail = detail;
              _captureErrorMessage = null;
              _captureErrorOnRetry = null;
              _captureErrorAssessment = null;
            });
          }
        },
        onGuideStateChanged: (state) {
          if (mounted && !_isDisposed) setState(() => _guideState = state);
        },
        onBatchChanged: (images, hashes) {
          if (mounted && !_isDisposed) setState(() {});
        },
        onAutoGradedResultsChanged: (results) {
          if (mounted && !_isDisposed) {
            setState(() {
              _autoGradedResults
                ..clear()
                ..addAll(results);
            });
          }
        },
        onBatchStartedChanged: (started) {
          if (mounted && !_isDisposed) setState(() => _batchStarted = started);
        },
        onCaptureError: (message, onRetry, assessment) {
          if (mounted && !_isDisposed) {
            setState(() {
              _captureErrorMessage = message;
              _captureErrorOnRetry = onRetry;
              _captureErrorAssessment = assessment;
              _lastCaptureTitle = '';
              _lastCaptureDetail = '';
            });
          }
        },
        onShowDuplicateDialog: () => showDuplicateDialog(context),
        onAutoCaptureTriggered: _captureImage,
        onFeedbackTextChanged: (text) {
          if (!_isDisposed && mounted) setState(() => _feedbackText = text);
        },
        onCountdownChanged: (value) {
          if (!_isDisposed && mounted) setState(() => _countdown = value);
        },
      ),
    );
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

    // Prefer camera matching the current lens direction — back for paper scanning.
    final targetLens = _isFrontCamera
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final selectedCamera = _cameras.where(
      (c) => c.lensDirection == targetLens,
    ).isEmpty
        ? _cameras.first
        : _cameras.firstWhere((c) => c.lensDirection == targetLens);
    debugPrint(
      'CAMERA: using ${selectedCamera.lensDirection} (${selectedCamera.name})',
    );

    _cameraController = CameraController(
      selectedCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
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
        // A fresh controller starts with flash off — sync the UI to reality.
        _flashModeIndex = 0;
        _isFlashOn = false;
      });
      // Start the frame-observation stream so the guide overlay gives live
      // detection feedback (bracket colors, countdown, low-light hints).
      _processor.startFrameObservation(_cameraController);
      debugPrint('CAMERA: frame observation started');
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
    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    if (_reScanArgs == null && routeArgs is ReScanArguments) {
      _reScanArgs = routeArgs;
      _selectedAssessment = routeArgs.assessment;
    }
    if (routeArgs is Map) {
      final assessment = routeArgs['assessment'];
      if (assessment is Assessment) {
        _selectedAssessment ??= assessment;
      }
      if (routeArgs['scanMode'] == 'masterKey') {
        _scanMode = _CameraScanMode.masterKey;
      }
    }
    _selectedAssessment ??= routeArgs is Assessment ? routeArgs : null;

    if (_selectedAssessment != null && !_existingHashesLoaded) {
      _loadExistingHashes(_selectedAssessment!);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: !_isInitialized
            ? CameraUnavailableView(
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
                  Positioned.fill(child: CameraPreview(_cameraController!)),
                  Positioned.fill(
                    child: PaperGuideOverlay(
                      state: _guideState,
                      countdown: _countdown,
                      feedbackText: _feedbackText,
                      onEnableFlash: _turnOnFlash,
                    ),
                  ),
                  _buildTopBar(),
                  // Active assessment banner
                  if (_selectedAssessment != null)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 56,
                      left: ResponsiveLayout.horizontalPadding(context),
                      right: ResponsiveLayout.horizontalPadding(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.assignment,
                              color: Colors.white70,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Scanning: ${_selectedAssessment!.title} (${_selectedAssessment!.questionCount} questions)',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Result overlay after capture
                  if (_lastCaptureTitle.isNotEmpty)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 100,
                      left: 24,
                      right: 24,
                      child: AnimatedOpacity(
                        opacity: _lastCaptureTitle.isNotEmpty ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: context.primaryGreen.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _lastCaptureTitle.contains('%')
                                    ? Icons.check_circle
                                    : Icons.info,
                                color: context.primaryGreen,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _lastCaptureTitle,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (_lastCaptureDetail.isNotEmpty)
                                      Text(
                                        _lastCaptureDetail,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
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

                  // Progress counter
                  if (_capturedImages.isNotEmpty)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 16,
                      right: ResponsiveLayout.horizontalPadding(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: context.primaryGreen,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${_capturedImages.length} scanned',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  if (_selectedAssessment == null && _reScanArgs == null)
                    AssessmentSelector(
                      assessments: context
                          .watch<AssessmentProvider>()
                          .assessments,
                      selectedAssessment: _selectedAssessment,
                      onChanged: (a) => setState(() {
                        _selectedAssessment = a;
                        if (a != null) _loadExistingHashes(a);
                      }),
                    ),
                  if (_reScanArgs != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _buildReScanControls(),
                    )
                  else
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: CameraControls(
                        isCapturing: _isCapturing,
                        capturedImages: _capturedImages,
                        lastCaptureTitle: _lastCaptureTitle,
                        lastCaptureDetail: _lastCaptureDetail,
                        isMasterKeyMode: _scanMode == _CameraScanMode.masterKey,
                        isAutoCapture: _processor.autoCaptureEnabled,
                        onCapture: _captureImage,
                        onFinishBatch: _finishBatch,
                        onViewCaptured: () => showCapturedImagesSheet(
                          context: context,
                          capturedImages: _capturedImages,
                        ),
                        onCaptureMasterKey: _captureMasterKey,
                        onToggleAutoCapture: () => setState(
                          () => _processor.toggleAutoCapture(_cameraController),
                        ),
                        onToggleFlash: _toggleFlash,
                        isFlashTorchOn: _isFlashOn,
                        canFlipCamera: _cameras.length >= 2,
                        onFlipCamera: _flipCamera,
                        onPickUploaded: _pickUploadedPapers,
                        captureErrorMessage: _captureErrorMessage,
                        captureErrorOnRetry: _captureErrorOnRetry,
                        captureErrorAssessment: _captureErrorAssessment,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveLayout.horizontalPadding(context),
            vertical: 8,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _titleText,
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
                        _subtitleText,
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
                  _flashModeIndex == 2
                      ? Icons.flash_on
                      : _flashModeIndex == 1
                          ? Icons.flash_auto
                          : Icons.flash_off,
                  color: Colors.white,
                ),
                tooltip: 'Flash',
                onPressed: _toggleFlash,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReScanControls() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CameraAssistantPanel(
            title: 'Re-Scan \u2014 ${_reScanArgs!.existingResult.studentName}',
            detail: _isReScanProcessing ? 'Grading...' : 'Tap to re-scan',
            capturedCount: 0,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: (_isCapturing || _isReScanProcessing)
                ? null
                : _captureAndReGrade,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (_isCapturing || _isReScanProcessing)
                      ? Colors.grey
                      : context.primaryGreen,
                ),
                child: (_isCapturing || _isReScanProcessing)
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      )
                    : const Icon(Icons.camera, color: Colors.white, size: 32),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _titleText {
    if (_reScanArgs != null) {
      return 'Re-Scan \u2014 ${_reScanArgs!.existingResult.studentName}';
    }
    if (_scanMode == _CameraScanMode.masterKey) {
      return 'Scan Answer Sheet';
    }
    return 'Scan Student Papers';
  }

  String get _subtitleText {
    if (_reScanArgs != null) {
      return 'Tap to re-scan ${_reScanArgs!.existingResult.studentName}';
    }
    if (_scanMode == _CameraScanMode.masterKey) {
      return 'Point camera at answer key';
    }
    if (_processor.autoCaptureEnabled) {
      return 'Auto-capture: hold steady';
    }
    return '${_capturedImages.length} papers captured';
  }

  String _effectiveClassId() {
    if (_classId != null) return _classId!;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['classId'] is String) {
      return args['classId'] as String;
    }
    return '';
  }

  List<Student> _classStudentsFor(String classId) {
    if (classId.isEmpty) return [];
    return context.read<StudentProvider>().studentsByClassId(classId);
  }

  // ── Capture methods ──

  Future<void> _captureImage() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    if (_selectedAssessment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an assessment first')),
      );
      return;
    }

    await _processor.captureImage(
      controller: _cameraController,
      assessment: _selectedAssessment,
      existingHashes: _existingHashes,
      capturedImages: _capturedImages,
      capturedHashes: _capturedHashes,
    );
  }

  Future<void> _captureMasterKey() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    if (_selectedAssessment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an assessment first')),
      );
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final image = await _cameraController!.takePicture();
      _batchStarted = true;
      _processor.stopFrameObservation(_cameraController);

      final cid = _effectiveClassId();
      final students = _classStudentsFor(cid);

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.batchScan,
        arguments: {
          'images': [image.path],
          'assessment': _selectedAssessment,
          'masterOnly': true,
          if (cid.isNotEmpty) 'classId': cid,
          if (students.isNotEmpty) 'classStudents': students,
        },
      );
    } catch (e) {
      debugPrint('Master key capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Master scan failed \u2014 try again')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _captureAndReGrade() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isCapturing ||
        _isReScanProcessing ||
        _reScanArgs == null) {
      return;
    }

    setState(() {
      _isCapturing = true;
      _isReScanProcessing = false;
    });

    final newResult = await _processor.captureAndReGrade(
      controller: _cameraController,
      existingResult: _reScanArgs!.existingResult,
      assessment: _reScanArgs!.assessment,
      context: context,
    );

    if (mounted) {
      setState(() {
        _isCapturing = false;
        _isReScanProcessing = false;
      });

      if (newResult != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newResult.status == ScanStatus.graded
                  ? '${_reScanArgs!.existingResult.studentName} re-graded \u2014 ${newResult.percentage.toStringAsFixed(0)}%'
                  : 'Re-scan failed \u2014 try again',
            ),
          ),
        );
        Navigator.pop(context, newResult);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Error \u2014 try again')));
      }
    }
  }

  void _finishBatch() {
    _batchStarted = true;
    _processor.stopFrameObservation(_cameraController);

    final cid = _effectiveClassId();
    Navigator.pushNamed(
      context,
      AppRoutes.batchScan,
      arguments: {
        'images': _capturedImages,
        'assessment': _selectedAssessment,
        if (cid.isNotEmpty) 'classId': cid,
        if (_autoGradedResults.isNotEmpty)
          'draftCompletedResults': _autoGradedResults,
      },
    );
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;
    final modes = [FlashMode.off, FlashMode.auto, FlashMode.torch];
    setState(() {
      _flashModeIndex = (_flashModeIndex + 1) % modes.length;
      _isFlashOn = modes[_flashModeIndex] == FlashMode.torch;
    });
    await _cameraController!.setFlashMode(modes[_flashModeIndex]);
  }

  Future<void> _turnOnFlash() async {
    if (_cameraController == null) return;
    setState(() {
      _flashModeIndex = 2;
      _isFlashOn = true;
    });
    await _cameraController!.setFlashMode(FlashMode.torch);
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;

    _processor.stopFrameObservation(_cameraController);
    _processor.cancelCountdown();
    final oldController = _cameraController;
    _cameraController = null;

    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _isInitialized = false;
      _isCameraStarting = true;
    });

    // Dispose the old controller after detaching it so the new one can grab
    // the hardware camera without conflict.
    await oldController?.dispose();
    await _initializeCamera();
  }

  Future<void> _pickUploadedPapers() async {
    if (_selectedAssessment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an assessment first')),
      );
      return;
    }
    _processor.stopFrameObservation(_cameraController);
    await _processor.pickUploadedPapers(
      assessment: _selectedAssessment,
      capturedImages: _capturedImages,
      capturedHashes: _capturedHashes,
    );
    if (mounted) _processor.startFrameObservation(_cameraController);
  }

  Future<void> _loadExistingHashes(Assessment assessment) async {
    if (_existingHashesLoaded) return;
    _existingHashesLoaded = true;
    try {
      final grading = HybridGradingService();
      final existingScans = await grading.loadScanResults(
        assessment.id,
        throwOnError: true,
      );
      _existingHashes = existingScans.map((s) => s.imageHash).toList();
    } catch (_) {
      _existingHashes = [];
      _existingHashesLoaded = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Couldn\'t load scanned records — duplicate detection disabled. '
              'Retry when scanning.',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _processor.cancelCountdown();
    _processor.stopFrameObservation(_cameraController);
    for (final timer in _cameraStartupTimers) {
      timer.cancel();
    }
    _cameraStartupTimers.clear();
    _cameraController?.dispose();
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
      // Cancel countdown before disposing camera
      _processor.cancelCountdown();
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }
}
