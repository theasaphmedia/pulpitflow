import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/constants/app_links.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/sermon_model.dart';
import '../../../data/models/scripture_model.dart';
import '../../../data/services/preach_session_service.dart';
import '../../../data/services/scripture_service.dart';
import '../../../shared/state/editor_font_provider.dart';
import '../../../shared/state/sermon_provider.dart';
import '../../../shared/state/theme_provider.dart';
import '../../bible/screens/bible_reader_screen.dart';
import '../../bible/widgets/scripture_overlay.dart';

class PreachingScreen extends ConsumerStatefulWidget {
  final String sermonId;
  const PreachingScreen({super.key, required this.sermonId});

  @override
  ConsumerState<PreachingScreen> createState() => _PreachingScreenState();
}

class _PreachingScreenState extends ConsumerState<PreachingScreen> {
  final ScrollController _scrollController = ScrollController();

  late Stopwatch _sermonTimer;
  String _timerDisplay = '00:00';

  bool _themeSuggestionShown = false;
  double _fontSize = 22.0;
  bool _controlsVisible = true;
  double _scrollProgress = 0.0;

  // ── Scripture card verse-text preview cache ───────────────────────────────────
  // Keyed by "ref|translation". bible_api_service already layers offline
  // cache + mock fallback under this, so a pastor mid-sermon won't be left
  // staring at a spinner — worst case it falls back to the reference-only
  // look this screen used before.
  final Map<String, ScripturePassage?> _scripturePreviewCache = {};

  Future<ScripturePassage?> _loadScripturePreview(String ref, String translation) async {
    final key = '$ref|$translation';
    if (_scripturePreviewCache.containsKey(key)) {
      return _scripturePreviewCache[key];
    }
    final passage = await scriptureService.getPassage(ref, translation);
    _scripturePreviewCache[key] = passage;
    return passage;
  }

  // ── Block progress tracking ──────────────────────────────────────────────────
  int _currentBlockIndex = 0;
  int _totalContentBlocks = 0;

  // ── Projection ───────────────────────────────────────────────────────────────
  bool _projectionEnabled = false;
  String _sessionCode = '';

  // Throttles the network broadcast itself (the on-screen block counter
  // above still updates every frame). A fast scroll fling can fire the
  // scroll listener dozens of times per second — unthrottled, that blew
  // past Supabase Realtime's per-channel broadcast rate limit and left the
  // projection screen frozen on whatever the first message was, even
  // though the phone kept advancing normally. _broadcastSettleTimer
  // guarantees the final position always gets sent once scrolling stops,
  // even if it landed inside a throttle window.
  DateTime? _lastBroadcastAt;
  Timer? _broadcastSettleTimer;

  // Brightness cycles: dim → normal → bright
  static const _kBrightnessLevels = [0.5, 1.0, 1.4];
  int _brightnessLevelIndex = 1;
  double get _brightness => _kBrightnessLevels[_brightnessLevelIndex];

  static const _kFontKey = 'preaching_font_size';
  static const _kGoalKey = 'preaching_goal_minutes';

  // ── Timer goal ───────────────────────────────────────────────────────────────
  int _goalMinutes = 0; // 0 = no goal set

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();

    _sermonTimer = Stopwatch()..start();
    _startTimer();
    _loadFontSize();
    _loadGoal();
    _checkThemeSuggestion();
    _scrollController.addListener(_updateScrollProgress);

    // Seed block count after first frame so the counter badge renders immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sermons = ref.read(sermonProvider).value;
      final sermon = sermons?.firstWhere(
        (s) => s.id == widget.sermonId,
        orElse: () => Sermon(title: ''),
      );
      if (sermon != null && mounted) {
        final count = sermon.blocks
            .where((b) => !(b.type == BlockType.text && b.content.trim().isEmpty))
            .length;
        setState(() => _totalContentBlocks = count);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollProgress);
    _scrollController.dispose();
    _broadcastSettleTimer?.cancel();
    _sermonTimer.stop();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Stop any active projection session when leaving the screen
    preachSessionService.stopSession();
    super.dispose();
  }

  // ── Font size ────────────────────────────────────────────────────────────────

  Future<void> _loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _fontSize = prefs.getDouble(_kFontKey) ?? 22.0);
  }

  Future<void> _saveFontSize(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFontKey, value);
  }

  // ── Timer goal ───────────────────────────────────────────────────────────────

  Future<void> _loadGoal() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _goalMinutes = prefs.getInt(_kGoalKey) ?? 0);
  }

  Future<void> _saveGoal(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGoalKey, value);
  }

  /// Returns a goal-aware color for the timer chip.
  /// Green = comfortably within goal, orange = within 3 min, red = over goal.
  Color _timerColor(PulpitColors colors) {
    if (_goalMinutes == 0) return colors.textSecondary;
    final elapsed = _sermonTimer.elapsed.inMinutes;
    if (elapsed > _goalMinutes) return const Color(0xFFEF4444);        // red
    if (elapsed >= _goalMinutes - 3) return const Color(0xFFF97316);   // orange
    return const Color(0xFF22C55E);                                     // green
  }

  // ── Brightness ───────────────────────────────────────────────────────────────

  // ignore: unused_element
  void _cycleBrightness() {
    HapticFeedback.selectionClick();
    setState(() {
      _brightnessLevelIndex =
          (_brightnessLevelIndex + 1) % _kBrightnessLevels.length;
    });
  }

  IconData get _brightnessIcon {
    switch (_brightnessLevelIndex) {
      case 0:
        return Icons.brightness_3_rounded;  // dim — crescent
      case 1:
        return Icons.brightness_5_rounded;  // normal — half sun
      case 2:
        return Icons.brightness_7_rounded;  // bright — full sun
      default:
        return Icons.brightness_5_rounded;
    }
  }

  // ── Scroll progress ──────────────────────────────────────────────────────────

  void _updateScrollProgress() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final progress = (_scrollController.offset / max).clamp(0.0, 1.0);
    if ((progress - _scrollProgress).abs() > 0.004) {
      // Compute current block index from progress
      final sermons = ref.read(sermonProvider).value;
      final sermon = sermons?.firstWhere(
        (s) => s.id == widget.sermonId,
        orElse: () => Sermon(title: ''),
      );
      final contentBlocks = sermon?.blocks
          .where((b) => !(b.type == BlockType.text && b.content.trim().isEmpty))
          .toList() ?? [];
      final total = contentBlocks.length;
      final idx = total > 1
          ? (progress * (total - 1)).round().clamp(0, total - 1)
          : 0;
      setState(() {
        _scrollProgress = progress;
        _currentBlockIndex = idx;
        _totalContentBlocks = total;
      });

      final now = DateTime.now();
      final dueForBroadcast = _lastBroadcastAt == null ||
          now.difference(_lastBroadcastAt!) > const Duration(milliseconds: 150);
      _broadcastSettleTimer?.cancel();
      if (dueForBroadcast) {
        _lastBroadcastAt = now;
        _broadcastCurrentState();
      } else {
        _broadcastSettleTimer = Timer(
          const Duration(milliseconds: 200),
          _broadcastCurrentState,
        );
      }
    }
  }

  // ── Projection broadcast ─────────────────────────────────────────────────────

  /// Derives the "current" visible block from scroll position and broadcasts it.
  void _broadcastCurrentState() {
    if (!_projectionEnabled || !preachSessionService.isActive) return;

    final sermons = ref.read(sermonProvider).value;
    if (sermons == null) return;

    final sermon = sermons.firstWhere(
      (s) => s.id == widget.sermonId,
      orElse: () => Sermon(title: ''),
    );

    // Only broadcast non-empty blocks
    final visibleBlocks = sermon.blocks
        .where(
          (b) => !(b.type == BlockType.text && b.content.trim().isEmpty),
        )
        .toList();

    if (visibleBlocks.isEmpty) return;

    final total = visibleBlocks.length;
    final idx =
        (_scrollProgress * (total - 1)).round().clamp(0, total - 1);
    final block = visibleBlocks[idx];

    preachSessionService.broadcast(
      PreachPayload(
        sermonId: sermon.id,
        sermonTitle: sermon.title,
        seriesName: sermon.series,
        blockIndex: idx,
        totalBlocks: total,
        blockText: block.content,
        scriptureRef: block.scriptureRef,
        translation: block.translation ?? sermon.defaultTranslation,
        isScripture: block.type == BlockType.scripture,
        fontSize: _fontSize,
      ),
    );
  }

  // ── Timer ────────────────────────────────────────────────────────────────────

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      final elapsed = _sermonTimer.elapsed;
      final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
      if (mounted) setState(() => _timerDisplay = '$m:$s');
      return mounted;
    });
  }

  // ── Theme auto-suggestion ────────────────────────────────────────────────────

  void _checkThemeSuggestion() {
    if (_themeSuggestionShown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final brightness = MediaQuery.of(context).platformBrightness;
      final pulpitTheme = ref.read(themeProvider);
      final isDark =
          pulpitTheme == PulpitTheme.sacredDark ||
          pulpitTheme == PulpitTheme.graceDark;

      if (brightness == Brightness.dark && !isDark) {
        _showThemeSuggestion(suggestDark: true);
      } else if (brightness == Brightness.light && isDark) {
        _showThemeSuggestion(suggestDark: false);
      }
      _themeSuggestionShown = true;
    });
  }

  void _showThemeSuggestion({required bool suggestDark}) {
    final colors = PulpitColors.of(ref.read(themeProvider));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: colors.card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        duration: const Duration(seconds: 5),
        content: Row(
          children: [
            Icon(
              suggestDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: colors.accent,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                suggestDark
                    ? 'Switch to Dark theme for better visibility?'
                    : 'Switch to Light theme?',
                style: PulpitFonts.inter(
                  fontSize: 13,
                  color: colors.textPrimary,
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ref.read(themeProvider.notifier).setTheme(
                  suggestDark
                      ? PulpitTheme.sacredDark
                      : PulpitTheme.sacredLight,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Switch',
                  style: PulpitFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.background,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  void _toggleControls() {
    HapticFeedback.lightImpact();
    setState(() => _controlsVisible = !_controlsVisible);
  }

  void _openBibleReader() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BibleReaderScreen(onAddToSermon: _addVerseToSermon),
      ),
    );
  }

  void _openOverlay(String scriptureRef, String translation) {
    HapticFeedback.mediumImpact();
    showScriptureOverlay(
      context: context,
      reference: scriptureRef,
      translation: translation,
      onAddToSermon: _addVerseToSermon,
    );
  }

  Future<void> _addVerseToSermon(
    String scriptureRef,
    String translation,
  ) async {
    final sermons = ref.read(sermonProvider).value;
    if (sermons == null) return;

    final sermon = sermons.firstWhere(
      (s) => s.id == widget.sermonId,
      orElse: () => Sermon(title: 'Not Found'),
    );

    final newBlock = SermonBlock.scripture(
      scriptureRef,
      translation: translation,
    );
    final updated = sermon.copyWith(
      blocks: [...sermon.blocks, newBlock, SermonBlock.text('')],
    );
    await ref.read(sermonProvider.notifier).updateSermon(updated);

    if (mounted) {
      final colors = PulpitColors.of(ref.read(themeProvider));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$scriptureRef added to sermon',
            style: PulpitFonts.inter(color: colors.background),
          ),
          backgroundColor: colors.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _endSermon(Sermon sermon) async {
    HapticFeedback.mediumImpact();
    final colors = PulpitColors.of(ref.read(themeProvider));
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          MediaQuery.of(ctx).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mic_off_rounded,
                size: 30,
                color: colors.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'End Sermon',
              style: PulpitFonts.cormorantGaramond(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You preached for $_timerDisplay.',
              style: PulpitFonts.inter(
                fontSize: 14,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(ctx);
                  final updated = sermon.copyWith(
                    status: SermonStatus.preached,
                  );
                  await ref
                      .read(sermonProvider.notifier)
                      .updateSermon(updated);
                  if (mounted) {
                    await _showReflectionNotes(updated);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: _onAccent(colors.accent),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Mark as Preached & Exit',
                  style: PulpitFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  if (mounted) context.pop();
                },
                child: Text(
                  'Just Exit',
                  style: PulpitFonts.inter(
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reflection notes ─────────────────────────────────────────────────────────

  /// Shows a reflection notes sheet after marking a sermon as preached.
  /// Saves the notes, then exits the screen.
  Future<void> _showReflectionNotes(Sermon sermon) async {
    final colors = PulpitColors.of(ref.read(themeProvider));
    final notesCtrl = TextEditingController(text: sermon.notes ?? '');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.edit_note_rounded,
                      color: colors.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reflection Notes',
                        style: PulpitFonts.cormorantGaramond(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        'How did the sermon go?',
                        style: PulpitFonts.inter(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: notesCtrl,
                autofocus: true,
                maxLines: 5,
                style: PulpitFonts.inter(
                  fontSize: 14,
                  color: colors.textPrimary,
                  height: 1.6,
                ),
                decoration: InputDecoration(
                  hintText:
                      'What worked well? What would you do differently? '
                      'How did the congregation respond?',
                  hintStyle: PulpitFonts.inter(
                    fontSize: 13,
                    color: colors.textSecondary.withValues(alpha: 0.6),
                    height: 1.6,
                  ),
                  filled: true,
                  fillColor: colors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: colors.accent, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(ctx);
                        if (mounted) context.pop();
                      },
                      child: Text(
                        'Skip',
                        style: PulpitFonts.inter(
                          fontSize: 14,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () async {
                        HapticFeedback.mediumImpact();
                        final text = notesCtrl.text.trim();
                        if (text.isNotEmpty) {
                          final withNotes = sermon.copyWith(notes: text);
                          await ref
                              .read(sermonProvider.notifier)
                              .updateSermon(withNotes);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) context.pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: _onAccent(colors.accent),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Save & Exit',
                        style: PulpitFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    notesCtrl.dispose();
  }

  // ── Contrast helper ──────────────────────────────────────────────────────────

  static Color _onAccent(Color bg) =>
      bg.computeLuminance() > 0.4 ? const Color(0xFF1A1A1A) : Colors.white;

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sermonAsync = ref.watch(sermonProvider);
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);

    return sermonAsync.when(
      loading: () => _buildLoadingScreen(colors),
      error: (e, _) => _buildLoadingScreen(colors),
      data: (sermons) {
        final sermon = sermons.firstWhere(
          (s) => s.id == widget.sermonId,
          orElse: () => Sermon(title: 'Not Found'),
        );

        return Scaffold(
          backgroundColor: colors.background,
          body: ColorFiltered(
            colorFilter: ColorFilter.matrix([
              _brightness, 0, 0, 0, 0,
              0, _brightness, 0, 0, 0,
              0, 0, _brightness, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: Stack(
              children: [
                // ── Sermon content (tap toggles controls) ──────────────────
                GestureDetector(
                  onTap: _toggleControls,
                  child: _buildSermonContent(sermon, colors),
                ),

                // ── Timer chip — top-left, always visible ───────────────────
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  child: _buildTimerChip(colors),
                ),

                // ── Bible button — top-right, always visible ────────────────
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 16,
                  child: _buildBibleChip(colors),
                ),

                // ── Progress bar — segmented, always at very bottom ─────────
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildProgressBar(colors),
                ),

                // ── Block counter badge — fades with controls ───────────────
                if (_totalContentBlocks > 1)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 12,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      opacity: _controlsVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 280),
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: Center(
                          child: _buildBlockCounterBadge(colors),
                        ),
                      ),
                    ),
                  ),

                // ── Bottom pill — fades on tap ──────────────────────────────
                Positioned(
                  bottom: 16,
                  left: 60,
                  right: 60,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 280),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: _buildBottomPill(sermon, colors),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Progress bar ─────────────────────────────────────────────────────────────

  Widget _buildProgressBar(PulpitColors colors) {
    const barHeight = 3.0;
    final total = _totalContentBlocks;

    // Use segmented bar when ≤ 20 blocks, solid fill beyond that
    if (total > 1 && total <= 20) {
      return SizedBox(
        height: barHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segGap = 2.0;
            final totalGap = segGap * (total - 1);
            final segWidth = (constraints.maxWidth - totalGap) / total;
            return Row(
              children: List.generate(total, (i) {
                final filled = i <= _currentBlockIndex;
                return Padding(
                  padding: EdgeInsets.only(right: i < total - 1 ? segGap : 0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: segWidth,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: filled
                          ? colors.accent.withValues(alpha: 0.75)
                          : colors.border.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      );
    }

    // Fallback: smooth linear bar
    return SizedBox(
      height: barHeight,
      child: LinearProgressIndicator(
        value: _scrollProgress,
        minHeight: barHeight,
        backgroundColor: colors.border.withValues(alpha: 0.2),
        valueColor: AlwaysStoppedAnimation<Color>(
          colors.accent.withValues(alpha: 0.65),
        ),
      ),
    );
  }

  // ── Block counter badge ───────────────────────────────────────────────────────

  Widget _buildBlockCounterBadge(PulpitColors colors) {
    final current = _currentBlockIndex + 1;
    final total = _totalContentBlocks;
    final pct = total > 0 ? (current / total * 100).round() : 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.60),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.border.withValues(alpha: 0.35),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_rounded,
                size: 11,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Block $current of $total',
                style: PulpitFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 10,
                color: colors.border.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Text(
                '$pct%',
                style: PulpitFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen(PulpitColors colors) {
    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colors.accent),
            const SizedBox(height: 20),
            Text(
              'Preparing sermon...',
              style: PulpitFonts.cormorantGaramond(
                fontSize: 18,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Timer chip — top-left, always visible ───────────────────────────────────

  Widget _buildTimerChip(PulpitColors colors) {
    final timerCol = _projectionEnabled
        ? const Color(0xFF4CAF50)
        : _timerColor(colors);
    final isOverGoal = _goalMinutes > 0 &&
        _sermonTimer.elapsed.inMinutes > _goalMinutes;

    return _frostedChip(
      colors: colors,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_projectionEnabled) ...[
            // Pulsing green dot + cast icon when projecting
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(
              Icons.cast_connected_rounded,
              size: 11,
              color: Color(0xFF4CAF50),
            ),
            const SizedBox(width: 5),
          ] else if (isOverGoal) ...[
            Icon(
              Icons.warning_amber_rounded,
              size: 11,
              color: timerCol,
            ),
            const SizedBox(width: 4),
          ] else ...[
            Icon(
              Icons.timer_outlined,
              size: 11,
              color: timerCol.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            _timerDisplay,
            style: PulpitFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: timerCol,
              letterSpacing: 0.8,
            ),
          ),
          // Goal indicator: show "/MM:00" when goal is set
          if (_goalMinutes > 0 && !_projectionEnabled) ...[
            Text(
              '/${_goalMinutes.toString().padLeft(2, '0')}:00',
              style: PulpitFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: timerCol.withValues(alpha: 0.6),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Bible chip — top-right, always visible ───────────────────────────────────

  Widget _buildBibleChip(PulpitColors colors) {
    return GestureDetector(
      onTap: _openBibleReader,
      child: _frostedChip(
        colors: colors,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_rounded,
              size: 13,
              color: colors.accent,
            ),
            const SizedBox(width: 5),
            Text(
              'Bible',
              style: PulpitFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared frosted glass chip shell ─────────────────────────────────────────

  Widget _frostedChip({
    required PulpitColors colors,
    required Widget child,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.border.withValues(alpha: 0.4),
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  // ── Bottom pill — ← | ⚙ | End (frosted, toggles with controls) ─────────────

  Widget _buildBottomPill(Sermon sermon, PulpitColors colors) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colors.border.withValues(alpha: 0.45),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // ← Back
              _pillButton(
                icon: Icons.arrow_back_ios_rounded,
                label: 'Back',
                colors: colors,
                onTap: () => context.pop(),
              ),

              _pillDivider(colors),

              // ⚙ Settings
              _pillButton(
                icon: Icons.tune_rounded,
                label: 'Settings',
                colors: colors,
                onTap: () => _showPreachSettings(sermon, colors),
              ),

              _pillDivider(colors),

              // 🔴 End
              _pillButton(
                icon: Icons.mic_off_rounded,
                label: 'End',
                colors: colors,
                iconColor: colors.error,
                labelColor: colors.error,
                onTap: () => _endSermon(sermon),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    required PulpitColors colors,
    required VoidCallback onTap,
    Color? iconColor,
    Color? labelColor,
  }) {
    final ic = iconColor ?? colors.textSecondary;
    final lc = labelColor ?? colors.textSecondary;
    return GestureDetector(
      onTap: () {
        // Generalized here — covers Back/Settings/End in one place. End
        // gets the heavier tier since it exits the live preaching session;
        // Back/Settings are ordinary navigation.
        HapticFeedback.lightImpact();
        if (label == 'End') HapticFeedback.mediumImpact();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: ic),
            const SizedBox(height: 3),
            Text(
              label,
              style: PulpitFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: lc,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillDivider(PulpitColors colors) {
    return Container(
      width: 0.5,
      height: 28,
      color: colors.border.withValues(alpha: 0.5),
    );
  }

  // ── Preaching settings sheet ─────────────────────────────────────────────────

  void _showPreachSettings(Sermon sermon, PulpitColors colors) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      // Was a fixed, non-scrollable Column — fine until "Project to Screen"
      // is toggled on, which adds the code box + share-text and pushed
      // "Sermon Goal" off the bottom of the sheet on shorter phones
      // (reported: "BOTTOM OVERFLOWED BY 49 PIXELS" on the SM A125F).
      // isScrollControlled lets the sheet grow past the default ~half-screen
      // cap, and the SingleChildScrollView below means it scrolls instead of
      // hard-overflowing if content still exceeds that on very short screens.
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Preaching Settings',
                style: PulpitFonts.cormorantGaramond(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 24),

              // ── Font size ──────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.format_size_rounded,
                      size: 16,
                      color: colors.accent,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Font Size',
                      style: PulpitFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    // A−
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        final v = (_fontSize - 2).clamp(16.0, 40.0);
                        setState(() => _fontSize = v);
                        setSheet(() {});
                        _saveFontSize(v);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.border),
                        ),
                        child: Icon(
                          Icons.text_decrease_rounded,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_fontSize.toInt()}',
                      style: PulpitFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // A+
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        final v = (_fontSize + 2).clamp(16.0, 40.0);
                        setState(() => _fontSize = v);
                        setSheet(() {});
                        _saveFontSize(v);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.border),
                        ),
                        child: Icon(
                          Icons.text_increase_rounded,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Brightness ─────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      _brightnessIcon,
                      size: 16,
                      color: colors.accent,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Brightness',
                      style: PulpitFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    // Three level buttons
                    ...List.generate(3, (i) {
                      final labels = ['Dim', 'Normal', 'Bright'];
                      final isSelected = _brightnessLevelIndex == i;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _brightnessLevelIndex = i);
                          setSheet(() {});
                        },
                        child: Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colors.accent
                                : colors.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? colors.accent
                                  : colors.border,
                            ),
                          ),
                          child: Text(
                            labels[i],
                            style: PulpitFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? _onAccent(colors.accent)
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ── Project to screen ──────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _projectionEnabled
                        ? const Color(0xFF4CAF50)
                        : colors.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _projectionEnabled
                              ? Icons.cast_connected_rounded
                              : Icons.cast_rounded,
                          size: 16,
                          color: _projectionEnabled
                              ? const Color(0xFF4CAF50)
                              : colors.accent,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Project to Screen',
                          style: PulpitFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Transform.scale(
                          scale: 0.82,
                          child: Switch(
                            value: _projectionEnabled,
                            activeThumbColor: const Color(0xFF4CAF50),
                            onChanged: (val) async {
                              HapticFeedback.selectionClick();
                              if (val) {
                                final code =
                                    await preachSessionService.startSession();
                                setState(() {
                                  _projectionEnabled = true;
                                  _sessionCode = code;
                                });
                                setSheet(() {});
                                // Immediately send the current state
                                _broadcastCurrentState();
                              } else {
                                await preachSessionService.stopSession();
                                setState(() {
                                  _projectionEnabled = false;
                                  _sessionCode = '';
                                });
                                setSheet(() {});
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_projectionEnabled &&
                        _sessionCode.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.wifi_tethering_rounded,
                              size: 14,
                              color: Color(0xFF4CAF50),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Code: ',
                              style: PulpitFonts.inter(
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                            ),
                            Text(
                              _sessionCode,
                              style: PulpitFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: colors.accent,
                                letterSpacing: 4,
                              ),
                            ),
                            const Spacer(),
                            // Real share sheet — sends the full join link
                            // (buildProjectionJoinLink) so the projectionist
                            // taps a link instead of having the 6 characters
                            // read aloud and re-typed by hand.
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                SharePlus.instance.share(
                                  ShareParams(
                                    text:
                                        'Connect to the sermon projection: '
                                        '${buildProjectionJoinLink(_sessionCode)}',
                                  ),
                                );
                              },
                              child: Icon(
                                Icons.ios_share_rounded,
                                size: 16,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 14),
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Clipboard.setData(
                                  ClipboardData(text: _sessionCode),
                                );
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Code $_sessionCode copied',
                                      style: PulpitFonts.inter(
                                        color: colors.background,
                                      ),
                                    ),
                                    backgroundColor: colors.accent,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    margin: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      100,
                                    ),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: Icon(
                                Icons.copy_rounded,
                                size: 16,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Share the link or code with your projectionist',
                        style: PulpitFonts.inter(
                          fontSize: 11,
                          color: colors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Same-room handoff alternative to reading the code
                      // aloud — scan instead of type. Kept small/inline
                      // since the sheet is already scrollable (see the
                      // isScrollControlled fix above).
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.border),
                          ),
                          child: QrImageView(
                            data: buildProjectionJoinLink(_sessionCode),
                            size: 96,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ── Timer goal ─────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.flag_rounded,
                          size: 16,
                          color: colors.accent,
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sermon Goal',
                              style: PulpitFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: colors.textPrimary,
                              ),
                            ),
                            Text(
                              _goalMinutes == 0
                                  ? 'No goal set'
                                  : '$_goalMinutes min target',
                              style: PulpitFonts.inter(
                                fontSize: 11,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // −5 button
                        GestureDetector(
                          onTap: _goalMinutes > 0
                              ? () {
                                  HapticFeedback.selectionClick();
                                  final v =
                                      (_goalMinutes - 5).clamp(0, 90);
                                  setState(() => _goalMinutes = v);
                                  setSheet(() {});
                                  _saveGoal(v);
                                }
                              : null,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _goalMinutes > 0
                                  ? colors.background
                                  : colors.background.withValues(
                                      alpha: 0.5,
                                    ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.border),
                            ),
                            child: Icon(
                              Icons.remove_rounded,
                              size: 14,
                              color: _goalMinutes > 0
                                  ? colors.textSecondary
                                  : colors.textSecondary
                                      .withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 44,
                          child: Text(
                            _goalMinutes == 0
                                ? 'Off'
                                : '$_goalMinutes',
                            textAlign: TextAlign.center,
                            style: PulpitFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _goalMinutes == 0
                                  ? colors.textSecondary
                                  : colors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // +5 button
                        GestureDetector(
                          onTap: _goalMinutes < 90
                              ? () {
                                  HapticFeedback.selectionClick();
                                  final v = _goalMinutes == 0
                                      ? 15
                                      : (_goalMinutes + 5).clamp(5, 90);
                                  setState(() => _goalMinutes = v);
                                  setSheet(() {});
                                  _saveGoal(v);
                                }
                              : null,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colors.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.border),
                            ),
                            child: Icon(
                              Icons.add_rounded,
                              size: 14,
                              color: _goalMinutes < 90
                                  ? colors.textSecondary
                                  : colors.textSecondary
                                      .withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Color legend — only when goal is set
                    if (_goalMinutes > 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _goalDot(const Color(0xFF22C55E), 'On track'),
                          const SizedBox(width: 12),
                          _goalDot(
                            const Color(0xFFF97316),
                            'Within 3 min',
                          ),
                          const SizedBox(width: 12),
                          _goalDot(
                            const Color(0xFFEF4444),
                            'Over goal',
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 6),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _goalDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: PulpitFonts.inter(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Sermon content ───────────────────────────────────────────────────────────

  Widget _buildSermonContent(Sermon sermon, PulpitColors colors) {
    // ref.watch (not ref.read) so the preaching screen reflects a font
    // change made in Settings without needing to be re-opened — read()
    // only reflects the value at whatever moment this last happened to
    // rebuild for some other reason.
    final editorFont = ref.watch(editorFontProvider);
    return SingleChildScrollView(
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        28,
        MediaQuery.of(context).padding.top + 28,
        28,
        160, // room for bottom pill
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sermon.title,
            style: PulpitFonts.cormorantGaramond(
              fontSize: _fontSize + 10,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              height: 1.2,
            ),
          ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1, end: 0),
          const SizedBox(height: 8),
          Container(
            width: 48,
            height: 2,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(1),
              boxShadow: [
                BoxShadow(
                  color: colors.accent.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          ...sermon.blocks.asMap().entries.map((entry) {
            final index = entry.key;
            final block = entry.value;
            final delay = Duration(milliseconds: 100 + index * 50);

            if (block.type == BlockType.text) {
              return _buildTextBlock(block, colors, editorFont)
                  .animate()
                  .fadeIn(duration: 500.ms, delay: delay);
            } else {
              return _buildScriptureChip(
                    block,
                    sermon.defaultTranslation,
                    colors,
                  )
                  .animate()
                  .fadeIn(duration: 400.ms, delay: delay)
                  .scale(
                    begin: const Offset(0.95, 0.95),
                    end: const Offset(1, 1),
                  );
            }
          }),
        ],
      ),
    );
  }

  Widget _buildTextBlock(
    SermonBlock block,
    PulpitColors colors,
    EditorFont editorFont,
  ) {
    if (block.content.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        block.content,
        style: editorFont.bodyStyle(
          fontSize: _fontSize,
          color: colors.textPrimary,
          height: 1.9,
        ),
      ),
    );
  }

  /// Full-width "quoted passage" card — matches the editor's redesigned
  /// scripture block (see sermon_editor_screen.dart _buildInlineScriptureChip)
  /// so a scripture reads the same connected, manuscript-style way in both
  /// draft and preach mode, instead of the old floating reference-only pill.
  /// Verse text scales with the live font-size control so it stays legible
  /// at pulpit reading distance.
  Widget _buildScriptureChip(
    SermonBlock block,
    String defaultTranslation,
    PulpitColors colors,
  ) {
    final scriptureRef = block.scriptureRef ?? block.content;
    final translation = block.translation ?? defaultTranslation;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: GestureDetector(
        onTap: () => _openOverlay(scriptureRef, translation),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 18, 18),
          decoration: BoxDecoration(
            color: colors.chipBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border(
              left: BorderSide(color: colors.accent, width: 4),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.accent.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.format_quote_rounded,
                    size: (_fontSize - 4).clamp(14.0, 28.0),
                    color: colors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      scriptureRef,
                      style: PulpitFonts.inter(
                        fontSize: (_fontSize - 6).clamp(12.0, 30.0),
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      translation,
                      style: PulpitFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FutureBuilder<ScripturePassage?>(
                future: _loadScripturePreview(scriptureRef, translation),
                builder: (ctx, snap) {
                  final text = snap.data?.verses
                      .map((v) => v.text.trim())
                      .join(' ')
                      .trim();
                  if (text == null || text.isEmpty) {
                    // Loading / offline / unavailable — never leave the
                    // pulpit view blank; the reference alone is still
                    // fully usable, matching the screen's prior behavior.
                    return snap.connectionState == ConnectionState.waiting
                        ? SizedBox(
                            height: _fontSize,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.accent.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink();
                  }
                  return Text(
                    '“$text”',
                    style: PulpitFonts.cormorantGaramond(
                      fontSize: _fontSize,
                      fontStyle: FontStyle.italic,
                      color: colors.textPrimary,
                      height: 1.45,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
