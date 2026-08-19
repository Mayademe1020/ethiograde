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
          // Done button only
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Thumbnail
              GestureDetector(
                onTap: capturedImages.isNotEmpty ? onViewCaptured : null,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white38),
                  ),
                  child: capturedImages.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(capturedImages.last),
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(Icons.photo_library, color: Colors.white54),
                ),
              ),
              const SizedBox(width: 24),
              // Done button
              GestureDetector(
                onTap: capturedImages.isNotEmpty ? onFinishBatch : null,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: capturedImages.isNotEmpty ? context.primaryGreen : Colors.white24,
                  ),
                  child: Icon(
                    Icons.check,
                    color: capturedImages.isNotEmpty ? Colors.white : Colors.white54,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Spacer for symmetry
              const SizedBox(width: 44),
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
          GestureDetector(
            onTap: isCapturing ? null : onCaptureMasterKey,
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
                  color: isCapturing ? Colors.grey : context.primaryGreen,
                ),
                child: isCapturing
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      )
                    : const Icon(
                        Icons.document_scanner_outlined,
                        color: Colors.white,
                        size: 32,
                      ),
              ),
            ),
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
              // Thumbnail of last captured image
              GestureDetector(
                onTap: capturedImages.isNotEmpty ? onViewCaptured : null,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white38),
                  ),
                  child: capturedImages.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(capturedImages.last),
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
                onTap: isCapturing ? null : onCapture,
                child: Container(
                  width: 72,
                  height: 72,
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
                onTap: capturedImages.isNotEmpty ? onFinishBatch : null,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: capturedImages.isNotEmpty ? context.primaryGreen : Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    color: capturedImages.isNotEmpty ? Colors.white : Colors.white54,
                  ),
                ),
              ),
            ],
          ),

          // Counter badge
          if (capturedImages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                  const Text(
                    'Tap \u2713 when done scanning',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
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
