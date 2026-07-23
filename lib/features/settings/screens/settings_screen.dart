import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/services/scripture_service.dart';
import '../../../shared/state/editor_font_provider.dart';
import '../../../shared/state/sermon_provider.dart';
import '../../../shared/state/theme_provider.dart';
import '../../../shared/widgets/pulpit_ui.dart';
import '../../export/services/sermon_backup_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _appVersion = '';
  String _defaultTranslation = 'KJV';
  double _preachingFontSize = 22.0;
  bool _exportingBackup = false;
  bool _importingBackup = false;

  static const _kFontKey = 'preaching_font_size';
  static const _kTranslationKey = 'default_translation';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadVersion();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _preachingFontSize = prefs.getDouble(_kFontKey) ?? 22.0;
      _defaultTranslation = prefs.getString(_kTranslationKey) ?? 'KJV';
    });
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _appVersion = '${info.version} (${info.buildNumber})');
  }

  Future<void> _saveFontSize(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFontKey, value);
    setState(() => _preachingFontSize = value);
  }

  Future<void> _saveTranslation(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTranslationKey, value);
    setState(() => _defaultTranslation = value);
  }

  @override
  Widget build(BuildContext context) {
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);
    final editorFont = ref.watch(editorFontProvider);

    return PulpitThemeScope(
      colors: colors,
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.background,
          elevation: 0,
          leading: IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              context.pop();
            },
            icon: Icon(
              Icons.arrow_back_ios_rounded,
              color: colors.textSecondary,
              size: 20,
            ),
            tooltip: 'Back',
          ),
          title: Text(
            'Settings',
            style: PulpitFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
        body: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Appearance ──────────────────────────────────────────────
              const PulpitSectionHeader(title: 'Appearance'),
              _settingsCard(
                colors,
                children: [
                  _row(
                    colors,
                    icon: Icons.palette_rounded,
                    title: 'Theme',
                    subtitle: _themeLabel(pulpitTheme),
                    onTap: () => _showThemePicker(context, colors, pulpitTheme),
                  ),
                  Divider(height: 1, color: colors.border),
                  _row(
                    colors,
                    icon: Icons.text_fields_rounded,
                    title: 'Editor Font',
                    subtitle: editorFont.displayName,
                    onTap: () => _showFontPicker(context, colors, editorFont),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Preaching ────────────────────────────────────────────────
              const PulpitSectionHeader(title: 'Preaching Mode'),
              _settingsCard(
                colors,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.text_fields_rounded,
                          size: 18,
                          color: colors.accent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Default Font Size',
                                style: PulpitFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textPrimary,
                                ),
                              ),
                              Text(
                                '${_preachingFontSize.toInt()}pt',
                                style: PulpitFonts.inter(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                        activeTrackColor: colors.accent,
                        inactiveTrackColor: colors.border,
                        thumbColor: colors.accent,
                        overlayColor: colors.accent.withValues(alpha: 0.15),
                      ),
                      child: Slider(
                        value: _preachingFontSize,
                        min: 16,
                        max: 40,
                        divisions: 12,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          _saveFontSize(v);
                        },
                      ),
                    ),
                  ),
                  _divider(colors),
                  _row(
                    colors,
                    icon: Icons.translate_rounded,
                    title: 'Default Translation',
                    subtitle: _defaultTranslation,
                    onTap: () => _showTranslationPicker(context, colors),
                  ),
                  _divider(colors),
                  // Projection (the 6-character-code screen-share to a
                  // second device/projector) was fully built and working
                  // end-to-end, but had zero tap target anywhere leading to
                  // it — same dead-route shape as VOTD history before it
                  // got wired in. Reachable from the auth screen too (for a
                  // projectionist with no account), but this is the
                  // in-app way to jump straight to it for testing on a
                  // second signed-in device.
                  _row(
                    colors,
                    icon: Icons.cast_connected_rounded,
                    title: 'Connect a Screen',
                    subtitle: 'Enter a code from a preacher\'s device',
                    last: true,
                    onTap: () => context.push('/projection'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Bible & Study ─────────────────────────────────────────────
              const PulpitSectionHeader(title: 'Bible & Study'),
              _settingsCard(
                colors,
                children: [
                  _row(
                    colors,
                    icon: Icons.history_rounded,
                    title: 'Clear Word Study History',
                    subtitle: 'Remove all recent searches',
                    onTap: () => _clearWordStudyHistory(colors),
                  ),
                  _divider(colors),
                  _divider(colors),
                  _row(
                    colors,
                    icon: Icons.cached_rounded,
                    title: 'Clear Scripture Cache',
                    subtitle: 'Fix a verse that looks wrong or outdated',
                    onTap: () => _clearScriptureCache(colors),
                  ),
                  _divider(colors),
                  _row(
                    colors,
                    icon: Icons.highlight_rounded,
                    title: 'Verse Highlights',
                    subtitle: 'Saved to your Supabase account',
                    last: true,
                    onTap: null,
                    trailing: Icon(
                      Icons.cloud_done_rounded,
                      size: 16,
                      color: colors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Data & Backup ─────────────────────────────────────────────
              const PulpitSectionHeader(title: 'Data & Backup'),
              _settingsCard(
                colors,
                children: [
                  _row(
                    colors,
                    icon: Icons.backup_rounded,
                    title: 'Export All Sermons',
                    subtitle: 'Save a .pulpitflow backup file',
                    onTap: _exportingBackup ? null : () => _exportBackup(colors),
                    trailing: _exportingBackup
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(colors.accent),
                            ),
                          )
                        : null,
                  ),
                  _divider(colors),
                  _row(
                    colors,
                    icon: Icons.restore_rounded,
                    title: 'Import Backup',
                    subtitle: 'Restore sermons from a backup file',
                    last: true,
                    onTap: _importingBackup ? null : () => _importBackup(colors),
                    trailing: _importingBackup
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(colors.accent),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── About ────────────────────────────────────────────────────
              const PulpitSectionHeader(title: 'About'),
              _settingsCard(
                colors,
                children: [
                  _row(
                    colors,
                    icon: Icons.info_outline_rounded,
                    title: 'Version',
                    subtitle: _appVersion.isEmpty ? '—' : _appVersion,
                    onTap: null,
                  ),
                  _divider(colors),
                  _row(
                    colors,
                    icon: Icons.favorite_rounded,
                    title: 'Built for the global pulpit',
                    subtitle: 'PulpitFlow © 2026',
                    last: true,
                    onTap: null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsCard(PulpitColors colors, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(children: children),
    );
  }

  Widget _row(
    PulpitColors colors, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool last = false,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap != null
          ? () {
              HapticFeedback.lightImpact();
              onTap();
            }
          : null,
      borderRadius: last
          ? const BorderRadius.vertical(bottom: Radius.circular(16))
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: PulpitFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: PulpitFonts.inter(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            trailing ??
                (onTap != null
                    ? Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.textSecondary.withValues(alpha: 0.5),
                      )
                    : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }

  Widget _divider(PulpitColors colors) => Divider(
        height: 1,
        indent: 48,
        color: colors.border.withValues(alpha: 0.6),
      );

  String _themeLabel(PulpitTheme t) {
    switch (t) {
      case PulpitTheme.sacredLight:
        return 'Sacred Light';
      case PulpitTheme.sacredDark:
        return 'Sacred Dark';
      case PulpitTheme.graceLight:
        return 'Grace Light';
      case PulpitTheme.graceDark:
        return 'Grace Dark';
    }
  }

  void _showThemePicker(
    BuildContext context,
    PulpitColors colors,
    PulpitTheme current,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => PulpitBottomSheet(
        title: 'Choose Theme',
        child: Column(
          children: PulpitTheme.values.map((t) {
            final selected = t == current;
            return InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(themeProvider.notifier).setTheme(t);
                Navigator.pop(context);
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? colors.accent.withValues(alpha: 0.1)
                      : colors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? colors.accent : colors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      t == PulpitTheme.sacredDark ||
                              t == PulpitTheme.graceDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      size: 16,
                      color: selected ? colors.accent : colors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _themeLabel(t),
                      style: PulpitFonts.inter(
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected ? colors.accent : colors.textPrimary,
                      ),
                    ),
                    if (selected) ...[
                      const Spacer(),
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: colors.accent,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showFontPicker(
    BuildContext context,
    PulpitColors colors,
    EditorFont current,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PulpitBottomSheet(
        title: 'Editor Font',
        // isScrollControlled above lets this sheet grow past the default
        // ~9/16-screen cap, but without scrollable:true the inner Column
        // has nothing to absorb the extra height — 6 font options each
        // with a sample line genuinely overflows on a 640dp-tall device
        // (SM-A125F). scrollable:true wraps it in SingleChildScrollView.
        scrollable: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose the typeface used in the sermon editor and preaching screen.',
              style: PulpitFonts.inter(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            ...EditorFont.values.map((f) {
              final selected = f == current;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(editorFontProvider.notifier).setFont(f);
                  Navigator.pop(context);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.accent.withValues(alpha: 0.08)
                        : colors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? colors.accent : colors.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    f.displayName,
                                    style: PulpitFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? colors.accent
                                          : colors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.border.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    f.category,
                                    style: PulpitFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textSecondary,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              f.sampleText,
                              style: f.bodyStyle(
                                fontSize: 13,
                                color: colors.textSecondary,
                                height: 1.4,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: colors.accent,
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showTranslationPicker(BuildContext context, PulpitColors colors) {
    const translations = ['KJV', 'NIV', 'ESV', 'NLT', 'AMP', 'NKJV'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => PulpitBottomSheet(
        title: 'Default Translation',
        child: Column(
          children: translations.map((t) {
            final selected = t == _defaultTranslation;
            return InkWell(
              onTap: () {
                _saveTranslation(t);
                Navigator.pop(context);
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? colors.accent.withValues(alpha: 0.1)
                      : colors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? colors.accent : colors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      t,
                      style: PulpitFonts.inter(
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? colors.accent : colors.textPrimary,
                      ),
                    ),
                    if (selected) ...[
                      const Spacer(),
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: colors.accent,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _exportBackup(PulpitColors colors) async {
    setState(() => _exportingBackup = true);
    try {
      final sermons = ref.read(sermonProvider).value ?? [];
      await SermonBackupService.exportBackup(sermons);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Export failed: $e',
              style: PulpitFonts.inter(color: colors.background),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingBackup = false);
    }
  }

  Future<void> _importBackup(PulpitColors colors) async {
    setState(() => _importingBackup = true);
    try {
      // Pick a JSON / .pulpitflow file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'pulpitflow'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        // User cancelled — nothing to do
        return;
      }

      final pickedFile = result.files.first;
      late String jsonStr;

      if (pickedFile.bytes != null) {
        // Web / memory-based path
        jsonStr = String.fromCharCodes(pickedFile.bytes!);
      } else if (pickedFile.path != null) {
        jsonStr = await File(pickedFile.path!).readAsString();
      } else {
        throw Exception('Could not read file');
      }

      final parsed = SermonBackupService.parseBackup(jsonStr);
      switch (parsed.status) {
        case BackupParseStatus.corrupt:
          throw Exception(
            'This file is corrupted or not a valid PulpitFlow backup',
          );
        case BackupParseStatus.unsupportedVersion:
          throw Exception(
            'This backup was made with a newer version of PulpitFlow — update the app first',
          );
        case BackupParseStatus.ok:
          if (parsed.sermons.isEmpty) {
            throw Exception('This backup file has no sermons in it');
          }
      }
      final sermons = parsed.sermons;

      final added = await ref.read(sermonProvider.notifier).importSermons(sermons);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              added == 0
                  ? 'All sermons already exist — nothing new imported'
                  : 'Imported $added sermon${added == 1 ? '' : 's'} successfully',
              style: PulpitFonts.inter(color: colors.background),
            ),
            backgroundColor: colors.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Import failed: $e',
              style: PulpitFonts.inter(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importingBackup = false);
    }
  }

  Future<void> _clearScriptureCache(PulpitColors colors) async {
    // The Bible API service caches verse/chapter text indefinitely with no
    // expiry — if a flaky network response ever got cached as a truncated
    // or wrong passage, it would otherwise be served forever with no way
    // for a pastor to fix it short of reinstalling the app. This wires the
    // existing (previously unused) clearOfflineCache() to an actual button.
    await scriptureService.clearOfflineCache();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Scripture cache cleared — verses will re-download as you use them',
            style: PulpitFonts.inter(color: colors.background),
          ),
          backgroundColor: colors.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _clearWordStudyHistory(PulpitColors colors) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('word_study_recent');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Word study history cleared',
            style: PulpitFonts.inter(color: colors.background),
          ),
          backgroundColor: colors.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
