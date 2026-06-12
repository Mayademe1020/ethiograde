import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../services/settings_provider.dart';
import '../../services/teacher_provider.dart';
import '../../services/backup_service.dart';
import '../../models/teacher.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final teachers = context.watch<TeacherProvider>();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Settings',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // Profile section
          SettingsSection(
            title: 'Profile',
            children: [
              SettingsTile(
                icon: Icons.person_outline,
                title: 'Teachers',
                subtitle: teachers.activeTeacherName.isEmpty
                    ? ('Not set — tap to add')
                    : '${teachers.activeTeacherName} (${teachers.teachers.length})',
                onTap: () => _manageTeachers(context, teachers),
              ),
              SettingsTile(
                icon: Icons.school_outlined,
                title: 'School',
                subtitle: settings.schoolName.isEmpty
                    ? ('Not set')
                    : settings.schoolName,
                onTap: () => _editSchool(context, settings),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Preferences section
          SettingsSection(
            title: 'Preferences',
            children: [
              SettingsTile(
                icon: Icons.grading_outlined,
                title: 'Default Grading Scale',
                subtitle: settings.defaultRubric,
                onTap: () => _selectRubric(context, settings),
              ),
              SettingsTile(
                icon: Icons.record_voice_over_outlined,
                title: 'Voice Feedback',
                subtitle: settings.voiceFeedbackModeLabel,
                onTap: () => _selectVoiceFeedback(context, settings),
              ),
              SettingsTile(
                icon: Icons.dark_mode_outlined,
                title: 'Dark Mode',
                trailing: Switch(
                  value: settings.darkMode,
                  onChanged: (_) => settings.toggleDarkMode(),
                ),
              ),
              SettingsTile(
                icon: Icons.camera_alt_outlined,
                title: 'Auto-Enhance Photos',
                trailing: Switch(
                  value: settings.autoEnhanceImages,
                  onChanged: (_) => settings.toggleAutoEnhance(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Data & Privacy section
          SettingsSection(
            title: 'Data & Privacy',
            children: [
              const StorageInfoTile(),
              SettingsTile(
                icon: Icons.upload_file_outlined,
                title: 'Export Backup',
                subtitle: 'Save encrypted data to file',
                onTap: () => _exportBackup(context),
              ),
              SettingsTile(
                icon: Icons.download_outlined,
                title: 'Import Backup',
                subtitle: 'Restore from backup file',
                onTap: () => _importBackup(context),
              ),
              SettingsTile(
                icon: Icons.lock_outline,
                title: 'Privacy Policy',
                onTap: () => _showPrivacyPolicy(context),
              ),
              SettingsTile(
                icon: Icons.delete_forever_outlined,
                title: 'Clear All Data',
                subtitle: 'Cannot be undone',
                onTap: () => _confirmClearData(context),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // About section
          SettingsSection(
            title: 'About',
            children: [
              SettingsTile(
                icon: Icons.info_outline,
                title: 'Version',
                subtitle: 'v${AppConstants.appVersion}',
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _manageTeachers(
    BuildContext context,
    TeacherProvider teachers,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Manage Teachers',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: teachers.teachers.isEmpty
                  ? const Center(
                      child: Text('No teachers yet. Tap + to add one.'),
                    )
                  : ListView.builder(
                      itemCount: teachers.teachers.length,
                      itemBuilder: (ctx, index) {
                        final teacher = teachers.teachers[index];
                        final isActive =
                            teacher.id == teachers.activeTeacher?.id;
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(teacher.name[0].toUpperCase()),
                          ),
                          title: Text(teacher.name),
                          subtitle: Text(teacher.role),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isActive)
                                IconButton(
                                  onPressed: () async {
                                    await teachers.setActive(teacher.id);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  },
                                  icon: const Icon(Icons.star_border),
                                  tooltip: 'Set as active',
                                ),
                              if (isActive)
                                const Icon(Icons.star, color: Colors.amber),
                              IconButton(
                                onPressed: () =>
                                    _confirmDelete(context, teachers, teacher),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                          onTap: () => _showTeacherForm(
                            context,
                            teachers,
                            existing: teacher,
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      _showTeacherForm(context, teachers),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Teacher'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTeacherForm(
    BuildContext context,
    TeacherProvider teachers, {
    Teacher? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final formKey = GlobalKey<FormState>();
    var role = existing?.role ?? 'teacher';

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                existing != null ? 'Edit Teacher' : 'Add Teacher',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                autofocus: true,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'teacher', label: Text('Teacher')),
                  ButtonSegment(value: 'admin', label: Text('Admin')),
                ],
                selected: {role},
                onSelectionChanged: (sel) {
                  role = sel.first;
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.pop(ctx, true);
                  },
                  child: Text(existing != null ? 'Update' : 'Add'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      final name = nameCtrl.text.trim();
      if (existing != null) {
        final updated = existing.copyWith(name: name, role: role);
        await teachers.updateTeacher(updated);
      } else {
        final teacher = Teacher(name: name, role: role);
        await teachers.addTeacher(teacher);
      }
      if (context.mounted && teachers.lastAddErrors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(teachers.lastAddErrors.first)),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    TeacherProvider teachers,
    Teacher teacher,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Teacher?'),
        content: Text('Remove "${teacher.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await teachers.deleteTeacher(teacher.id);
    }
  }

  Future<void> _editSchool(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final ctrl = TextEditingController(text: settings.schoolName);
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'School Name',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'School',
                prefixIcon: Icon(Icons.school_outlined),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
    if (result == true) {
      settings.updateSchoolInfo(name: ctrl.text.trim());
    }
  }

  Future<void> _selectRubric(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final rubrics = [
      ('moe_national', 'MoE National'),
      ('private_international', 'Private / International'),
      ('university', 'University'),
    ];
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text(
            'Default Grading Scale',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final (id, label) in rubrics)
            RadioListTile<String>(
              title: Text(label),
              value: id,
              groupValue: settings.defaultRubric,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
    if (result != null) {
      settings.setDefaultRubric(result);
    }
  }

  Future<void> _selectVoiceFeedback(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final modes = [
      (VoiceFeedbackMode.off, 'Off'),
      (VoiceFeedbackMode.scoreOnly, 'Score Only'),
      (VoiceFeedbackMode.scoreAndGrade, 'Score + Grade (Privacy Safe)'),
    ];
    final result = await showModalBottomSheet<VoiceFeedbackMode>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text(
            'Voice Feedback Mode',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final (mode, label) in modes)
            RadioListTile<VoiceFeedbackMode>(
              title: Text(label),
              value: mode,
              groupValue: settings.voiceFeedbackMode,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
    if (result != null) {
      settings.setVoiceFeedbackMode(result);
    }
  }

  Future<void> _exportBackup(BuildContext context) async {
    try {
      final path = await BackupService.instance.exportAllData();
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup saved to: $path')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'enc'],
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.first.path;
      if (filePath == null) return;

      final importResult = await BackupService.instance.importData(filePath);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${importResult.imported}, skipped ${importResult.skipped}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _showPrivacyPolicy(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Privacy'),
        content: const SingleChildScrollView(
          child: Text(
            'EthioGrade stores all data locally on your device. '
            'No data is sent to any server. '
            'Backups are encrypted with AES-256. '
            'You can clear all data at any time from Settings.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Data?'),
        content: const Text(
          'This will permanently delete all students, assessments, '
          'scan results, and settings. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _clearAllData(context);
    }
  }

  Future<void> _clearAllData(BuildContext context) async {
    try {
      final boxes = [
        'students',
        'assessments',
        'classes',
        'teachers',
        'settings_pii',
        'scan_results',
        'weighted_scales',
        'audit_trail',
        'grading_drafts',
      ];
      for (final name in boxes) {
        if (Hive.isBoxOpen(name)) {
          await Hive.box(name).clear();
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared')),
        );
        SystemNavigator.pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }
}

// ──── Reusable Settings Components ────

class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SettingsSection({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    indent: AppSpacing.md + 44 + AppSpacing.md,
                    endIndent: 0,
                    color: cs.outlineVariant,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        ),
        child: Icon(icon, size: 18, color: cs.onSurface),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 18)
              : null),
      onTap: onTap,
    );
  }
}

/// Storage usage tile — shows total disk used by Hive + scanned images.
class StorageInfoTile extends StatelessWidget {
  const StorageInfoTile({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StorageInfo>(
      future: _calculateStorage(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final subtitle = info == null
            ? 'Calculating...'
            : '${info.totalFormatted} used'
                  '${info.imageCount > 0 ? ' · ${info.imageCount} scanned images' : ''}';

        return ListTile(
          leading: Icon(Icons.storage_outlined, color: Colors.grey.shade600),
          title: const Text('Storage Usage'),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: info != null && info.totalBytes > 0
              ? SizedBox(
                  width: 48,
                  height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (info.totalBytes / (500 * 1024 * 1024)).clamp(
                        0.0,
                        1.0,
                      ),
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                        info.totalBytes > 200 * 1024 * 1024
                            ? AppTheme.primaryRed
                            : AppTheme.primaryGreen,
                      ),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  static Future<StorageInfo> _calculateStorage() async {
    int hiveBytes = 0;
    int imageBytes = 0;
    int imageCount = 0;

    try {
      final dir = await getApplicationDocumentsDirectory();

      for (final entity in dir.listSync(recursive: false)) {
        if (entity is File && entity.path.endsWith('.hive')) {
          hiveBytes += await entity.length();
        }
      }

      final imageDirs = ['${dir.path}/images', '${dir.path}/Pictures'];
      for (final imageDirPath in imageDirs) {
        final imageDir = Directory(imageDirPath);
        if (await imageDir.exists()) {
          await for (final entity in imageDir.list(recursive: true)) {
            if (entity is File &&
                (entity.path.endsWith('.jpg') ||
                    entity.path.endsWith('.jpeg') ||
                    entity.path.endsWith('.png'))) {
              imageBytes += await entity.length();
              imageCount++;
            }
          }
        }
      }

      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: false)) {
          if (entity is File &&
              (entity.path.endsWith('.jpg') ||
                  entity.path.endsWith('.jpeg') ||
                  entity.path.contains('enhanced_'))) {
            imageBytes += await entity.length();
            imageCount++;
          }
        }
      }
    } catch (e) {
      debugPrint('[Storage] Failed to calculate: $e');
    }

    return StorageInfo(
      hiveBytes: hiveBytes,
      imageBytes: imageBytes,
      imageCount: imageCount,
    );
  }
}

class StorageInfo {
  final int hiveBytes;
  final int imageBytes;
  final int imageCount;

  const StorageInfo({
    required this.hiveBytes,
    required this.imageBytes,
    required this.imageCount,
  });

  int get totalBytes => hiveBytes + imageBytes;

  String get totalFormatted {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
