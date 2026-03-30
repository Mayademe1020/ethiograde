import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../services/locale_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/ocr_service.dart';
import '../../services/analytics_provider.dart';
import '../../services/scoring_service.dart';

class BatchScanScreen extends StatefulWidget {
  const BatchScanScreen({super.key});

  @override
  State<BatchScanScreen> createState() => _BatchScanScreenState();
}

class _BatchScanScreenState extends State<BatchScanScreen> {
  final List<ScanResult> _results = [];
  List<AnswerDuplicate> _duplicates = [];
  bool _isProcessing = false;
  int _processedCount = 0;
  int _totalCount = 0;
  List<String> _imagePaths = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null && _results.isEmpty) {
      final images = args['images'] as List<String>;
      final assessment = args['assessment'] as Assessment?;
      if (assessment != null) {
        _imagePaths = List<String>.from(images);
        _totalCount = images.length;
        _processBatch(images, assessment);
      }
    }
  }

  Future<void> _processBatch(
    List<String> images,
    Assessment assessment,
  ) async {
    if (!mounted) return;
    setState(() => _isProcessing = true);
    final grading = HybridGradingService();

    final results = await grading.gradeBatch(
      imagePaths: images,
      assessment: assessment,
      onProgress: (processed, total) {
        if (mounted) {
          setState(() {
            _processedCount = processed;
          });
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _results.addAll(results);
      _isProcessing = false;
    });

    // Detect answer-pattern duplicates (post-OCR)
    if (_results.length >= 2) {
      _duplicates = grading.detectBatchDuplicates(_results);
      if (_duplicates.isNotEmpty) {
        debugPrint('BatchScan: ${_duplicates.length} answer-pattern duplicate(s) detected');
      }
    }

    // Compute analytics after batch completes
    if (mounted && _results.isNotEmpty) {
      context.read<AnalyticsProvider>().computeAnalytics(
        assessment: assessment,
        results: _results,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAm = context.watch<LocaleProvider>().isAmharic;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAm ? 'የጅምላ ስካኒንግ' : 'Batch Scan'),
        actions: [
          if (_results.isNotEmpty && !_isProcessing)
            IconButton(
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.reports,
              ),
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: isAm ? 'ሪፖርት' : 'Report',
            ),
          if (_results.isNotEmpty && !_isProcessing)
            TextButton.icon(
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.review,
                arguments: _results,
              ),
              icon: const Icon(Icons.rate_review),
              label: Text(isAm ? 'ይገምግሙ' : 'Review'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Progress header
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.primaryGreen.withOpacity(0.05),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isAm ? 'ሂደት' : 'Progress',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '$_processedCount / $_totalCount',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _totalCount > 0
                        ? _processedCount / _totalCount
                        : 0,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.primaryGreen,
                    ),
                  ),
                ),
                if (_isProcessing)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isAm ? 'በማስኬድ ላይ...' : 'Processing...',
                          style: TextStyle(
                            color: AppTheme.lightText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Summary stats (when done)
          if (!_isProcessing && _results.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: isAm ? 'አማካይ' : 'Avg',
                      value: _average.toStringAsFixed(1),
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniStat(
                      label: isAm ? 'ከፍተኛ' : 'High',
                      value: _highest.toStringAsFixed(1),
                      color: AppTheme.info,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniStat(
                      label: isAm ? 'ዝቅተኛ' : 'Low',
                      value: _lowest.toStringAsFixed(1),
                      color: AppTheme.primaryRed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniStat(
                      label: isAm ? 'ማለፍ' : 'Pass',
                      value: '${_passRate.toStringAsFixed(0)}%',
                      color: AppTheme.success,
                    ),
                  ),
                ],
              ),
            ),

          // Duplicate warnings (answer-pattern detection)
          if (_duplicates.isNotEmpty && !_isProcessing)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryYellow.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryYellow.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: AppTheme.primaryYellow, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        isAm ? 'ሊመሰሉ የሚችሉ ቅጂዎች' : 'Possible Duplicates',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...(_duplicates.map((d) {
                    final nameA = d.scanIndexA < _results.length
                        ? _results[d.scanIndexA].studentName
                        : '#${d.scanIndexA + 1}';
                    final nameB = d.scanIndexB < _results.length
                        ? _results[d.scanIndexB].studentName
                        : '#${d.scanIndexB + 1}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        isAm
                            ? '  #$nameA እና #$nameB — መልሶች ${d.matchPercent.toStringAsFixed(0)}% ተመሳሰሉ'
                            : '  #$nameA & #$nameB — answers ${d.matchPercent.toStringAsFixed(0)}% match',
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  })),
                ],
              ),
            ),

          // Results list
          Expanded(
            child: _results.isEmpty && !_isProcessing
                ? Center(
                    child: Text(
                      isAm ? 'ውጤት የለም' : 'No results yet',
                      style: TextStyle(color: AppTheme.lightText),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final r = _results[index];
                      final passed = r.percentage >= 50;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: passed
                                ? AppTheme.primaryGreen.withOpacity(0.1)
                                : AppTheme.primaryRed.withOpacity(0.1),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: passed
                                    ? AppTheme.primaryGreen
                                    : AppTheme.primaryRed,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(r.studentName),
                          subtitle: Text(
                            '${r.totalScore.toInt()}/${r.maxScore.toInt()} • ${r.grade}',
                          ),
                          trailing: Text(
                            '${r.percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: passed
                                  ? AppTheme.primaryGreen
                                  : AppTheme.primaryRed,
                            ),
                          ),
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.sideBySide,
                            arguments: r,
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Bottom actions
          if (!_isProcessing && _results.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pushNamed(
                          context,
                          AppRoutes.analytics,
                        ),
                        icon: const Icon(Icons.analytics),
                        label: Text(isAm ? 'ትንተና' : 'Analytics'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pushNamed(
                          context,
                          AppRoutes.review,
                          arguments: _results,
                        ),
                        icon: const Icon(Icons.rate_review),
                        label: Text(isAm ? 'ሁሉን ይገምግሙ' : 'Review All'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  double get _average {
    if (_results.isEmpty) return 0;
    return _results.fold(0.0, (s, r) => s + r.percentage) / _results.length;
  }

  double get _highest {
    if (_results.isEmpty) return 0;
    return _results.map((r) => r.percentage).reduce((a, b) => a > b ? a : b);
  }

  double get _lowest {
    if (_results.isEmpty) return 0;
    return _results.map((r) => r.percentage).reduce((a, b) => a < b ? a : b);
  }

  double get _passRate {
    if (_results.isEmpty) return 0;
    final passed = _results.where((r) => r.percentage >= 50).length;
    return passed / _results.length * 100;
  }

  @override
  void dispose() {
    // Clean up enhanced/corrected images after grading completes.
    // Original captured images are managed by CameraScreen.
    if (_imagePaths.isNotEmpty) {
      for (final path in _imagePaths) {
        OcrService().cleanupEnhancedImages(path);
      }
    }
    super.dispose();
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppTheme.lightText),
          ),
        ],
      ),
    );
  }
}
