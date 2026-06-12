import 'package:flutter/material.dart';

/// Camera unavailable view shown when camera fails to initialize.
class CameraUnavailableView extends StatelessWidget {
  final bool isStarting;
  final String? message;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final VoidCallback onManualEntry;

  const CameraUnavailableView({
    super.key,
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
          ],
        ),
      ),
    );
  }
}
