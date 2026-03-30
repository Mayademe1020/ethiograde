import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../services/locale_provider.dart';
import '../../services/assessment_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../widgets/paper_guide_overlay.dart';

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
  bool _isProcessing = false;
  bool _isFlashOn = false;
  int _scanCount = 0;
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
    // Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission required')),
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

      // Set flash mode and exposure for better classroom scanning
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

    // Auto-select assessment if coming from a specific one
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
                  child: PaperGuideOverlay(state: _guideState, isAmharic: isAm),
                ),

                // Top bar
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
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white),
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
                                  '$_scanCount ${isAm ? 'ተሰልፏል' : 'scanned'}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Flash toggle
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
                                .where((a) =>
                                    a.status == AssessmentStatus.active)
                                .map((a) => DropdownMenuItem(
                                      value: a,
                                      child: Text(
                                        '${a.title} (${a.subject})',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ))
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
                          // Processing indicator
                          if (_isProcessing)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Processing...',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),

                          // Capture button row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Gallery of captured images
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
                                onTap: _isProcessing ? null : _captureImage,
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
                                      color: _isProcessing
                                          ? Colors.grey
                                          : AppTheme.primaryGreen,
                                    ),
                                    child: _isProcessing
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

                              // Done / Batch review
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
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _captureImage() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isProcessing) {
      return;
    }

    if (_selectedAssessment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<LocaleProvider>().isAmharic
                ? 'ፈተና ይምረጡ'
                : 'Please select an assessment first',
          ),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final image = await _cameraController!.takePicture();
      _capturedImages.add(image.path);
      _scanCount++;

      // Process image (auto-enhance + OCR)
      final grading = HybridGradingService();

      final result = await grading.gradePaper(
        imagePath: image.path,
        assessment: _selectedAssessment!,
        studentId: 'student_$_scanCount',
        studentName: 'Student $_scanCount',
      );

      if (mounted) {
        // Show quick result
        _showQuickResult(result);
      }
    } catch (e) {
      debugPrint('Capture error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showQuickResult(ScanResult result) {
    final isAm = context.read<LocaleProvider>().isAmharic;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: AppTheme.primaryGreen,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${isAm ? 'ውጤት' : 'Result'}: ${result.totalScore}/${result.maxScore}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${result.percentage.toStringAsFixed(1)}% — Grade: ${result.grade}',
                        style: TextStyle(color: AppTheme.lightText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      Navigator.pushNamed(
                        context,
                        AppRoutes.sideBySide,
                        arguments: result,
                      );
                    },
                    icon: const Icon(Icons.visibility),
                    label: Text(isAm ? 'ዝርዝር' : 'Review'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(c),
                    icon: const Icon(Icons.camera_alt),
                    label: Text(isAm ? 'ቀጣይ' : 'Next Paper'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
                '${_capturedImages.length} Papers Scanned',
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
