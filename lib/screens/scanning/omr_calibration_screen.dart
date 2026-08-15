import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/theme.dart';
import '../../models/assessment.dart';
import '../../services/omr_calibration_service.dart';
import '../../services/bubble_template.dart';

/// Screen for calibrating OMR bubble sheet templates.
///
/// Teachers scan a blank bubble sheet to verify that template coordinates
/// match actual bubble positions. The calibration is saved per-assessment
/// and used for subsequent scans.
class OmrCalibrationScreen extends StatefulWidget {
  final Assessment assessment;
  final BubbleTemplate? suggestedTemplate;

  const OmrCalibrationScreen({
    super.key,
    required this.assessment,
    this.suggestedTemplate,
  });

  @override
  State<OmrCalibrationScreen> createState() => _OmrCalibrationScreenState();
}

class _OmrCalibrationScreenState extends State<OmrCalibrationScreen> {
  final OmrCalibrationService _calibrationService = OmrCalibrationService();
  final ImagePicker _imagePicker = ImagePicker();

  CalibrationResult? _calibrationResult;
  BubbleTemplate? _selectedTemplate;
  String? _scannedImagePath;
  bool _isScanning = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedTemplate = widget.suggestedTemplate ??
        StandardTemplates.matchAssessment(
          questionCount: widget.assessment.questionCount,
          isTrueFalse: widget.assessment.mcqCount == 0 &&
              widget.assessment.trueFalseCount > 0,
        );
    _loadExistingCalibration();
  }

  Future<void> _loadExistingCalibration() async {
    final existing = await _calibrationService.loadCalibration(widget.assessment.id);
    if (existing != null && mounted) {
      setState(() {
        _selectedTemplate = existing;
      });
    }
  }

  Future<void> _scanBlankSheet() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 90,
      );

      if (image == null) return;

      setState(() {
        _isScanning = true;
        _scannedImagePath = image.path;
        _calibrationResult = null;
      });

      final result = await _calibrationService.detectBubbles(
        imagePath: image.path,
        template: _selectedTemplate!,
      );

      if (mounted) {
        setState(() {
          _calibrationResult = result;
          _isScanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _saveCalibration() async {
    if (_calibrationResult == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await _calibrationService.saveCalibration(
        assessmentId: widget.assessment.id,
        template: _selectedTemplate!,
        params: const CalibrationParams(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Calibration saved!'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _selectTemplate(BubbleTemplate template) {
    setState(() {
      _selectedTemplate = template;
      _calibrationResult = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calibrate Bubble Sheet'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_calibrationResult != null)
            TextButton(
              onPressed: _isSaving ? null : _saveCalibration,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Instructions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppTheme.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'How Calibration Works',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '1. Print a blank bubble sheet from the app\n'
                      '2. Scan it with this screen\n'
                      '3. Check if bubbles align correctly\n'
                      '4. Save calibration for accurate scanning',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Template selection
            Text(
              'Select Template',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: StandardTemplates.all.map((template) {
                final isSelected = _selectedTemplate?.name == template.name;
                return ChoiceChip(
                  label: Text(template.name),
                  selected: isSelected,
                  onSelected: (_) => _selectTemplate(template),
                  selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.primary : AppTheme.onSurfaceLight,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Scan button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _scanBlankSheet,
                icon: _isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt),
                label: Text(_isScanning ? 'Scanning...' : 'Scan Blank Sheet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(AppSpacing.md),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Preview image
            if (_scannedImagePath != null) ...[
              Text(
                'Scanned Sheet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(_scannedImagePath!),
                  height: 300,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Calibration result
            if (_calibrationResult != null) ...[
              _buildResultCard(),
              const SizedBox(height: AppSpacing.lg),
              _buildBubbleGrid(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final result = _calibrationResult!;
    final statusColor = result.isGood
        ? AppTheme.success
        : result.isAcceptable
            ? AppTheme.warning
            : AppTheme.error;
    final statusText = result.isGood
        ? 'Excellent alignment!'
        : result.isAcceptable
            ? 'Acceptable alignment'
            : 'Poor alignment - try adjusting';
    final statusIcon = result.isGood
        ? Icons.check_circle
        : result.isAcceptable
            ? Icons.warning
            : Icons.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 24),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  statusText,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _buildStatRow('Template', result.templateName),
            _buildStatRow('Bubbles Detected', '${result.detectedBubbles}/${result.expectedBubbles}'),
            _buildStatRow('Alignment Score', result.alignmentScore.toStringAsFixed(1)),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${result.errors.length} bubbles have offset > 5px',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.warning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubbleGrid() {
    final result = _calibrationResult!;
    final template = _selectedTemplate!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bubble Grid Preview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Green = detected, Red = expected but not found',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: template.questionCount,
                itemBuilder: (context, qi) {
                  return Column(
                    children: List.generate(template.optionCount, (oi) {
                      final hasError = result.errors.any(
                        (e) => e.questionNumber == qi + 1 && e.option == template.options[oi],
                      );

                      return Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasError
                              ? AppTheme.error.withValues(alpha: 0.3)
                              : AppTheme.success.withValues(alpha: 0.3),
                          border: Border.all(
                            color: hasError ? AppTheme.error : AppTheme.success,
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            template.options[oi],
                            style: TextStyle(
                              fontSize: 8,
                              color: hasError ? AppTheme.error : AppTheme.success,
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}