enum AutoScanReadiness {
  disabled,
  noPaper,
  tooDark,
  moving,
  waitingForNewPaper,
  coolingDown,
  steady,
  capture,
}

class AutoScanFrameSignal {
  final bool paperVisible;
  final double brightness;
  final double movement;
  final int? contentHash;
  final double paperCoverage;
  final double offsetX;
  final double offsetY;

  const AutoScanFrameSignal({
    required this.paperVisible,
    required this.brightness,
    required this.movement,
    this.contentHash,
    this.paperCoverage = 0.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
  });
}

class AutoScanDecision {
  final AutoScanReadiness readiness;
  final bool shouldCapture;
  final String message;

  const AutoScanDecision({
    required this.readiness,
    required this.shouldCapture,
    required this.message,
  });
}

class AutoScanEngine {
  static const Duration defaultStableDuration = Duration(milliseconds: 900);
  static const Duration defaultCaptureCooldown = Duration(seconds: 2);

  final Duration stableDuration;
  final Duration captureCooldown;
  final double minBrightness;
  final double maxMovement;

  DateTime? _stableSince;
  DateTime? _lastCaptureAt;
  int? _lastCapturedHash;

  AutoScanEngine({
    this.stableDuration = defaultStableDuration,
    this.captureCooldown = defaultCaptureCooldown,
    this.minBrightness = 0.28,
    this.maxMovement = 0.18,
  });

  AutoScanDecision observe({
    required AutoScanFrameSignal frame,
    required DateTime now,
    required bool enabled,
  }) {
    if (!enabled) {
      _stableSince = null;
      return const AutoScanDecision(
        readiness: AutoScanReadiness.disabled,
        shouldCapture: false,
        message: 'Manual mode is active.',
      );
    }

    if (!frame.paperVisible) {
      _stableSince = null;
      return const AutoScanDecision(
        readiness: AutoScanReadiness.noPaper,
        shouldCapture: false,
        message: 'Place the next paper inside the frame.',
      );
    }

    if (frame.brightness < minBrightness) {
      _stableSince = null;
      return const AutoScanDecision(
        readiness: AutoScanReadiness.tooDark,
        shouldCapture: false,
        message: 'Too dark. Use flash or more light.',
      );
    }

    if (frame.movement > maxMovement) {
      _stableSince = null;
      return const AutoScanDecision(
        readiness: AutoScanReadiness.moving,
        shouldCapture: false,
        message: 'Hold still.',
      );
    }

    if (_isSameAsLastCapture(frame.contentHash)) {
      _stableSince = null;
      return const AutoScanDecision(
        readiness: AutoScanReadiness.waitingForNewPaper,
        shouldCapture: false,
        message: 'Insert a new paper.',
      );
    }

    if (_lastCaptureAt != null &&
        now.difference(_lastCaptureAt!) < captureCooldown) {
      return const AutoScanDecision(
        readiness: AutoScanReadiness.coolingDown,
        shouldCapture: false,
        message: 'Getting ready for the next paper.',
      );
    }

    _stableSince ??= now;
    if (now.difference(_stableSince!) < stableDuration) {
      return const AutoScanDecision(
        readiness: AutoScanReadiness.steady,
        shouldCapture: false,
        message: 'Hold steady.',
      );
    }

    return const AutoScanDecision(
      readiness: AutoScanReadiness.capture,
      shouldCapture: true,
      message: 'Capturing.',
    );
  }

  void recordCapture({required DateTime now, int? contentHash}) {
    _lastCaptureAt = now;
    _lastCapturedHash = contentHash;
    _stableSince = null;
  }

  void reset() {
    _stableSince = null;
    _lastCaptureAt = null;
    _lastCapturedHash = null;
  }

  bool _isSameAsLastCapture(int? contentHash) {
    if (contentHash == null || _lastCapturedHash == null) return false;
    return contentHash == _lastCapturedHash;
  }
}
