import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// Camera assistant panel showing scan status and guidance.
class CameraAssistantPanel extends StatelessWidget {
  final String title;
  final String detail;
  final int capturedCount;

  const CameraAssistantPanel({
    super.key,
    required this.title,
    required this.detail,
    required this.capturedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              capturedCount == 0 ? Icons.center_focus_strong : Icons.check,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.25,
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

/// Scan mode control (Manual vs Auto toggle).
class ScanModeControl extends StatelessWidget {
  final bool autoEnabled;
  final VoidCallback onManualTap;
  final VoidCallback onAutoTap;

  const ScanModeControl({
    super.key,
    required this.autoEnabled,
    required this.onManualTap,
    required this.onAutoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onManualTap,
            child: ScanModePill(
              icon: Icons.touch_app_outlined,
              label: 'Manual',
              subtitle: 'Tap each paper',
              active: !autoEnabled,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: onAutoTap,
            child: ScanModePill(
              icon: Icons.auto_awesome_motion_outlined,
              label: 'Auto',
              subtitle: autoEnabled ? 'Watching paper' : 'Capture next',
              active: autoEnabled,
            ),
          ),
        ),
      ],
    );
  }
}

/// Single scan mode pill (Manual or Auto).
class ScanModePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool active;

  const ScanModePill({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = active ? Colors.white : Colors.white60;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: active
            ? AppTheme.primaryGreen.withValues(alpha: 0.24)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? AppTheme.primaryGreen : Colors.white24,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: foreground, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Camera guidance panel with icon, title, and detail text.
class CameraGuidancePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const CameraGuidancePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.25,
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
