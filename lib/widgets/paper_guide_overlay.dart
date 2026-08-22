import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Alignment state of the paper within the camera guide.
enum PaperGuideState {
  /// No paper detected — white brackets.
  idle,

  /// Paper detected but tilted or misaligned — yellow brackets.
  detected,

  /// Paper detected and properly aligned — green brackets.
  aligned,

  /// The scene is too dark for reliable capture.
  tooDark,

  /// The phone or paper is moving too much.
  moving,

  /// The paper is outside the guide frame.
  outsideFrame,
}

/// Draws a paper-alignment overlay on top of the camera preview.
///
/// Pure paint — no image processing, no allocations in [paint].
/// Scales proportionally from 480p to 1440p screens.
class PaperGuideOverlay extends StatefulWidget {
  const PaperGuideOverlay({
    super.key,
    required this.state,
    this.countdown,
    this.feedbackText,
    this.onEnableFlash,
  });

  final PaperGuideState state;

  /// 3, 2, 1, or null when not counting down.
  final int? countdown;

  /// Real-time position feedback text (e.g. "Move closer").
  final String? feedbackText;

  /// Invoked when the user taps "Turn on flash" in the too-dark state.
  final VoidCallback? onEnableFlash;

  @override
  State<PaperGuideOverlay> createState() => _PaperGuideOverlayState();
}

class _PaperGuideOverlayState extends State<PaperGuideOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  Animation<double>? _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant PaperGuideOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncPulse();
  }

  void _syncPulse() {
    final shouldPulse = widget.state == PaperGuideState.aligned &&
        widget.countdown == null;
    if (shouldPulse) {
      if (!_pulseController.isAnimating) {
        _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
        );
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return CustomPaint(
          painter: _PaperGuidePainter(
            state: widget.state,
            countdown: widget.countdown,
            pulse: _pulse?.value,
          ),
          child: child,
        );
      },
      child: Stack(
        children: [
          // Hint text at bottom of guide
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 140),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HintText(
                    state: widget.state,
                    feedbackText: widget.feedbackText,
                  ),
                  if (widget.state == PaperGuideState.tooDark &&
                      widget.onEnableFlash != null) ...[
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: widget.onEnableFlash,
                      icon: const Icon(Icons.flash_on, size: 18),
                      label: const Text('Turn on flash'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryYellow,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Countdown overlay in center
          if (widget.countdown != null)
            Center(
              child: _CountdownDisplay(countdown: widget.countdown!),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Countdown display
// ---------------------------------------------------------------------------

class _CountdownDisplay extends StatelessWidget {
  final int countdown;
  const _CountdownDisplay({required this.countdown});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(countdown),
      tween: Tween(begin: 1.5, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.primaryGreen.withValues(alpha: 0.9),
              boxShadow: [
                BoxShadow(
                  color: context.primaryGreen.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: Text(
                '$countdown',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Hint text
// ---------------------------------------------------------------------------

class _HintText extends StatelessWidget {
  const _HintText({required this.state, this.feedbackText});

  final PaperGuideState state;
  final String? feedbackText;

  @override
  Widget build(BuildContext context) {
    final label = feedbackText ?? _label();
    if (label == null) return const SizedBox.shrink();

    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _stateIcon(state),
              color: _stateColor(state),
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  IconData _stateIcon(PaperGuideState state) {
    switch (state) {
      case PaperGuideState.aligned:
        return Icons.check_circle;
      case PaperGuideState.detected:
      case PaperGuideState.outsideFrame:
        return Icons.center_focus_weak;
      case PaperGuideState.tooDark:
        return Icons.brightness_low;
      case PaperGuideState.moving:
        return Icons.pan_tool;
      case PaperGuideState.idle:
        return Icons.center_focus_strong;
    }
  }

  Color _stateColor(PaperGuideState state) {
    switch (state) {
      case PaperGuideState.aligned:
        return AppTheme.primaryGreen;
      case PaperGuideState.tooDark:
      case PaperGuideState.moving:
      case PaperGuideState.outsideFrame:
        return AppTheme.primaryYellow;
      case PaperGuideState.idle:
      case PaperGuideState.detected:
        return Colors.black87;
    }
  }

  String? _label() {
    switch (state) {
      case PaperGuideState.idle:
        return 'Place paper inside the frame';
      case PaperGuideState.detected:
        return 'Align paper within the frame';
      case PaperGuideState.aligned:
        return 'Hold steady — preparing to capture';
      case PaperGuideState.tooDark:
        return 'Too dark — use flash or more light';
      case PaperGuideState.moving:
        return 'Hold still';
      case PaperGuideState.outsideFrame:
        return 'Move paper into the frame';
    }
  }
}

// ---------------------------------------------------------------------------
// Painter — zero allocations in paint()
// ---------------------------------------------------------------------------

class _PaperGuidePainter extends CustomPainter {
  _PaperGuidePainter({required this.state, this.countdown, this.pulse});

  final PaperGuideState state;
  final int? countdown;
  final double? pulse;

  // Pre-allocated paints (created once per painter, reused in paint).
  late final _bracketPaint = Paint()
    ..color = _bracketColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round;

  late final _fillPaint = Paint()
    ..color = _bracketColor.withValues(alpha: 0.06)
    ..style = PaintingStyle.fill;

  Color get _bracketColor {
    if (countdown != null) return AppTheme.primaryGreen;
    switch (state) {
      case PaperGuideState.idle:
        return Colors.white;
      case PaperGuideState.detected:
      case PaperGuideState.tooDark:
      case PaperGuideState.moving:
      case PaperGuideState.outsideFrame:
        return AppTheme.primaryYellow;
      case PaperGuideState.aligned:
        return AppTheme.primaryGreen;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Guide rect: 80% viewport width, A4 portrait aspect ratio (~1:1.414).
    final guideWidth = size.width * 0.80;
    final guideHeight = guideWidth * 1.414;

    final centerX = size.width / 2;
    final centerY = size.height / 2 - 20; // slight upward shift for controls

    final rect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: guideWidth,
      height: guideHeight,
    );

    // Semi-transparent fill.
    canvas.drawRect(rect, _fillPaint);

    // Corner brackets — 24dp arm length, proportional to width.
    final arm = guideWidth * 0.07; // ~24dp at 360dp width, scales up/down

    // Pulse: subtly grow the brackets and brighten them when aligned.
    final pulseValue = pulse ?? 0.0;
    final pulseGrow = 1.0 + pulseValue * 0.015;
    final pulsingBracketPaint = Paint()
      ..color = _bracketColor.withValues(alpha: 0.25 + pulseValue * 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    _drawCornerBracket(
      canvas,
      rect.topLeft,
      arm * pulseGrow,
      _BracketCorner.topLeft,
      paint: pulseValue > 0 ? pulsingBracketPaint : _bracketPaint,
    );
    _drawCornerBracket(
      canvas,
      rect.topRight,
      arm * pulseGrow,
      _BracketCorner.topRight,
      paint: pulseValue > 0 ? pulsingBracketPaint : _bracketPaint,
    );
    _drawCornerBracket(
      canvas,
      rect.bottomLeft,
      arm * pulseGrow,
      _BracketCorner.bottomLeft,
      paint: pulseValue > 0 ? pulsingBracketPaint : _bracketPaint,
    );
    _drawCornerBracket(
      canvas,
      rect.bottomRight,
      arm * pulseGrow,
      _BracketCorner.bottomRight,
      paint: pulseValue > 0 ? pulsingBracketPaint : _bracketPaint,
    );

    // During countdown, draw a pulsing border around the guide
    if (countdown != null) {
      final pulsePaint = Paint()
        ..color = AppTheme.primaryGreen.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(rect, pulsePaint);
    }
  }

  void _drawCornerBracket(
    Canvas canvas,
    Offset origin,
    double arm,
    _BracketCorner corner, {
    Paint? paint,
  }) {
    final stroke = paint ?? _bracketPaint;
    late Offset hStart, hEnd, vStart, vEnd;

    switch (corner) {
      case _BracketCorner.topLeft:
        hStart = origin + Offset(0, arm);
        hEnd = origin;
        vStart = origin;
        vEnd = origin + Offset(arm, 0);
        break;
      case _BracketCorner.topRight:
        hStart = origin + Offset(-arm, 0);
        hEnd = origin;
        vStart = origin;
        vEnd = origin + Offset(0, arm);
        break;
      case _BracketCorner.bottomLeft:
        hStart = origin + Offset(0, -arm);
        hEnd = origin;
        vStart = origin;
        vEnd = origin + Offset(arm, 0);
        break;
      case _BracketCorner.bottomRight:
        hStart = origin + Offset(-arm, 0);
        hEnd = origin;
        vStart = origin;
        vEnd = origin + Offset(0, -arm);
        break;
    }

    canvas.drawLine(hStart, hEnd, stroke);
    canvas.drawLine(vStart, vEnd, stroke);
  }

  @override
  bool shouldRepaint(covariant _PaperGuidePainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.countdown != countdown ||
        oldDelegate.pulse != pulse;
  }
}

enum _BracketCorner { topLeft, topRight, bottomLeft, bottomRight }
