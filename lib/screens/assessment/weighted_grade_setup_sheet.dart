import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/weighted_grade.dart';
import '../../services/weighted_grade_provider.dart';

/// Bottom sheet for setting up weighted grade components.
///
/// Teacher defines:
/// - Component name (e.g., "Quiz", "Midterm", "Final")
/// - Weight percentage (must total 100%)
/// - Optional: drop lowest N scores
///
/// Shows live validation and example calculation.
class WeightedGradeSetupSheet extends StatefulWidget {
  final String classId;
  final WeightedGradeScale? existingScale;

  const WeightedGradeSetupSheet({
    super.key,
    required this.classId,
    this.existingScale,
  });

  /// Show the setup sheet. Returns the created scale or null if cancelled.
  static Future<WeightedGradeScale?> show(
    BuildContext context, {
    required String classId,
    WeightedGradeScale? existingScale,
  }) {
    return showModalBottomSheet<WeightedGradeScale>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => WeightedGradeSetupSheet(
        classId: classId,
        existingScale: existingScale));
  }

  @override
  State<WeightedGradeSetupSheet> createState() =>
      _WeightedGradeSetupSheetState();
}

class _WeightedGradeSetupSheetState extends State<WeightedGradeSetupSheet> {
  late final TextEditingController _nameController;
  late List<_ComponentEntry> _components;
  String _rubricType = 'moe_national';

  @override
  void initState() {
    super.initState();
    final existing = widget.existingScale;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _rubricType = existing?.rubricType ?? 'moe_national';

    if (existing != null) {
      _components = existing.components
          .map((c) => _ComponentEntry(
                nameCtrl: TextEditingController(text: c.name),
                weightCtrl: TextEditingController(text: '${(c.weight * 100).toInt()}'),
                dropLowestCtrl: TextEditingController(text: '${c.dropLowest}')))
          .toList();
    } else {
      // Default: 3 components
      _components = [
        _ComponentEntry(
          nameCtrl: TextEditingController(text: 'Quiz'),
          weightCtrl: TextEditingController(text: '20'),
          dropLowestCtrl: TextEditingController(text: '0')),
        _ComponentEntry(
          nameCtrl: TextEditingController(text: 'Midterm'),
          weightCtrl: TextEditingController(text: '30'),
          dropLowestCtrl: TextEditingController(text: '0')),
        _ComponentEntry(
          nameCtrl: TextEditingController(text: 'Final'),
          weightCtrl: TextEditingController(text: '50'),
          dropLowestCtrl: TextEditingController(text: '0')),
      ];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final c in _components) {
      c.dispose();
    }
    super.dispose();
  }

  double get _totalWeight {
    double sum = 0;
    for (final c in _components) {
      sum += double.tryParse(c.weightCtrl.text) ?? 0;
    }
    return sum;
  }

  bool get _isValid =>
      _totalWeight > 99.5 && _totalWeight < 100.5 && _nameController.text.trim().isNotEmpty;

  void _addComponent() {
    setState(() {
      _components.add(_ComponentEntry(
        nameCtrl: TextEditingController(),
        weightCtrl: TextEditingController(text: '0'),
        dropLowestCtrl: TextEditingController(text: '0')));
    });
  }

  void _removeComponent(int index) {
    if (_components.length <= 1) return;
    setState(() {
      _components[index].dispose();
      _components.removeAt(index);
    });
  }

  void _save() {
    if (!_isValid) return;

    final components = _components.map((c) => GradeComponent(
      name: c.nameCtrl.text.trim(),
      weight: (double.tryParse(c.weightCtrl.text) ?? 0) / 100,
      dropLowest: int.tryParse(c.dropLowestCtrl.text) ?? 0)).toList();

    final scale = WeightedGradeScale(
      id: widget.existingScale?.id,
      name: _nameController.text.trim(),
      classId: widget.classId,
      components: components,
      rubricType: _rubricType);

    // Just return the scale — the caller (CreateAssessmentScreen) handles
    // persisting with the correct assessment ID and linked component IDs.
    Navigator.pop(context, scale);
  }

  /// Load components from a saved template.
  void _loadFromTemplate(BuildContext context, List<WeightedGradeScale> templates) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Choose Template',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ...templates.map((t) => ListTile(
              title: Text(t.name),
              subtitle: Text(
                t.components.map((c) => '${c.name} ${(c.weight * 100).toInt()}%').join(' + '),
                style: const TextStyle(fontSize: 12)),
              trailing: IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: AppTheme.error),
                onPressed: () async {
                  await context.read<WeightedGradeProvider>().deleteTemplate(t.name);
                  if (c.mounted) Navigator.pop(c);
                }),
              onTap: () {
                setState(() {
                  // Clear current components
                  for (final comp in _components) {
                    comp.dispose();
                  }
                  _components = t.components.map((c) => _ComponentEntry(
                    nameCtrl: TextEditingController(text: c.name),
                    weightCtrl: TextEditingController(text: '${(c.weight * 100).toInt()}'),
                    dropLowestCtrl: TextEditingController(text: '${c.dropLowest}'))).toList();
                  _rubricType = t.rubricType;
                });
                Navigator.pop(c);
              })),
            const SizedBox(height: 16),
          ])));
  }

  /// Save current weights as a reusable template.
  Future<void> _saveAsTemplate() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Save as Template'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Template name',
            hintText: 'e.g. Final Exam Weights')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, nameCtrl.text.trim()),
            child: Text('Save')),
        ]));

    if (name == null || name.isEmpty || !_isValid) return;

    final components = _components.map((c) => GradeComponent(
      name: c.nameCtrl.text.trim(),
      weight: (double.tryParse(c.weightCtrl.text) ?? 0) / 100,
      dropLowest: int.tryParse(c.dropLowestCtrl.text) ?? 0)).toList();

    final scale = WeightedGradeScale(
      name: _nameController.text.trim(),
      classId: widget.classId,
      components: components,
      rubricType: _rubricType);

    await context.read<WeightedGradeProvider>().saveTemplate(name, scale);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Template saved: $name'),
          backgroundColor: AppTheme.primaryGreen));
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalWeight = _totalWeight;
    final isValid = _isValid;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              // Title
              Text(
                'Weighted Grade Setup',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    // Name fields
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Name (English)',
                        hintText: 'e.g. Semester 1'),
                      onChanged: (_) => setState(() {})),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'e.g. First Semester')),
                    const SizedBox(height: 16),
                    // Load from template
                    Builder(
                      builder: (context) {
                        final templates = context.watch<WeightedGradeProvider>().templates;
                        if (templates.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _loadFromTemplate(context, templates),
                              icon: const Icon(Icons.bookmark_outline, size: 18),
                              label: Text('Load from Template')),
                            const SizedBox(height: 16),
                          ]);
                      }),
                    // Components
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Components',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16)),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: AppTheme.primaryGreen),
                          onPressed: _addComponent,
                          tooltip: 'Add component'),
                      ]),
                    const SizedBox(height: 8),
                    ..._components.asMap().entries.map((entry) {
                      final index = entry.key;
                      final component = entry.value;
                      return _ComponentCard(
                        component: component,
                        index: index,
                        canRemove: _components.length > 1,onRemove: () => _removeComponent(index),
                        onChanged: () => setState(() {}));
                    }),
                    const SizedBox(height: 16),
                    // Total weight indicator
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isValid
                            ? AppTheme.primaryGreen.withOpacity(0.08)
                            : AppTheme.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isValid
                              ? AppTheme.primaryGreen.withOpacity(0.3)
                              : AppTheme.error.withOpacity(0.3))),
                      child: Row(
                        children: [
                          Icon(
                            isValid ? Icons.check_circle : Icons.error,
                            color: isValid ? AppTheme.primaryGreen : AppTheme.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Weight',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isValid ? AppTheme.primaryGreen : AppTheme.error)),
                                Text(
                                  '${totalWeight.toStringAsFixed(0)}% / 100%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isValid ? AppTheme.primaryGreen : AppTheme.error)),
                              ])),
                        ])),
                    const SizedBox(height: 16),
                    // Example calculation preview
                    _ExamplePreview(
                      components: _components,
                      totalWeight: totalWeight),
                    const SizedBox(height: 20),
                    // Save buttons
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton(
                              onPressed: isValid ? _save : null,
                              child: Text(
                                'Save',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))))),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: isValid ? () => _saveAsTemplate() : null,
                            icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                            label: Text('Template'))),
                      ]),
                  ])),
            ]));
      });
  }
}

/// Internal representation of a component entry in the form.
class _ComponentEntry {
  final TextEditingController nameCtrl;
  final TextEditingController weightCtrl;
  final TextEditingController dropLowestCtrl;

  _ComponentEntry({
    required this.nameCtrl,
    required this.weightCtrl,
    required this.dropLowestCtrl,
  });

  void dispose() {
    nameCtrl.dispose();
    weightCtrl.dispose();
    dropLowestCtrl.dispose();
  }
}

/// Card for a single component entry.
class _ComponentCard extends StatelessWidget {
  final _ComponentEntry component;
  final int index;
  final bool canRemove;final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _ComponentCard({
    required this.component,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${"Component"} ${index + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppTheme.lightText)),
              const Spacer(),
              if (canRemove)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: AppTheme.error),
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
            ]),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: component.nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                  onChanged: (_) => onChanged())),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: component.weightCtrl,
                  decoration: InputDecoration(
                    labelText: 'Weight %',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => onChanged())),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: component.dropLowestCtrl,
                  decoration: InputDecoration(
                    labelText: 'Drop N',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    hintText: '0'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => onChanged())),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)))),
        ]));
  }
}

/// Example calculation preview showing how scores would be weighted.
class _ExamplePreview extends StatelessWidget {
  final List<_ComponentEntry> components;
  final double totalWeight;const _ExamplePreview({
    required this.components,
    required this.totalWeight,
    });

  @override
  Widget build(BuildContext context) {
    if (totalWeight <= 0) return const SizedBox.shrink();

    // Example: student scores 80 on quiz, 70 on midterm, 60 on final
    final exampleScores = [80.0, 70.0, 60.0];

    double weightedSum = 0;
    final items = <Widget>[];

    for (int i = 0; i < components.length && i < exampleScores.length; i++) {
      final weight = (double.tryParse(components[i].weightCtrl.text) ?? 0) / 100;
      final score = exampleScores[i];
      final contribution = score * weight;
      weightedSum += contribution;

      items.add(Text(
        '  ${components[i].nameCtrl.text.isEmpty ? "?" : components[i].nameCtrl.text}: '
        '${score.toInt()}% × ${(weight * 100).toInt()}% = ${contribution.toStringAsFixed(1)}',
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace')));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.info.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.info.withOpacity(0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Example:',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          ...items,
          const Divider(height: 12),
          Text(
            '= ${weightedSum.toStringAsFixed(1)}% final grade',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ]));
  }
}
