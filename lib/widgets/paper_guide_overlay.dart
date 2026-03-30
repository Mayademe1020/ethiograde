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
}

/// Draws a paper-alignment overlay on top of the camera preview.
///
/// Pure paint — no image processing, no allocations in [paint].
/// Scales proportionally from 480p to 1440p screens.
class PaperGuideOverlay extends StatelessWidget {
  const PaperGuideOverlay({
    super.key,
    required this.state,
    required this.isAmharic,
  });

  final PaperGuideState state;
  final bool isAmharic;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PaperGuidePainter(state: state),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 140),
          child: _HintText(state: state, isAm: isAmharic),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hint text
// ---------------------------------------------------------------------------

class _HintText extends StatelessWidget {
  const _HintText({required this.state, required this.isAm});

  final PaperGuideState state;
  final bool isAm;

  @override
  Widget build(BuildContext context) {
    final label = _label();
    if (label == null) return const SizedBox.shrink();

    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  String? _label() {
    switch (state) {
      case PaperGuideState.idle:
      case PaperGuideState.detected:
        return isAm
            ? 'ወረቀቱን በአገባቡ ያስተካክሉ'
            : 'Align paper within the frame';
      case PaperGuideState.aligned:
        return isAm ? 'የያዙትን ይቆዩ' : 'Hold steady';
    }
  }
}

// ---------------------------------------------------------------------------
// Painter — zero allocations in paint()
// ---------------------------------------------------------------------------

class _PaperGuidePainter extends CustomPainter {
  _PaperGuidePainter({required this.state});

  final PaperGuideState state;

  // Pre-allocated paints (created once per painter, reused in paint).
  late final _bracketPaint = Paint()
    ..color = _bracketColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;

  late final _fillPaint = Paint()
    ..color = _bracketColor.withOpacity(0.06)
    ..style = PaintingStyle.fill;

  Color get _bracketColor {
    switch (state) {
      case PaperGuideState.idle:
        return Colors.white;
      case PaperGuideState.detected:
        return AppTheme.primaryYellow;
      case PaperGuideState.aligned:
        return AppTheme.primaryGreen;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Guide rect: 80% viewport width, 3:4 portrait aspect ratio.
    final guideWidth = size.width * 0.80;
    final guideHeight = guideWidth * (4 / 3); // portrait: height > width

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
    _drawCornerBracket(canvas, rect.topLeft, arm, _BracketCorner.topLeft);
    _drawCornerBracket(canvas, rect.topRight, arm, _BracketCorner.topRight);
    _drawCornerBracket(
        canvas, rect.bottomLeft, arm, _BracketCorner.bottomLeft);
    _drawCornerBracket(
        canvas, rect.bottomRight, arm, _BracketCorner.bottomRight);
  }

  void _drawCornerBracket(
    Canvas canvas,
    Offset origin,
    double arm,
    _BracketCorner corner,
  ) {
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

    canvas.drawLine(hStart, hEnd, _bracketPaint);
    canvas.drawLine(vStart, vEnd, _bracketPaint);
  }

  @override
  bool shouldRepaint(covariant _PaperGuidePainter oldDelegate) {
    return oldDelegate.state != state;
  }
}

enum _BracketCorner { topLeft, topRight, bottomLeft, bottomRight }
