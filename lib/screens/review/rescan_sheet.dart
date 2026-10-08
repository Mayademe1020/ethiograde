import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../../config/theme.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../services/hybrid_grading_service.dart';

/// Shows an inline camera bottom sheet for re-scanning a single paper.
///
/// Returns a new [ScanResult] on success, null on cancel.
Future<ScanResult?> showReScanSheet(
  BuildContext context, {
  required Assessment assessment,
  required ScanResult existingResult,
}) async {
  return showModalBottomSheet<ScanResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.black,
    builder: (_) => _ReScanSheet(
      assessment: assessment,
      existingResult: existingResult,
    ),
  );
}

class _ReScanSheet extends StatefulWidget {
  final Assessment assessment;
  final ScanResult existingResult;

  const _ReScanSheet({
    required this.assessment,
    required this.existingResult,
  });

  @override
  State<_ReScanSheet> createState() => _ReScanSheetState();
}

class _ReScanSheetState extends State<_ReScanSheet> {
  CameraController? _controller;
  bool _isCapturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera available');
        return;
      }
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (mounted) setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }
    setState(() => _isCapturing = true);

    try {
      final image = await _controller!.takePicture();

      final grading = HybridGradingService();
      final result = await grading.gradePaper(
        imagePath: image.path,
        assessment: widget.assessment,
        studentId: widget.existingResult.studentId,
        studentName: widget.existingResult.studentName,
      );

      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() => _isCapturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Text(
                    'Re-scan: ${widget.existingResult.studentName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  : _controller == null
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.center,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _controller!.value.previewSize!.height,
                                height: _controller!.value.previewSize!.width,
                                child: CameraPreview(_controller!),
                              ),
                            ),
                          ),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _capture,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: _isCapturing ? Colors.grey : context.primaryGreen,
                      ),
                      child: _isCapturing
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 32,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
