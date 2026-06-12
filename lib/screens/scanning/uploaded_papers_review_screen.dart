import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/assessment.dart';
import '../../services/paper_image_intake_service.dart';

class UploadedPapersReviewArgs {
  final Assessment assessment;
  final List<String> imagePaths;

  const UploadedPapersReviewArgs({
    required this.assessment,
    required this.imagePaths,
  });
}

class UploadedPapersReviewScreen extends StatefulWidget {
  final UploadedPapersReviewArgs args;

  const UploadedPapersReviewScreen({super.key, required this.args});

  @override
  State<UploadedPapersReviewScreen> createState() =>
      _UploadedPapersReviewScreenState();
}

class _UploadedPapersReviewScreenState
    extends State<UploadedPapersReviewScreen> {
  final PaperImageIntakeService _intake = PaperImageIntakeService();
  late List<PaperImageReviewItem> _items;
  bool _isPreparing = false;

  List<PaperImageReviewItem> get _ready => _items
      .where((item) => item.readiness == PaperImageReadiness.ready)
      .toList();
  List<PaperImageReviewItem> get _attention => _items
      .where((item) => item.readiness == PaperImageReadiness.needsAttention)
      .toList();
  List<PaperImageReviewItem> get _rejected => _items
      .where((item) => item.readiness == PaperImageReadiness.rejected)
      .toList();

  @override
  void initState() {
    super.initState();
    _items = _intake.reviewPaths(
      paths: widget.args.imagePaths,
      source: PaperImageSource.upload,
    );
  }

  @override
  Widget build(BuildContext context) {
    final readyCount = _ready.length;
    final attentionCount = _attention.length;
    final rejectedCount = _rejected.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Prepare uploaded papers')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: _UploadSummary(
                readyCount: readyCount,
                attentionCount: attentionCount,
                rejectedCount: rejectedCount,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  ..._ready.map(
                    (item) => _PaperPhotoTile(
                      item: item,
                      onRemove: () => _remove(item),
                    ),
                  ),
                  ..._attention.map(
                    (item) => _PaperPhotoTile(
                      item: item,
                      onRemove: () => _remove(item),
                    ),
                  ),
                  ..._rejected.map(
                    (item) => _PaperPhotoTile(
                      item: item,
                      onRemove: () => _remove(item),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isPreparing ? null : _addMore,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Add more'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: readyCount == 0 || _isPreparing
                          ? null
                          : _continueGrading,
                      icon: _isPreparing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_forward),
                      label: Text(
                        _isPreparing ? 'Preparing...' : 'Grade $readyCount',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMore() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (!mounted || picked == null) return;

    final existing = _items.map((item) => item.path).toSet();
    final newItems = _intake.reviewPaths(
      paths: picked.files
          .map((file) => file.path)
          .where((path) => path != null && !existing.contains(path)),
      source: PaperImageSource.upload,
    );

    setState(() => _items.addAll(newItems));
  }

  void _remove(PaperImageReviewItem item) {
    setState(() => _items.remove(item));
  }

  Future<void> _continueGrading() async {
    setState(() => _isPreparing = true);
    final copiedPaths = await _intake.copyReadyImagesForGrading(items: _ready);
    if (!mounted) return;

    if (copiedPaths.isEmpty) {
      setState(() => _isPreparing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No ready photos could be prepared')),
      );
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      AppRoutes.batchScan,
      arguments: {
        'images': copiedPaths,
        'assessment': widget.args.assessment,
        'imageSource': PaperImageSource.upload.name,
      },
    );
  }
}

class _UploadSummary extends StatelessWidget {
  final int readyCount;
  final int attentionCount;
  final int rejectedCount;

  const _UploadSummary({
    required this.readyCount,
    required this.attentionCount,
    required this.rejectedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Check photos before grading',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '$readyCount ready'
            '${attentionCount > 0 ? ' - $attentionCount need attention' : ''}'
            '${rejectedCount > 0 ? ' - $rejectedCount rejected' : ''}',
            style: const TextStyle(color: AppTheme.lightText),
          ),
        ],
      ),
    );
  }
}

class _PaperPhotoTile extends StatelessWidget {
  final PaperImageReviewItem item;
  final VoidCallback onRemove;

  const _PaperPhotoTile({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final color = switch (item.readiness) {
      PaperImageReadiness.ready => AppTheme.primaryGreen,
      PaperImageReadiness.needsAttention => AppTheme.primaryYellow,
      PaperImageReadiness.rejected => AppTheme.primaryRed,
    };
    final title = switch (item.readiness) {
      PaperImageReadiness.ready => 'Ready',
      PaperImageReadiness.needsAttention => 'Needs attention',
      PaperImageReadiness.rejected => 'Rejected',
    };

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: item.canShowPreview
              ? Image.file(
                  File(item.path),
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                )
              : Container(
                  width: 48,
                  height: 48,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image_outlined),
                ),
        ),
        title: Text(title, style: TextStyle(color: color)),
        subtitle: Text(
          item.message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.close),
          tooltip: 'Remove',
        ),
      ),
    );
  }
}
