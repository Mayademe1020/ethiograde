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
  Assessment? _selectedAssessment;
  PaperGuideState _guideState = PaperGuideState.idle;

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
                                      color: Colors.white60,
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
      _capturedImages.add(image.path);
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

  /// Navigate to BatchScanScreen for batch processing.
  void _finishBatch() {
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
