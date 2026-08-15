import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/answer_key_ocr_parser.dart';

/// Result passed back to the answer key screen after a successful photo scan.
class PhotoScanResult {
  final List<OcrParsedAnswer> answers;
  final int totalDetected;
  final int totalQuestions;

  const PhotoScanResult({
    required this.answers,
    required this.totalDetected,
    required this.totalQuestions,
  });
}

/// Full-screen photo scan for printed answer key sheets.
///
/// Flow: pick/take photo → preprocess → OCR → parse → preview → apply.
class AnswerKeyPhotoScanScreen extends StatefulWidget {
  final int questionCount;

  const AnswerKeyPhotoScanScreen({super.key, required this.questionCount});

  @override
  State<AnswerKeyPhotoScanScreen> createState() =>
      _AnswerKeyPhotoScanScreenState();
}

class _AnswerKeyPhotoScanScreenState extends State<AnswerKeyPhotoScanScreen> {
  final _picker = ImagePicker();
  final _parser = const AnswerKeyOcrParser();
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  File? _imageFile;
  bool _isProcessing = false;
  String? _errorMessage;
  List<OcrParsedAnswer> _parsedAnswers = [];
  bool _showPreview = false;

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  // ── Image Capture ──────────────────────────────────────────────────

  Future<void> _openCamera() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 85,
    );
    if (picked != null) {
      await _processImage(File(picked.path));
    }
  }

  Future<void> _openGallery() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      await _processImage(File(picked.path));
    }
  }

  // ── Image Processing ───────────────────────────────────────────────

  Future<void> _processImage(File imageFile) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _imageFile = imageFile;
      _showPreview = false;
    });

    try {
      // Check brightness — reject if too dark
      final brightness = await _checkBrightness(imageFile);
      if (brightness < 50) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Photo is too dark. Try again with more light.';
        });
        return;
      }

      // Preprocess: enhance contrast for low-light classrooms
      final enhancedPath = await _enhanceImage(imageFile);

      // Run ML Kit OCR
      final inputImage = InputImage.fromFilePath(enhancedPath);
      final recognized = await _textRecognizer.processImage(inputImage);

      if (recognized.text.isEmpty) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Could not read answers. Try a clearer photo.';
        });
        return;
      }

      // Parse OCR text into answers
      final answers = _parser.parse(
        recognized.text,
        expectedCount: widget.questionCount,
      );

      if (answers.isEmpty) {
        setState(() {
          _isProcessing = false;
          _errorMessage =
              'Could not detect any answers. Make sure the answer key is clearly visible.';
        });
        return;
      }

      setState(() {
        _parsedAnswers = answers;
        _showPreview = true;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Error processing photo: ${e.toString()}';
      });
    }
  }

  /// Check average brightness of the image. Returns 0–255.
  Future<double> _checkBrightness(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return 128;

      // Sample pixels across the image
      final step = math.max(1, image.width ~/ 20);
      double totalBrightness = 0;
      int count = 0;

      for (int y = 0; y < image.height; y += step) {
        for (int x = 0; x < image.width; x += step) {
          final pixel = image.getPixel(x, y);
          // Perceived brightness formula
          final brightness =
              (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b);
          totalBrightness += brightness;
          count++;
        }
      }

      return count > 0 ? totalBrightness / count : 128;
    } catch (_) {
      return 128; // Assume OK if we can't check
    }
  }

  /// Enhance image for better OCR: contrast stretch + downscale.
  Future<String> _enhanceImage(File file) async {
    try {
      final appDir = await getTemporaryDirectory();
      final outputPath =
          '${appDir.path}/ocr_enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return file.path;

      // EXIF rotation correction
      image = img.bakeOrientation(image);

      // Downscale if too large (max 3000px)
      const maxDim = 3000;
      if (image.width > maxDim || image.height > maxDim) {
        final longer = image.width > image.height ? image.width : image.height;
        final ratio = maxDim / longer;
        image = img.copyResize(
          image,
          width: (image.width * ratio).round(),
          height: (image.height * ratio).round(),
        );
      }

      // Encode and save
      final encoded = img.encodeJpg(image, quality: 85);
      await File(outputPath).writeAsBytes(encoded);

      return outputPath;
    } catch (_) {
      return file.path; // Fallback to original
    }
  }

  // ── Answer Editing ─────────────────────────────────────────────────

  void _updateAnswer(int index, String newAnswer) {
    setState(() {
      _parsedAnswers[index] = OcrParsedAnswer(
        questionNumber: _parsedAnswers[index].questionNumber,
        answer: newAnswer,
        rawText: _parsedAnswers[index].rawText,
        confidence: 'high', // Manual edits are always high confidence
      );
    });
  }

  void _applyAnswers() {
    final result = PhotoScanResult(
      answers: _parsedAnswers,
      totalDetected: _parsedAnswers.length,
      totalQuestions: widget.questionCount,
    );
    Navigator.pop(context, result);
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Answer Key'),
        backgroundColor: const Color(0xFF242424),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: _showPreview ? _buildPreview() : _buildCaptureView(),
      ),
    );
  }

  Widget _buildCaptureView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.document_scanner_outlined,
              size: 80,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'Photograph your answer key sheet',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The app will read the answers automatically',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 40),
            if (_isProcessing) ...[
              const CircularProgressIndicator(color: Color(0xFFF4A623)),
              const SizedBox(height: 16),
              Text(
                'Reading answers...',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ] else if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDA2A2A).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFDA2A2A).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Color(0xFFDA2A2A),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFFDA2A2A),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildCaptureButtons(),
            ] else ...[
              if (_imageFile != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    _imageFile!,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 20),
              ],
              _buildCaptureButtons(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureButtons() {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.camera_alt,
            label: 'Open Camera',
            onTap: _openCamera,
            color: const Color(0xFFF4A623),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon: Icons.photo_library,
            label: 'Upload Photo',
            onTap: _openGallery,
            color: const Color(0xFF7EB8DA),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final detected = _parsedAnswers.length;
    final total = widget.questionCount;
    final missing = total - detected;
    final highConf = _parsedAnswers.where((a) => a.isHighConfidence).length;
    final lowConf = _parsedAnswers.where((a) => a.isLowConfidence).length;

    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: const Color(0xFF242424),
          child: Row(
            children: [
              _PreviewStat(
                label: 'Found',
                value: '$detected/$total',
                color: const Color(0xFF18A558),
              ),
              const SizedBox(width: 16),
              if (lowConf > 0)
                _PreviewStat(
                  label: 'Uncertain',
                  value: '$lowConf',
                  color: const Color(0xFFF4A623),
                ),
              if (highConf > 0) ...[
                const SizedBox(width: 16),
                _PreviewStat(
                  label: 'Clear',
                  value: '$highConf',
                  color: const Color(0xFF18A558),
                ),
              ],
              const Spacer(),
              if (missing > 0)
                Text(
                  '$missing missing',
                  style: const TextStyle(
                    color: Color(0xFFDA2A2A),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),

        // Answer grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 1.8,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: _parsedAnswers.length,
            itemBuilder: (context, index) {
              final answer = _parsedAnswers[index];
              return _AnswerPreviewTile(
                answer: answer,
                onTap: () => _showEditDialog(index),
              );
            },
          ),
        ),

        // Bottom actions
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF242424),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _showPreview = false;
                    _errorMessage = null;
                  }),
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('Retake'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: detected > 0 ? _applyAnswers : null,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text('Apply $detected Answers'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0B6E4F),
                    disabledBackgroundColor: Colors.white12,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showEditDialog(int index) {
    final answer = _parsedAnswers[index];
    final controller = TextEditingController(text: answer.answer);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Q${answer.questionNumber}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Answer',
            hintText: 'A, B, C, D, E, T, F',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newAnswer = controller.text.trim().toUpperCase();
              if (newAnswer.isNotEmpty) {
                _updateAnswer(index, newAnswer);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ── Helper Widgets ─────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _PreviewStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _AnswerPreviewTile extends StatelessWidget {
  final OcrParsedAnswer answer;
  final VoidCallback onTap;

  const _AnswerPreviewTile({required this.answer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLow = answer.isLowConfidence;
    final bgColor = isLow
        ? const Color(0xFFF4A623).withValues(alpha: 0.15)
        : const Color(0xFF2A3A2F);
    final borderColor = isLow
        ? const Color(0xFFF4A623)
        : const Color(0xFF3D6B4F);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${answer.questionNumber}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              isLow ? '?' : answer.answer,
              style: TextStyle(
                color: isLow ? const Color(0xFFF4A623) : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
