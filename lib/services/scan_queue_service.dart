import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'cloud_ocr_service.dart';
import 'assessment_provider.dart';
import 'ocr_service.dart';

/// Offline-capable scan queue that saves images locally when no internet
/// and processes them in batch when connectivity returns.
///
/// Flow:
/// 1. Camera captures image → save to queue
/// 2. If internet available: process immediately
/// 3. If offline: mark as "queued for processing"
/// 4. When internet returns: process queue in batch
/// 5. Reports progress to teacher
class ScanQueueService {
  static final ScanQueueService _instance = ScanQueueService._();
  factory ScanQueueService() => _instance;
  ScanQueueService._();

  static const String _boxName = 'scan_queue';
  static const String _metadataKey = 'queue_metadata';

  bool _isProcessing = false;
  bool _initialized = false;
  final StreamController<ScanQueueProgress> _progressController =
      StreamController<ScanQueueProgress>.broadcast();

  /// Stream of processing progress updates.
  Stream<ScanQueueProgress> get progressStream => _progressController.stream;

  bool get isProcessing => _isProcessing;

  /// Initialize the queue (open Hive box).
  Future<void> initialize() async {
    if (_initialized) return;
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    _initialized = true;
    debugPrint('ScanQueue: initialized');
  }

  /// Add a captured image to the queue.
  ///
  /// Returns the queue item ID for tracking.
  Future<String> enqueue({
    required String imagePath,
    required String assessmentId,
    String studentId = '',
    String studentName = '',
  }) async {
    await initialize();
    final box = Hive.box(_boxName);

    final item = ScanQueueItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imagePath: imagePath,
      assessmentId: assessmentId,
      studentId: studentId,
      studentName: studentName,
      status: ScanQueueItemStatus.queued,
      createdAt: DateTime.now(),
    );

    await box.put(item.id, item.toMap());
    debugPrint('ScanQueue: enqueued ${item.id} for assessment $assessmentId');
    return item.id;
  }

  /// Process a single item from the queue immediately.
  ///
  /// Used when internet is available during capture.
  Future<ScanQueueItem> processItem(String itemId) async {
    await initialize();
    final box = Hive.box(_boxName);
    final data = box.get(itemId);
    if (data == null) {
      throw Exception('Queue item not found: $itemId');
    }

    final item = ScanQueueItem.fromMap(Map<String, dynamic>.from(data as Map));

    // Mark as processing
    item.status = ScanQueueItemStatus.processing;
    await box.put(itemId, item.toMap());

    try {
      final cloudOcr = CloudOcrService();
      if (!cloudOcr.isConfigured) {
        // Fall back to local OCR
        final localResult = await _processLocal(item);
        item.status = ScanQueueItemStatus.completed;
        item.resultText = localResult;
        await box.put(itemId, item.toMap());
        return item;
      }

      // Process with cloud OCR
      int? questionCount;
      try {
        final assessmentProv = AssessmentProvider();
        final assessment = assessmentProv.getAssessmentById(item.assessmentId);
        if (assessment != null) questionCount = assessment.questions.length;
      } catch (_) {}
      final result = await cloudOcr.processImage(item.imagePath, questionCount: questionCount);
      item.status = ScanQueueItemStatus.completed;
      item.resultText = result.rawText;
      item.resultConfidence = result.confidence;
      item.detectedAnswers = result.answers
          .map((a) => {'q': a.questionNumber, 'a': a.answer, 'c': a.confidence})
          .toList();
      await box.put(itemId, item.toMap());
      return item;
    } catch (e) {
      item.status = ScanQueueItemStatus.failed;
      item.errorMessage = e.toString();
      await box.put(itemId, item.toMap());
      return item;
    }
  }

  /// Process all queued items in batch.
  ///
  /// Called when internet connectivity returns.
  /// Reports progress via [progressStream].
  Future<int> processQueue() async {
    if (_isProcessing) return 0;
    _isProcessing = true;

    await initialize();
    final box = Hive.box(_boxName);

    final queuedItems = box.values
        .map((data) => ScanQueueItem.fromMap(Map<String, dynamic>.from(data as Map)))
        .where((item) => item.status == ScanQueueItemStatus.queued)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (queuedItems.isEmpty) {
      _isProcessing = false;
      return 0;
    }

    debugPrint('ScanQueue: processing ${queuedItems.length} queued items');
    int processed = 0;
    int failed = 0;

    for (final item in queuedItems) {
      _progressController.add(ScanQueueProgress(
        current: processed + 1,
        total: queuedItems.length,
        status: 'Processing paper ${processed + 1} of ${queuedItems.length}...',
      ));

      try {
        await processItem(item.id);
        processed++;
      } catch (e) {
        debugPrint('ScanQueue: failed to process ${item.id}: $e');
        failed++;
      }
    }

    _isProcessing = false;

    _progressController.add(ScanQueueProgress(
      current: queuedItems.length,
      total: queuedItems.length,
      status: 'Done: $processed processed, $failed failed',
      isComplete: true,
    ));

    debugPrint('ScanQueue: batch complete — $processed processed, $failed failed');
    return processed;
  }

  /// Get count of queued items.
  Future<int> getQueuedCount() async {
    await initialize();
    final box = Hive.box(_boxName);
    return box.values
        .map((data) => ScanQueueItem.fromMap(Map<String, dynamic>.from(data as Map)))
        .where((item) => item.status == ScanQueueItemStatus.queued)
        .length;
  }

  /// Get all items for an assessment.
  Future<List<ScanQueueItem>> getItemsForAssessment(String assessmentId) async {
    await initialize();
    final box = Hive.box(_boxName);
    return box.values
        .map((data) => ScanQueueItem.fromMap(Map<String, dynamic>.from(data as Map)))
        .where((item) => item.assessmentId == assessmentId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Clear completed items older than [days].
  Future<void> cleanup({int days = 7}) async {
    await initialize();
    final box = Hive.box(_boxName);
    final cutoff = DateTime.now().subtract(Duration(days: days));

    final toDelete = <String>[];
    for (final key in box.keys) {
      final data = box.get(key);
      if (data == null) continue;
      final item = ScanQueueItem.fromMap(Map<String, dynamic>.from(data as Map));
      if (item.status == ScanQueueItemStatus.completed &&
          item.createdAt.isBefore(cutoff)) {
        toDelete.add(key as String);
        // Delete the image file too
        try {
          final file = File(item.imagePath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }

    await box.deleteAll(toDelete);
    if (toDelete.isNotEmpty) {
      debugPrint('ScanQueue: cleaned up ${toDelete.length} old items');
    }
  }

  /// Process a single item using local OCR (fallback when offline).
  Future<String> _processLocal(ScanQueueItem item) async {
    // This would call OcrService — placeholder for now
    return 'Local OCR processing';
  }

  void dispose() {
    _progressController.close();
  }
}

/// Status of a queued scan item.
enum ScanQueueItemStatus { queued, processing, completed, failed }

/// A single item in the scan queue.
class ScanQueueItem {
  final String id;
  final String imagePath;
  final String assessmentId;
  final String studentId;
  final String studentName;
  ScanQueueItemStatus status;
  final DateTime createdAt;
  String resultText;
  double resultConfidence;
  List<Map<String, dynamic>> detectedAnswers;
  String errorMessage;

  ScanQueueItem({
    required this.id,
    required this.imagePath,
    required this.assessmentId,
    this.studentId = '',
    this.studentName = '',
    required this.status,
    required this.createdAt,
    this.resultText = '',
    this.resultConfidence = 0.0,
    this.detectedAnswers = const [],
    this.errorMessage = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'imagePath': imagePath,
    'assessmentId': assessmentId,
    'studentId': studentId,
    'studentName': studentName,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'resultText': resultText,
    'resultConfidence': resultConfidence,
    'detectedAnswers': detectedAnswers,
    'errorMessage': errorMessage,
  };

  factory ScanQueueItem.fromMap(Map<String, dynamic> map) => ScanQueueItem(
    id: map['id'] ?? '',
    imagePath: map['imagePath'] ?? '',
    assessmentId: map['assessmentId'] ?? '',
    studentId: map['studentId'] ?? '',
    studentName: map['studentName'] ?? '',
    status: ScanQueueItemStatus.values.firstWhere(
      (s) => s.name == map['status'],
      orElse: () => ScanQueueItemStatus.queued,
    ),
    createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
    resultText: map['resultText'] ?? '',
    resultConfidence: (map['resultConfidence'] as num?)?.toDouble() ?? 0.0,
    detectedAnswers: (map['detectedAnswers'] as List?)
        ?.map((a) => Map<String, dynamic>.from(a as Map))
        .toList() ?? [],
    errorMessage: map['errorMessage'] ?? '',
  );
}

/// Progress update from queue processing.
class ScanQueueProgress {
  final int current;
  final int total;
  final String status;
  final bool isComplete;

  const ScanQueueProgress({
    required this.current,
    required this.total,
    required this.status,
    this.isComplete = false,
  });

  double get fraction => total > 0 ? current / total : 0.0;
}
