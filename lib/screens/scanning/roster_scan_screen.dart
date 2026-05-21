import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../../config/theme.dart';
import '../../services/ocr_service.dart';
import '../../services/roster_parser.dart';
import '../classes/roster_preview_screen.dart';

/// Dedicated camera for scanning a paper roster.
/// One capture → OCR → parse → preview → save.
///
/// Simpler than the assessment camera: no batch, no assessment selector,
/// no duplicate detection. Just: point, shoot, review names.
class RosterScanScreen extends StatefulWidget {
  final String classId;

  const RosterScanScreen({super.key, required this.classId});

  @override
  State<RosterScanScreen> createState() => _RosterScanScreenState();
}

class _RosterScanScreenState extends State<RosterScanScreen> {
  CameraController? _controller;
  bool _initialized = false;
  bool _processing = false;
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
      // Use rear camera
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first);
      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false);
      await _controller!.initialize();
      setState(() => _initialized = true);
    } catch (e) {
      setState(() => _error = 'Camera error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Scan Roster',
          style: const TextStyle(color: Colors.white))),
      body: _error != null
          ? _ErrorView(message: _error!)
          : !_initialized
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              children: [
                // Camera preview
                Positioned.fill(child: CameraPreview(_controller!)),

                // Guide overlay
                Positioned.fill(
                  child: CustomPaint(painter: _RosterGuidePainter())),

                // Instructions
                Positioned(
                  top: 16,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      'Align the student roster in the frame',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.center))),

                // Capture button
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _processing ? null : _capture,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _processing
                              ? Colors.grey
                              : AppTheme.primaryGreen,
                          border: Border.all(color: Colors.white, width: 3)),
                        child: _processing
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2))
                            : const Icon(
                                Icons.document_scanner,
                                color: Colors.white,
                                size: 32))))),
              ]));
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() => _processing = true);

    try {
      // 1. Capture
      final image = await _controller!.takePicture();

      // 2. OCR
      final ocrService = OcrService();
      final enhancedPath = await ocrService.enhanceImage(image.path);
      final ocrResult = await ocrService.extractTextRegions(enhancedPath);
      final rawText = ocrResult.regions.map((r) => r.text).join('\n');

      // 3. Parse
      const parser = RosterParser();
      final parsed = parser.parse(rawText);

      // 4. Cleanup temp files
      try {
        await File(enhancedPath).delete();
      } catch (_) {}

      if (!mounted) return;

      if (parsed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No names found — try again with better lighting'),
            backgroundColor: AppTheme.primaryYellow));
        setState(() => _processing = false);
        return;
      }

      // 5. Navigate to preview
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RosterPreviewScreen(
            parsedStudents: parsed,
            classId: widget.classId)));
    } catch (e) {
      debugPrint('Roster scan error: $e');
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.primaryRed));
      }
    }
  }
}

class _RosterGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primaryGreen.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Draw a rectangle guide with padding
    final padding = 24.0;
    final rect = Rect.fromLTWH(
      padding,
      size.height * 0.15,
      size.width - padding * 2,
      size.height * 0.6);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      paint);

    // Corner accents
    final cornerPaint = Paint()
      ..color = AppTheme.primaryGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const cornerLen = 24.0;
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];

    for (final corner in corners) {
      final dx = corner == rect.topLeft || corner == rect.bottomLeft
          ? 1.0
          : -1.0;
      final dy = corner == rect.topLeft || corner == rect.topRight ? 1.0 : -1.0;
      canvas.drawLine(
        corner,
        Offset(corner.dx + cornerLen * dx, corner.dy),
        cornerPaint);
      canvas.drawLine(
        corner,
        Offset(corner.dx, corner.dy + cornerLen * dy),
        cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_outlined, size: 64, color: Colors.white38),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Go Back')),
          ])));
  }
}
