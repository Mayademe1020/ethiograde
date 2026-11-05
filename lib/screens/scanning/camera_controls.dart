import 'dart:io';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/responsive.dart';
import 'camera_assistant_panel.dart';

/// Bottom controls for the camera screen: capture button, thumbnail, done button.
class CameraControls extends StatelessWidget {
  const CameraControls({
    super.key,
    required this.isCapturing,
    required this.capturedImages,
    required this.lastCaptureTitle,
    required this.lastCaptureDetail,
    required this.isMasterKeyMode,
    required this.isAutoCapture,
    required this.onCapture,
    required this.onFinishBatch,
    required this.onViewCaptured,
    required this.onCaptureMasterKey,
    required this.onToggleAutoCapture,
    required this.onToggleFlash,
    required this.isFlashTorchOn,
    required this.canFlipCamera,
    required this.onFlipCamera,
    required this.onPickUploaded,
    this.captureErrorMessage,
    this.captureErrorOnRetry,
    this.captureErrorAssessment,
  });

  final bool isCapturing;
  final List<String> capturedImages;
  final String lastCaptureTitle;
  final String lastCaptureDetail;
  final bool isMasterKeyMode;
  final bool isAutoCapture;
  final VoidCallback onCapture;
  final VoidCallback onFinishBatch;
  final VoidCallback onViewCaptured;
  final VoidCallback onCaptureMasterKey;
  final VoidCallback onToggleAutoCapture;
  final VoidCallback onToggleFlash;
  final bool isFlashTorchOn;
  final bool canFlipCamera;
  final VoidCallback onFlipCamera;
  final VoidCallback onPickUploaded;
  final String? captureErrorMessage;
  final VoidCallback? captureErrorOnRetry;
  final dynamic captureErrorAssessment;

  @override
  Widget build(BuildContext context) {
    if (isMasterKeyMode) {
      return _buildMasterKeyControls(context);
    }
    if (isAutoCapture) {
      return _buildAutoCaptureControls(context);
    }
    return _buildBatchControls(context);
  }

  Widget _buildAutoCaptureControls(BuildContext context) {
    final hasError = captureErrorMessage != null;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveLayout.horizontalPadding(context),
        vertical: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScanModeControl(
            autoEnabled: isAutoCapture,
            onManualTap: onToggleAutoCapture,
            onAutoTap: onToggleAutoCapture,
          ),
          const SizedBox(height: 10),
          if (hasError) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          captureErrorMessage!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: captureErrorOnRetry,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: captureErrorAssessment != null
                              ? () {
                                  Navigator.pushNamed(
                                    context,
                                    '/quick_enter',
                                    arguments: captureErrorAssessment,
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Enter Score'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            // Auto-capture status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.primaryGreen,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isCapturing ? 'Processing...' : 'Place paper in frame',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Controls: import, thumbnail, capture, flash, flip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _LabeledControlButton(
                icon: Icons.add_photo_alternate_outlined,
                label: 'Import',
                onTap: onPickUploaded,
              ),
              _ThumbnailButton(
                capturedImages: capturedImages,
                onViewCaptured: onViewCaptured,
              ),
              _CaptureButton(
                isCapturing: isCapturing,
                onCapture: onCapture,
                isAuto: true,
              ),
              _LabeledControlButton(
                icon: isFlashTorchOn ? Icons.flash_on : Icons.flash_auto,
                label: 'Flash',
                onTap: onToggleFlash,
              ),
              _LabeledControlButton(
                icon: Icons.flip_camera_ios,
                label: 'Flip',
                onTap: canFlipCamera ? onFlipCamera : null,
                enabled: canFlipCamera,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Done button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: capturedImages.isNotEmpty ? onFinishBatch : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: capturedImages.isNotEmpty
                        ? context.primaryGreen
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check,
                        color: capturedImages.isNotEmpty
                            ? Colors.white
                            : Colors.white54,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Done (${capturedImages.length})',
                        style: TextStyle(
                          color: capturedImages.isNotEmpty
                              ? Colors.white
                              : Colors.white54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMasterKeyControls(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveLayout.horizontalPadding(context),
        vertical: 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CameraAssistantPanel(
            title: 'Scan Answer Sheet',
            detail: 'Place the answer key in frame',
            capturedCount: 0,
          ),
          const SizedBox(height: 24),
          _CaptureButton(
            isCapturing: isCapturing,
            onCapture: onCaptureMasterKey,
            isAuto: false,
            icon: Icons.document_scanner_outlined,
            size: 80,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LabeledControlButton(
                icon: isFlashTorchOn ? Icons.flash_on : Icons.flash_auto,
                label: 'Flash',
                onTap: onToggleFlash,
              ),
              const SizedBox(width: 16),
              _LabeledControlButton(
                icon: Icons.flip_camera_ios,
                label: 'Flip',
                onTap: canFlipCamera ? onFlipCamera : null,
                enabled: canFlipCamera,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBatchControls(BuildContext context) {
    final hasError = captureErrorMessage != null;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveLayout.horizontalPadding(context),
        vertical: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScanModeControl(
            autoEnabled: isAutoCapture,
            onManualTap: onToggleAutoCapture,
            onAutoTap: onToggleAutoCapture,
          ),
          const SizedBox(height: 10),
          if (hasError) ...[
            // Error state: show error message with retry and manual buttons
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          captureErrorMessage!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: captureErrorOnRetry,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: captureErrorAssessment != null
                              ? () {
                                  Navigator.pushNamed(
                                    context,
                                    '/quick_enter',
                                    arguments: captureErrorAssessment,
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Enter Score'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            // Normal state: show assistant panel
            CameraAssistantPanel(
              title: lastCaptureTitle.isNotEmpty ? lastCaptureTitle : 'Align paper in frame',
              detail: lastCaptureDetail.isNotEmpty ? lastCaptureDetail : 'Then tap capture',
              capturedCount: capturedImages.length,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Import from gallery
              _LabeledControlButton(
                icon: Icons.add_photo_alternate_outlined,
                label: 'Import',
                onTap: onPickUploaded,
              ),
              // Thumbnail of last captured image
              _ThumbnailButton(
                capturedImages: capturedImages,
                onViewCaptured: onViewCaptured,
              ),
              // Capture button
              _CaptureButton(
                isCapturing: isCapturing,
                onCapture: onCapture,
                isAuto: false,
              ),
              // Flash
              _LabeledControlButton(
                icon: isFlashTorchOn ? Icons.flash_on : Icons.flash_auto,
                label: 'Flash',
                onTap: onToggleFlash,
              ),
              // Camera flip
              _LabeledControlButton(
                icon: Icons.flip_camera_ios,
                label: 'Flip',
                onTap: canFlipCamera ? onFlipCamera : null,
                enabled: canFlipCamera,
              ),
            ],
          ),

          // Counter badge + Done button
          if (capturedImages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${capturedImages.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Tap \u2713 when done scanning',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: capturedImages.isNotEmpty ? onFinishBatch : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: context.primaryGreen,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check, color: Colors.white, size: 18),
                          SizedBox(width: 4),
                          Text(
                            'Done',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Labeled icon control button (≥44dp target) for flash, flip, and import.
class _LabeledControlButton extends StatelessWidget {
  const _LabeledControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isEnabled = enabled && onTap != null;
    return InkWell(
      onTap: isEnabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isEnabled
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isEnabled ? Colors.white38 : Colors.white12,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isEnabled ? Colors.white : Colors.white38,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isEnabled ? Colors.white : Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thumbnail of the last captured image; tap to view captured papers.
class _ThumbnailButton extends StatelessWidget {
  const _ThumbnailButton({
    required this.capturedImages,
    required this.onViewCaptured,
  });

  final List<String> capturedImages;
  final VoidCallback onViewCaptured;

  @override
  Widget build(BuildContext context) {
    final hasImages = capturedImages.isNotEmpty;
    return GestureDetector(
      onTap: hasImages ? onViewCaptured : null,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white38),
        ),
        child: hasImages
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(capturedImages.last),
                  fit: BoxFit.cover,
                ),
              )
            : const Icon(Icons.photo_library, color: Colors.white54),
      ),
    );
  }
}

/// Shutter-style capture button: white ring with brand-green solid disc.
class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    required this.isCapturing,
    required this.onCapture,
    required this.isAuto,
    this.icon = Icons.camera,
    this.size = 72,
  });

  final bool isCapturing;
  final VoidCallback onCapture;
  final bool isAuto;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isCapturing ? null : onCapture,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCapturing ? Colors.grey : context.primaryGreen,
          ),
          child: isCapturing
              ? const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                )
              : Icon(
                  icon,
                  color: Colors.white,
                  size: size * 0.44,
                ),
        ),
      ),
    );
  }
}

/// Shows a grid of captured images for review.
void showCapturedImagesSheet({
  required BuildContext context,
  required List<String> capturedImages,
}) {
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
              '${capturedImages.length} Papers Captured',
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
                itemCount: capturedImages.length,
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(capturedImages[index]),
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

/// Shows a duplicate warning dialog. Returns true if teacher wants to keep.
Future<bool> showDuplicateDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: context.primaryYellow,
            size: 22,
          ),
          const SizedBox(width: 8),
          const Text('Possible Duplicate'),
        ],
      ),
      content: const Text(
        'This looks similar to a paper already captured. Not sure? '
        'Answers will be double-checked after processing.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Keep'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: ElevatedButton.styleFrom(
            backgroundColor: context.primaryRed,
          ),
          child: const Text('Skip'),
        ),
      ],
    ),
  );
  return result ?? false;
}
