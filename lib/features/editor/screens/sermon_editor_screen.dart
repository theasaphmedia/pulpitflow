import 'dart:async';
import 'dart:io';

import 'package:docx_to_text/docx_to_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:read_pdf_text/read_pdf_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion_pdf;

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/scripture_data.dart';
import '../../../core/constants/bible_books.dart';
import '../../../data/models/sermon_model.dart';
import '../../../data/models/scripture_model.dart';
import '../../../data/services/scripture_service.dart';
import '../../../features/bible/screens/bible_reader_screen.dart';
import '../../../features/bible/widgets/scripture_overlay.dart';
import '../../../features/export/services/sermon_export_service.dart';
import '../../../features/export/services/sermon_share_service.dart';
import '../../../shared/state/editor_font_provider.dart';
import '../../../shared/state/sermon_provider.dart';
import '../../../shared/state/theme_provider.dart';

class SermonEditorScreen extends ConsumerStatefulWidget {
  final String sermonId;
  /// When set, the editor will scroll to and flash this block after loading.
  /// Used by the concordance screen to deep-link into a specific scripture block.
  final String? highlightBlockId;

  const SermonEditorScreen({
    super.key,
    required this.sermonId,
    this.highlightBlockId,
  });

  @override
  ConsumerState<SermonEditorScreen> createState() => _SermonEditorScreenState();
}

class _SermonEditorScreenState extends ConsumerState<SermonEditorScreen> {
  late List<SermonBlock> _blocks;
  late String _title;
  late String _translation;
  bool _initialized = false;
  bool _saving = false;
  bool _savedRecently = false;
  Timer? _saveDebounce;

  // Built once from bibleBooks — matches e.g. "John 3:16", "1 Cor 13:4-7"
  static final RegExp _scriptureRefRegex = _buildScriptureRegex();

  bool _focusMode = false;

  // ── Word count goal ───────────────────────────────────────────────────────────
  int _wordCountGoal = 0; // 0 = no goal set
  static const _kWordGoalKey = 'editor_word_count_goal';

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  // ── Backspace-delete-scripture reliability ──────────────────────────────
  // FocusNode.onKeyEvent (below, in _buildInlineTextField) is the "correct"
  // way to catch backspace on an already-empty field, and it's kept as a
  // best-effort path since it does work on some setups (hardware keyboards
  // in particular). But on-device testing on Solomon's actual phone showed
  // it silently doing nothing — a known Android soft-keyboard gap: most
  // IMEs (Gboard, Samsung Keyboard) simply don't forward a key event when
  // there's genuinely nothing left in the field to delete, since from the
  // IME's point of view there's no local edit to make. No text change means
  // TextField.onChanged never fires either, so there is no reliable signal
  // at all from an empty field on many real devices.
  //
  // The fix (the same trick OTP/PIN-box inputs use for "backspace jumps to
  // the previous box"): seed the text block that immediately follows a
  // scripture insertion with a single invisible zero-width character
  // instead of leaving it truly empty. That guarantees backspace-at-start
  // always has something real to delete, which *does* reliably fire
  // onChanged on every keyboard. onChanged below detects that specific
  // transition and treats it as "delete the preceding scripture", then the
  // marker is stripped the instant real typing starts so it never becomes
  // visible or gets saved. _sentinelBlockIds tracks which controllers are
  // currently carrying the marker.
  static const String _kBackspaceSentinel = '​';
  final Set<String> _sentinelBlockIds = {};

  /// Strips the invisible marker before content is ever persisted —
  /// defense in depth in case any edge case leaves it in a controller.
  String _stripSentinel(String text) =>
      text.startsWith(_kBackspaceSentinel)
          ? text.substring(_kBackspaceSentinel.length)
          : text;

  /// Creates the TextEditingController and FocusNode for a text block that
  /// already exists in [_blocks] — the one and only place this setup should
  /// happen. This used to be duplicated three times (here via
  /// _buildInlineTextField, in _doInsertScripture, and in
  /// _syncControllers), and two of those three copies created a bare
  /// FocusNode() with no backspace handling at all. Since each site only
  /// creates a controller if none exists yet, whichever copy got there
  /// first "won" — and for the actual scripture-insert flow, it was always
  /// the bare one. That silently blocked real key handling from ever being
  /// attached, which is the actual reason backspace-delete-scripture never
  /// worked, not an IME limitation. Every insertion path now funnels
  /// through here so they can't drift out of sync again.
  void _ensureTextController(String blockId) {
    if (_controllers.containsKey(blockId)) return;
    final idx = _blocks.indexWhere((b) => b.id == blockId);
    if (idx < 0) return;
    final content = _blocks[idx].content;
    // Sentinel now seeds for ANY empty block with something before it, not
    // just ones sitting directly after a scripture. Narrowing it to
    // scripture-only left a real dead end: an already-orphaned empty block
    // (one whose preceding scripture was already removed some other way, or
    // one left over from before this fix existed) had nothing in front of
    // it worth deleting, so backspace correctly did nothing — but there was
    // also no way to clear the empty row itself. Now backspace on any
    // empty, non-first block either removes the scripture before it, or —
    // if there's no scripture there — removes the empty row itself and
    // hands focus back, so there's no longer a stuck gap that survives no
    // matter what you press.
    final isOrphanCandidate = content.isEmpty && idx > 0;
    if (isOrphanCandidate) _sentinelBlockIds.add(blockId);
    _controllers[blockId] = TextEditingController(
      text: isOrphanCandidate ? _kBackspaceSentinel : content,
    );
    _focusNodes[blockId] = FocusNode(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.backspace) {
          return KeyEventResult.ignored;
        }
        final ctrl = _controllers[blockId];
        if (ctrl == null ||
            !ctrl.selection.isCollapsed ||
            ctrl.selection.start != 0) {
          return KeyEventResult.ignored;
        }
        final i = _blocks.indexWhere((b) => b.id == blockId);
        if (i <= 0) return KeyEventResult.ignored;
        if (_blocks[i - 1].type == BlockType.scripture) {
          _deleteBlock(i - 1);
          return KeyEventResult.handled;
        }
        // Nothing but an empty gap either way — clear it and return focus
        // to whatever precedes it, deferred a tick so we're not disposing
        // this field's own controller mid-key-event.
        if (ctrl.text.isEmpty || ctrl.text == _kBackspaceSentinel) {
          _removeEmptyBlockAndFocusPrevious(blockId);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    _focusNodes[blockId]!.addListener(() {
      if (_focusNodes[blockId]!.hasFocus) {
        final i = _blocks.indexWhere((b) => b.id == blockId);
        if (i >= 0) setState(() => _activeCursorBlockIndex = i);
      }
    });
  }

  /// Deletes an empty text block and hands focus to whatever text block
  /// precedes it, if any. Deferred a tick since this is always called from
  /// inside that same block's own key-event/onChanged handler — deleting
  /// (and disposing) a controller while its own callback is still on the
  /// stack risks a "used after dispose" exception.
  void _removeEmptyBlockAndFocusPrevious(String blockId) {
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      final i = _blocks.indexWhere((b) => b.id == blockId);
      if (i < 0) return;
      final prev = i > 0 ? _blocks[i - 1] : null;
      _deleteBlock(i);
      if (prev != null && prev.type == BlockType.text) {
        _focusNodes[prev.id]?.requestFocus();
      }
    });
  }

  // ── Margin notes ──────────────────────────────────────────────────────────────
  /// One controller per block id for the private margin note TextField.
  final Map<String, TextEditingController> _noteControllers = {};
  /// Block ids whose note panel is currently expanded.
  final Set<String> _expandedNotes = {};
  int _activeCursorBlockIndex = 0;
  final ScrollController _scrollController = ScrollController();

  // ── Concordance highlight ────────────────────────────────────────────────────
  /// GlobalKey per block id — used to scroll to a specific block.
  final Map<String, GlobalKey> _blockKeys = {};
  /// Block id currently being highlighted (flashed from concordance deep-link).
  String? _highlightedBlockId;

  // ── Cross-reference suggestions ───────────────────────────────────────────────
  /// The scripture block id for which we're showing cross-ref suggestions.
  String? _xrefSourceBlockId;
  /// Suggested reference strings to show in the strip.
  List<String> _xrefSuggestions = [];

  // ── Scripture card verse-text preview cache ───────────────────────────────────
  /// Keyed by "ref|translation" so the inline scripture card can show the
  /// actual verse text (not just the reference) without re-fetching on every
  /// rebuild — the editor rebuilds often (every keystroke in other blocks).
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

  // ── Word count ────────────────────────────────────────────────────────────────

  /// Total word count across all text blocks (uses live controller text).
  int get _wordCount {
    var count = 0;
    for (final block in _blocks) {
      if (block.type == BlockType.text) {
        final text = _controllers[block.id]?.text ?? block.content;
        final trimmed = text.trim();
        if (trimmed.isNotEmpty) {
          count +=
              trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        }
      }
    }
    return count;
  }

  /// Estimated speaking time at 130 wpm.
  String get _speakingTime {
    final wc = _wordCount;
    if (wc == 0) return '';
    final minutes = (wc / 130).ceil();
    return '~$minutes min';
  }

  String get _wordCountLabel {
    final wc = _wordCount;
    if (wc == 0) return 'No text yet';
    final time = _speakingTime;
    final label = wc >= 1000
        ? '${(wc / 1000).toStringAsFixed(1)}k'
        : '$wc';
    return '$label words · $time';
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    if (_focusMode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _scrollController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    for (final c in _noteControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleFocusMode() {
    HapticFeedback.lightImpact();
    setState(() => _focusMode = !_focusMode);
    if (_focusMode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  // ── Word count goal helpers ───────────────────────────────────────────────────

  Future<void> _loadWordCountGoal() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _wordCountGoal = prefs.getInt(_kWordGoalKey) ?? 0);
    }
  }

  Future<void> _saveWordCountGoal(int goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kWordGoalKey, goal);
    setState(() => _wordCountGoal = goal);
  }

  void _showWordGoalPicker(BuildContext context, PulpitColors colors) {
    // Single choke point — covers both call sites (top progress bar and
    // keyboard toolbar) with one haptic instead of duplicating it.
    HapticFeedback.lightImpact();
    final options = [0, 300, 500, 800, 1000, 1500, 2000];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
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
                const SizedBox(height: 20),
                Text(
                  'Word Count Goal',
                  style: PulpitFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set a target to see your progress as you write.',
                  style: PulpitFonts.inter(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options.map((opt) {
                    final isSelected = opt == _wordCountGoal;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _saveWordCountGoal(opt);
                        Navigator.pop(sheetCtx);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colors.accent
                              : colors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? colors.accent
                                : colors.border,
                          ),
                        ),
                        child: Text(
                          opt == 0 ? 'No goal' : '$opt words',
                          style: PulpitFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? (colors.accent.computeLuminance() > 0.4
                                    ? const Color(0xFF1A1A1A)
                                    : Colors.white)
                                : colors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _initFromSermon(Sermon sermon) {
    if (_initialized) return;
    _loadWordCountGoal();
    if (sermon.title == 'Not Found') return;
    _blocks = List.from(sermon.blocks);
    if (_blocks.isEmpty) {
      _blocks = [SermonBlock.text('')];
    }
    _title = sermon.title;
    _translation = sermon.defaultTranslation;
    _initialized = true;
    _syncControllers();
    // Show drag-reorder hint once per install
    _maybeShowDragHint();
    // If opened from concordance, scroll to & flash the target block
    if (widget.highlightBlockId != null) {
      _scheduleHighlight(widget.highlightBlockId!);
    }
  }

  /// Scrolls to the target block and flashes a highlight ring for 1.8 s.
  void _scheduleHighlight(String blockId) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Set highlight colour so the chip renders the ring immediately.
      setState(() => _highlightedBlockId = blockId);
      // Give the list one more frame to actually lay out with the new key.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      final key = _blockKeys[blockId];
      if (key?.currentContext != null) {
        await Scrollable.ensureVisible(
          key!.currentContext!,
          alignment: 0.35,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        );
      }
      // Clear the highlight after 1.8 seconds
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (mounted) setState(() => _highlightedBlockId = null);
    });
  }

  static const _kDragHintShownKey = 'editor_drag_hint_shown';

  Future<void> _maybeShowDragHint() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool(_kDragHintShownKey) ?? false;
    if (shown || !mounted) return;
    await prefs.setBool(_kDragHintShownKey, true);
    // Wait one frame so the scaffold is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.drag_handle_rounded,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Long-press a block to drag and reorder',
                  style: PulpitFonts.inter(
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF374151),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    });
  }

  void _syncControllers() {
    for (int i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];
      if (block.type == BlockType.text) {
        _ensureTextController(block.id);
      }
      // Note controllers for ALL block types (text + scripture).
      if (!_noteControllers.containsKey(block.id)) {
        _noteControllers[block.id] =
            TextEditingController(text: block.note ?? '');
      }
    }
  }

  /// Called by ReorderableListView when the user drags a block to a new position.
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      // ReorderableListView passes newIndex as if the item is already removed;
      // adjust downward when moving forward in the list.
      if (newIndex > oldIndex) newIndex--;
      final block = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, block);
      _activeCursorBlockIndex = newIndex;
    });
    _saveAfterDelay();
  }

  void _saveAfterDelay() {
    // Debounced: every keystroke re-arms this timer instead of stacking up
    // an independent 800ms save for each character typed. Without the
    // cancel(), fast typing spawned dozens of overlapping autosaves — each
    // doing a full local write + background Supabase upsert — which is what
    // caused the "Saving… / Saved" badge to flicker erratically while
    // typing and hammered the network with redundant writes.
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      final sermon = ref.read(singleSermonProvider(widget.sermonId));
      if (sermon != null && mounted) {
        _autoSave(sermon);
      }
    });
  }

  Future<void> _autoSave(Sermon original) async {
    if (!_initialized) return;
    for (int i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];
      if (block.type == BlockType.text && _controllers.containsKey(block.id)) {
        // Defense in depth: the invisible backspace-delete marker (see
        // _kBackspaceSentinel) should always be stripped from onChanged
        // before this runs, but never persist it either way.
        _blocks[i] = block.copyWith(
          content: _stripSentinel(_controllers[block.id]!.text),
        );
      }
    }
    setState(() => _saving = true);
    final updated = original.copyWith(
      title: _title,
      blocks: _blocks,
      defaultTranslation: _translation,
    );
    await ref.read(sermonProvider.notifier).updateSermon(updated);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() {
        _saving = false;
        _savedRecently = true;
      });
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _savedRecently = false);
      });
    }
  }

  void _insertScriptureAtCursor() {
    HapticFeedback.lightImpact();
    final pulpitTheme = ref.read(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PremiumScripturePicker(
        colors: colors,
        defaultTranslation: _translation,
        onInsert: (ref, translation) {
          _doInsertScripture(ref, translation);
        },
      ),
    );
  }

  // ── Cross-reference map ───────────────────────────────────────────────────────
  static const Map<String, List<String>> _kCrossRefs = {
    'John 3:16':       ['Romans 5:8', 'Ephesians 2:8-9', '1 John 4:9-10'],
    'Romans 8:28':     ['Jeremiah 29:11', 'Genesis 50:20', 'Philippians 4:6-7'],
    'Philippians 4:13':['Isaiah 40:31', '2 Corinthians 12:9', 'Ephesians 6:10'],
    'Jeremiah 29:11':  ['Romans 8:28', 'Psalm 32:8', 'Proverbs 16:9'],
    'Isaiah 40:31':    ['Philippians 4:13', 'Psalm 27:14', '2 Corinthians 4:16'],
    'Psalm 23:1':      ['John 10:11', 'Hebrews 13:5', 'Psalm 27:1'],
    'Proverbs 3:5-6':  ['Psalm 37:5', 'Isaiah 26:3', 'Proverbs 16:3'],
    'Romans 5:1':      ['John 5:24', 'Romans 8:1', 'Colossians 1:20'],
    'Ephesians 2:8':   ['Romans 6:23', 'Titus 3:5', 'Galatians 2:16'],
    'Hebrews 11:1':    ['Romans 4:20-21', '2 Corinthians 5:7', 'Mark 11:24'],
    'Matthew 6:33':    ['Psalm 37:4', 'Luke 12:31', 'Colossians 3:1-2'],
    'Joshua 1:9':      ['Deuteronomy 31:6', 'Isaiah 41:10', 'Psalm 27:1'],
    'Romans 8:38-39':  ['John 10:28-29', 'Psalm 139:7-10', 'Ephesians 3:17-19'],
    'Psalm 46:1':      ['Nahum 1:7', 'Isaiah 25:4', 'Proverbs 18:10'],
    '2 Timothy 1:7':   ['Romans 8:15', 'John 14:27', '1 John 4:18'],
    'Galatians 2:20':  ['Romans 6:6', 'Colossians 3:3', '2 Corinthians 5:17'],
    'John 14:6':       ['Acts 4:12', '1 Timothy 2:5', 'Hebrews 7:25'],
    'Philippians 4:7': ['John 14:27', 'Isaiah 26:3', 'Colossians 3:15'],
    'Isaiah 41:10':    ['Joshua 1:9', 'Psalm 34:4', 'Romans 8:31'],
    'Psalm 119:105':   ['Proverbs 6:23', '2 Timothy 3:16-17', 'Hebrews 4:12'],
    'Romans 12:2':     ['Ephesians 4:23', 'Colossians 3:10', '2 Corinthians 3:18'],
    '2 Corinthians 5:17': ['Galatians 6:15', 'John 3:3', 'Ezekiel 36:26'],
    'John 15:5':       ['Galatians 2:20', 'Colossians 1:27', 'Philippians 4:13'],
    'Matthew 11:28':   ['Psalm 55:22', '1 Peter 5:7', 'Hebrews 4:9-10'],
    'Romans 1:16':     ['Mark 8:38', '1 Corinthians 1:18', '2 Timothy 1:8'],
    '1 Corinthians 13:4-7': ['Colossians 3:14', 'John 13:35', '1 John 4:8'],
    'Psalm 27:1':      ['Isaiah 41:10', 'Romans 8:31', 'Hebrews 13:6'],
    'Ephesians 6:10':  ['1 Peter 5:8', '2 Corinthians 10:4', 'James 4:7'],
    'James 1:5':       ['Proverbs 2:6', 'Colossians 2:3', '1 Kings 3:9'],
  };

  /// Returns up to 3 cross-reference suggestions for [ref], excluding refs
  /// already present in the sermon.
  List<String> _crossRefsFor(String ref) {
    // Normalise: strip verse range for lookup, try canonical form
    final canonical = ref.trim();
    final suggestions = _kCrossRefs[canonical] ?? [];
    // Also try book-level lookup (e.g. "John 3:16-17" → try "John 3:16")
    if (suggestions.isEmpty) {
      for (final key in _kCrossRefs.keys) {
        if (canonical.startsWith(key.split(':').first)) {
          return _kCrossRefs[key]!
              .where((r) => !_blocks.any((b) => b.scriptureRef == r))
              .take(3)
              .toList();
        }
      }
    }
    final existing = _blocks
        .where((b) => b.type == BlockType.scripture)
        .map((b) => b.scriptureRef ?? '')
        .toSet();
    return suggestions.where((r) => !existing.contains(r)).take(3).toList();
  }

  void _doInsertScripture(String ref, String translation) {
    String? insertedBlockId;
    setState(() {
      int insertAt = _activeCursorBlockIndex;
      if (insertAt < 0) {
        insertAt = 0;
      }
      if (insertAt >= _blocks.length) {
        insertAt = _blocks.length - 1;
      }

      final activeBlock = _blocks[insertAt];

      if (activeBlock.type == BlockType.text) {
        final controller = _controllers[activeBlock.id];
        final cursorPos =
            controller?.selection.baseOffset ?? activeBlock.content.length;
        final textBefore = activeBlock.content.substring(
          0,
          cursorPos.clamp(0, activeBlock.content.length),
        );
        final textAfter = activeBlock.content.substring(
          cursorPos.clamp(0, activeBlock.content.length),
        );

        _controllers[activeBlock.id]?.text = textBefore;
        _blocks[insertAt] = activeBlock.copyWith(content: textBefore);

        final scriptureBlock = SermonBlock.scripture(
          ref,
          translation: translation,
        );
        insertedBlockId = scriptureBlock.id;
        _blocks.insert(insertAt + 1, scriptureBlock);

        final afterBlock = SermonBlock.text(textAfter);
        _blocks.insert(insertAt + 2, afterBlock);
        _ensureTextController(afterBlock.id);

        _activeCursorBlockIndex = insertAt + 2;
        Future.delayed(const Duration(milliseconds: 100), () {
          _focusNodes[afterBlock.id]?.requestFocus();
        });
      } else {
        final scriptureBlock = SermonBlock.scripture(
          ref,
          translation: translation,
        );
        insertedBlockId = scriptureBlock.id;
        _blocks.insert(insertAt + 1, scriptureBlock);
        final afterBlock = SermonBlock.text('');
        _blocks.insert(insertAt + 2, afterBlock);
        _ensureTextController(afterBlock.id);
      }
    });
    _saveAfterDelay();

    // Trigger cross-reference suggestions after a short delay
    if (insertedBlockId != null) {
      final suggestions = _crossRefsFor(ref);
      if (suggestions.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) {
            setState(() {
              _xrefSourceBlockId = insertedBlockId;
              _xrefSuggestions = suggestions;
            });
          }
        });
      }
    }
  }

  void _deleteBlock(int index) {
    final block = _blocks[index];
    _controllers.remove(block.id)?.dispose();
    _focusNodes.remove(block.id)?.dispose();
    setState(() => _blocks.removeAt(index));
    _saveAfterDelay();
  }

  /// "Remove Scripture" from the chip's long-press menu. Every scripture
  /// block is inserted together with an empty text block right after it
  /// (see _doInsertScriptureAfter) purely to give the cursor somewhere
  /// natural to land. Plain _deleteBlock only ever removed the scripture
  /// itself, so that companion block was permanently orphaned — invisible,
  /// but still there, as an empty paragraph gap that never went away. This
  /// is the "placeholder ... even after deleted still remain" bug Solomon
  /// found. Clean the companion up too, but only while it's still genuinely
  /// empty — if the pastor already typed real content into it, leave it
  /// alone. (The backspace-shortcut delete path doesn't need this: there,
  /// the block that triggered the backspace *is* the companion, and it
  /// naturally survives and merges with whatever precedes the scripture —
  /// nothing is orphaned on that path.)
  void _deleteScriptureBlockAndCleanup(int index) {
    final block = _blocks[index];
    _controllers.remove(block.id)?.dispose();
    _focusNodes.remove(block.id)?.dispose();
    setState(() {
      _blocks.removeAt(index);
      if (index < _blocks.length) {
        final next = _blocks[index];
        final nextText = _controllers[next.id]?.text ?? next.content;
        if (next.type == BlockType.text && nextText.trim().isEmpty) {
          _controllers.remove(next.id)?.dispose();
          _focusNodes.remove(next.id)?.dispose();
          _blocks.removeAt(index);
        }
      }
    });
    _saveAfterDelay();
  }

  /// Opens the glassmorphism scripture overlay for a chip in the editor.
  /// The overlay's "Read full chapter in Bible" button forwards
  /// [_doInsertScripture] as the add-to-sermon callback so the user can
  /// drop more verses into the editor without leaving the reader.
  Future<void> _openScriptureOverlay(SermonBlock block) async {
    HapticFeedback.lightImpact();
    final ref = block.scriptureRef ?? block.content;
    final translation = block.translation ?? _translation;
    await showScriptureOverlay(
      context: context,
      reference: ref,
      translation: translation,
      onAddToSermon: _doInsertScripture,
    );
  }

  /// Opens the full Bible Reader without going through a chip first.
  Future<void> _openBibleReader() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BibleReaderScreen(
          initialTranslation: _translation,
          onAddToSermon: _doInsertScripture,
        ),
      ),
    );
  }

  /// Saves any pending changes then opens the native PDF share/print sheet.
  Future<void> _exportPdf(Sermon sermon) async {
    // Flush in-memory text to blocks before building the PDF.
    for (int i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];
      if (block.type == BlockType.text && _controllers.containsKey(block.id)) {
        // Defense in depth: the invisible backspace-delete marker (see
        // _kBackspaceSentinel) should always be stripped from onChanged
        // before this runs, but never persist it either way.
        _blocks[i] = block.copyWith(
          content: _stripSentinel(_controllers[block.id]!.text),
        );
      }
    }
    final updated = sermon.copyWith(title: _title, blocks: _blocks);
    await SermonExportService.exportToPdf(updated);
  }

  @override
  Widget build(BuildContext context) {
    final sermonAsync = ref.watch(sermonProvider);
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);
    return sermonAsync.when(
      loading: () => Scaffold(
        backgroundColor: colors.background,
        body: Center(child: CircularProgressIndicator(color: colors.accent)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: colors.background,
        body: Center(child: Text('Error: $e')),
      ),
      data: (sermons) {
        final sermon = sermons.firstWhere(
          (s) => s.id == widget.sermonId,
          orElse: () => Sermon(title: 'Not Found'),
        );
        _initFromSermon(sermon);

        if (_focusMode) {
          return Scaffold(
            backgroundColor: colors.background,
            resizeToAvoidBottomInset: true,
            body: Stack(
              children: [
                // Full-screen editor content
                SafeArea(
                  child: _initialized
                      ? _buildInlineEditor(context, sermon, colors)
                      : Center(
                          child: CircularProgressIndicator(color: colors.accent),
                        ),
                ),
                // Minimal exit button
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  right: 16,
                  child: GestureDetector(
                    onTap: _toggleFocusMode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colors.card.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colors.border,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.fullscreen_exit_rounded,
                            size: 15,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Exit Focus',
                            style: PulpitFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Word count pill at bottom
                Positioned(
                  bottom: MediaQuery.of(context).viewInsets.bottom +
                      MediaQuery.of(context).padding.bottom +
                      16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.card.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colors.border),
                      ),
                      child: Text(
                        _wordCountLabel,
                        style: PulpitFonts.inter(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: colors.background,
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: Column(
              children: [
                _buildTopBar(context, sermon, colors),
                // ── Word count goal progress bar ───────────────────────────
                if (_wordCountGoal > 0)
                  _WordCountGoalBar(
                    current: _wordCount,
                    goal: _wordCountGoal,
                    colors: colors,
                    onTap: () => _showWordGoalPicker(context, colors),
                  ),
                Expanded(
                  child: _initialized
                      ? _buildInlineEditor(context, sermon, colors)
                      : Center(
                          child: CircularProgressIndicator(
                            color: colors.accent,
                          ),
                        ),
                ),
                _buildKeyboardToolbar(context, colors),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    Sermon sermon,
    PulpitColors colors,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      child: Row(
        children: [
          // ── Back ──────────────────────────────────────────────────────────────
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              context.pop();
            },
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                Icons.arrow_back_ios_rounded,
                color: colors.textPrimary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // ── Title + save status ───────────────────────────────────────────────
          Expanded(
            child: GestureDetector(
              onTap: () => _showTitleEditor(context, sermon, colors),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _initialized ? _title : sermon.title,
                    style: PulpitFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.4),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: _saving
                        ? Row(
                            key: const ValueKey('saving'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 9,
                                height: 9,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Saving…',
                                style: PulpitFonts.inter(
                                  fontSize: 10,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          )
                        : _savedRecently
                            ? Row(
                                key: const ValueKey('saved'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.cloud_done_rounded,
                                    size: 11,
                                    color: colors.success,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Saved',
                                    style: PulpitFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: colors.success,
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(key: ValueKey('idle')),
                  ),
                  if (!_saving && !_savedRecently)
                    if (sermon.series != null && sermon.series!.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.collections_bookmark_rounded,
                            size: 10,
                            color: colors.accent,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              sermon.series!,
                              style: PulpitFonts.inter(
                                fontSize: 10,
                                color: colors.accent,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'Tap to rename',
                        style: PulpitFonts.inter(
                          fontSize: 10,
                          color: colors.textSecondary,
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // ── Status badge ──────────────────────────────────────────────────────
          _buildStatusBadge(context, sermon, colors),
          const SizedBox(width: 6),
          // ── Preach pill (primary CTA) ─────────────────────────────────────────
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              context.push('/sermons/${widget.sermonId}/preach');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_rounded, size: 14, color: colors.background),
                  const SizedBox(width: 4),
                  Text(
                    'Preach',
                    style: PulpitFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.background,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 2),
          // ── Overflow menu ─────────────────────────────────────────────────────
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded,
                color: colors.textSecondary, size: 22),
            padding: EdgeInsets.zero,
            color: colors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.border),
            ),
            onSelected: (value) {
              switch (value) {
                case 'translation':
                  HapticFeedback.lightImpact();
                  _showTranslationPicker(colors);
                  break;
                case 'checklist':
                  _showPrepChecklist(context, sermon, colors);
                  break;
                case 'coach':
                  _showSermonCoach(context, sermon, colors);
                  break;
                case 'focus':
                  _toggleFocusMode();
                  break;
                case 'bible':
                  HapticFeedback.lightImpact();
                  _openBibleReader();
                  break;
                case 'pdf':
                  HapticFeedback.lightImpact();
                  _exportPdf(sermon);
                  break;
                case 'share':
                  HapticFeedback.lightImpact();
                  _showShareSheet(context, sermon, colors);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'translation',
                child: _menuRow(
                  icon: Icons.translate_rounded,
                  label: 'Translation (${_initialized ? _translation : '…'})',
                  color: colors.accent,
                  textColor: colors.textPrimary,
                ),
              ),
              PopupMenuItem(
                value: 'checklist',
                child: _menuRow(
                  icon: Icons.checklist_rounded,
                  label: 'Prep Checklist',
                  color: colors.textSecondary,
                  textColor: colors.textPrimary,
                ),
              ),
              PopupMenuItem(
                value: 'coach',
                child: _menuRow(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Sermon Coach',
                  color: colors.accent,
                  textColor: colors.textPrimary,
                ),
              ),
              PopupMenuItem(
                value: 'focus',
                child: _menuRow(
                  icon: _focusMode
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  label: _focusMode ? 'Exit Focus Mode' : 'Focus Mode',
                  color: colors.textSecondary,
                  textColor: colors.textPrimary,
                ),
              ),
              PopupMenuItem(
                value: 'bible',
                child: _menuRow(
                  icon: Icons.menu_book_rounded,
                  label: 'Open Bible',
                  color: colors.accent,
                  textColor: colors.textPrimary,
                ),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: _menuRow(
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'Export PDF',
                  color: colors.textSecondary,
                  textColor: colors.textPrimary,
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: _menuRow(
                  icon: Icons.share_rounded,
                  label: 'Share Sermon',
                  color: colors.textSecondary,
                  textColor: colors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildStatusBadge(
    BuildContext context,
    Sermon sermon,
    PulpitColors colors,
  ) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (sermon.status) {
      case SermonStatus.draft:
        statusColor = colors.textSecondary;
        statusLabel = 'Draft';
        statusIcon = Icons.edit_outlined;
        break;
      case SermonStatus.ready:
        statusColor = Colors.green;
        statusLabel = 'Ready';
        statusIcon = Icons.check_circle_outline;
        break;
      case SermonStatus.preached:
        statusColor = colors.accent;
        statusLabel = 'Preached';
        statusIcon = Icons.mic_rounded;
        break;
    }

    return GestureDetector(
      onTap: () => _cycleStatus(context, sermon, colors),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon, size: 11, color: statusColor),
            const SizedBox(width: 4),
            Text(
              statusLabel,
              style: PulpitFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cycleStatus(
    BuildContext context,
    Sermon sermon,
    PulpitColors colors,
  ) async {
    SermonStatus next;
    switch (sermon.status) {
      case SermonStatus.draft:
        next = SermonStatus.ready;
        break;
      case SermonStatus.ready:
        next = SermonStatus.preached;
        break;
      case SermonStatus.preached:
        next = SermonStatus.draft;
        break;
    }

    // Confirm before marking as Preached — opens reflection notes prompt
    if (next == SermonStatus.preached) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: colors.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Mark as Preached?',
            style: PulpitFonts.cormorantGaramond(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          content: Text(
            'This will mark the sermon as preached. You can add reflection notes afterwards.',
            style:
                PulpitFonts.inter(fontSize: 14, color: colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(ctx, false);
              },
              child: Text(
                'Cancel',
                style: PulpitFonts.inter(color: colors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(ctx, true);
              },
              child: Text(
                'Yes, preached!',
                style: PulpitFonts.inter(
                  color: colors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final updated = sermon.copyWith(status: next);
    await ref.read(sermonProvider.notifier).updateSermon(updated);
    HapticFeedback.selectionClick();
  }

  // ignore: unused_element
  Widget _buildTranslationSelector(PulpitColors colors) {
    return GestureDetector(
      onTap: () => _showTranslationPicker(colors),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _initialized ? _translation : '',
              style: PulpitFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: colors.accent,
            ),
          ],
        ),
      ),
    );
  }

  /// Compact 32×32 icon button used in [_buildKeyboardToolbar].
  Widget _toolbarIcon(IconData icon, PulpitColors colors, {double rightMargin = 6}) {
    return Container(
      width: 32,
      height: 32,
      margin: EdgeInsets.only(right: rightMargin),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Icon(icon, size: 15, color: colors.textSecondary),
    );
  }

  /// Compact row used inside the overflow [PopupMenuButton] in [_buildTopBar].
  Widget _menuRow({
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(
          label,
          style: PulpitFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildInlineEditor(
    BuildContext context,
    Sermon sermon,
    PulpitColors colors,
  ) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title,
            style: PulpitFonts.cormorantGaramond(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 48,
            height: 2,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(height: 24),
          _buildInlineContent(colors),
          // ── Reflection notes ──────────────────────────────
          if (sermon.notes != null && sermon.notes!.isNotEmpty) ...[
            const SizedBox(height: 28),
            _buildNotesCard(context, sermon, colors),
          ] else if (sermon.status == SermonStatus.preached) ...[
            const SizedBox(height: 28),
            _buildAddNotesButton(context, sermon, colors),
          ],
        ],
      ),
    );
  }

  Widget _buildNotesCard(
    BuildContext context,
    Sermon sermon,
    PulpitColors colors,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
            child: Row(
              children: [
                Icon(Icons.edit_note_rounded, size: 16, color: colors.accent),
                const SizedBox(width: 8),
                Text(
                  'Reflection Notes',
                  style: PulpitFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.accent,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _editNotesDialog(context, sermon, colors),
                  child: Icon(
                    Icons.edit_rounded,
                    size: 15,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Text(
              sermon.notes!,
              style: PulpitFonts.inter(
                fontSize: 13,
                color: colors.textPrimary,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddNotesButton(
    BuildContext context,
    Sermon sermon,
    PulpitColors colors,
  ) {
    return GestureDetector(
      onTap: () => _editNotesDialog(context, sermon, colors),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colors.accent.withValues(alpha: 0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.edit_note_rounded, size: 16, color: colors.accent),
            const SizedBox(width: 8),
            Text(
              'Add Reflection Notes',
              style: PulpitFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNotesDialog(
    BuildContext context,
    Sermon sermon,
    PulpitColors colors,
  ) async {
    // Single choke point — covers both call sites (edit icon and the
    // "Add Reflection Notes" empty-state button).
    HapticFeedback.lightImpact();
    final ctrl = TextEditingController(text: sermon.notes ?? '');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            // autofocus below + a 5-line field pulls up the keyboard on a
            // small phone — needs to scroll, not just resize, or it
            // overflows (same class of bug as the title editor above).
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
              const SizedBox(height: 20),
              Text(
                'Reflection Notes',
                style: PulpitFonts.cormorantGaramond(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'How did the sermon go?',
                style: PulpitFonts.inter(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 5,
                style: PulpitFonts.inter(
                  fontSize: 14,
                  color: colors.textPrimary,
                  height: 1.6,
                ),
                decoration: InputDecoration(
                  hintText: 'What worked well? What would you do differently?',
                  hintStyle: PulpitFonts.inter(
                    fontSize: 13,
                    color: colors.textSecondary.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: colors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: colors.accent, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (sermon.notes != null && sermon.notes!.isNotEmpty)
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          await ref
                              .read(sermonProvider.notifier)
                              .updateSermon(sermon.copyWith(notes: null));
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: Text(
                          'Clear',
                          style: PulpitFonts.inter(
                            color: colors.error,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () async {
                        HapticFeedback.mediumImpact();
                        final text = ctrl.text.trim();
                        await ref
                            .read(sermonProvider.notifier)
                            .updateSermon(
                              sermon.copyWith(
                                notes: text.isEmpty ? null : text,
                              ),
                            );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor:
                            colors.accent.computeLuminance() > 0.4
                                ? const Color(0xFF1A1A1A)
                                : Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Save',
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
      ),
    );
    ctrl.dispose();
  }

  Widget _buildInlineContent(PulpitColors colors) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Don't show the default long-press drag handle overlay — we provide our own.
      buildDefaultDragHandles: false,
      onReorder: _onReorder,
      itemCount: _blocks.length,
      itemBuilder: (context, i) {
        final block = _blocks[i];
        return _buildDraggableBlockRow(i, block, colors);
      },
    );
  }

  /// Wraps each block in a Row that includes a subtle drag handle on the left.
  Widget _buildDraggableBlockRow(int index, SermonBlock block, PulpitColors colors) {
    final isText = block.type == BlockType.text;
    final hasNote = (block.note ?? '').isNotEmpty;
    final noteExpanded = _expandedNotes.contains(block.id);

    // Register a global key so _scheduleHighlight can call ensureVisible on it.
    final blockGlobalKey =
        _blockKeys.putIfAbsent(block.id, () => GlobalKey());

    return KeyedSubtree(
      key: ValueKey(block.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle — subtle dots icon, only draggable from this widget
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: isText ? 16.0 : 22.0,
                    right: 6,
                  ),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    size: 16,
                    color: colors.border,
                  ),
                ),
              ),
              // Block content takes the rest of the width.
              // KeyedSubtree lets _scheduleHighlight call Scrollable.ensureVisible
              // on this specific block without disrupting ReorderableListView.
              Expanded(
                child: KeyedSubtree(
                  key: blockGlobalKey,
                  child: isText
                      ? _buildInlineTextField(index, block, colors)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildInlineScriptureChip(index, block, colors),
                            // Cross-reference suggestion strip
                            if (_xrefSourceBlockId == block.id &&
                                _xrefSuggestions.isNotEmpty)
                              _buildXrefStrip(block.id, colors),
                          ],
                        ),
                ),
              ),
              // Note toggle button
              Padding(
                padding: EdgeInsets.only(top: isText ? 12.0 : 18.0, left: 4),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (noteExpanded) {
                        _expandedNotes.remove(block.id);
                      } else {
                        _expandedNotes.add(block.id);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: (noteExpanded || hasNote)
                          ? colors.accent.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      hasNote
                          ? Icons.comment_rounded
                          : Icons.add_comment_outlined,
                      size: 15,
                      color: (noteExpanded || hasNote)
                          ? colors.accent
                          : colors.border,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Expandable note panel
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: noteExpanded ? _buildNotePanel(block, colors) : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildNotePanel(SermonBlock block, PulpitColors colors) {
    _noteControllers.putIfAbsent(
      block.id,
      () => TextEditingController(text: block.note ?? ''),
    );
    return Container(
      margin: const EdgeInsets.only(left: 22, bottom: 6, right: 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDE7).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFFD600).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.sticky_note_2_outlined,
              size: 14,
              color: const Color(0xFFFFD600).withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _noteControllers[block.id],
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: PulpitFonts.inter(
                fontSize: 13,
                color: colors.textPrimary.withValues(alpha: 0.85),
                height: 1.6,
              ),
              decoration: InputDecoration(
                hintText: 'Add a private note or reminder for this block…',
                hintStyle: PulpitFonts.inter(
                  fontSize: 13,
                  color: colors.textSecondary.withValues(alpha: 0.5),
                  height: 1.6,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onChanged: (value) {
                final idx = _blocks.indexWhere((b) => b.id == block.id);
                if (idx < 0) return;
                setState(() {
                  _blocks[idx] = _blocks[idx].copyWith(
                    note: value.isEmpty ? null : value,
                  );
                });
                _saveAfterDelay();
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Cross-reference suggestion strip ──────────────────────────────────────────

  Widget _buildXrefStrip(String sourceBlockId, PulpitColors colors) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: Container(
        margin: const EdgeInsets.only(left: 4, top: 6, bottom: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: colors.accent.withValues(alpha: 0.20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(
                  Icons.link_rounded,
                  size: 12,
                  color: colors.accent.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 5),
                Text(
                  'Related passages',
                  style: PulpitFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: colors.accent.withValues(alpha: 0.7),
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _xrefSourceBlockId = null;
                      _xrefSuggestions = [];
                    });
                  },
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Suggestion chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _xrefSuggestions.map((xref) {
                return GestureDetector(
                  onTap: () {
                    // Insert the cross-reference as a new scripture block
                    final sermon = ref.read(singleSermonProvider(widget.sermonId));
                    if (sermon == null) return;
                    HapticFeedback.mediumImpact();
                    setState(() {
                      _xrefSourceBlockId = null;
                      _xrefSuggestions = [];
                    });
                    _doInsertScriptureAfter(sourceBlockId, xref, _translation);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colors.accent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 11,
                          color: colors.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          xref,
                          style: PulpitFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  /// Inserts a new scripture block immediately after the block with [afterBlockId].
  void _doInsertScriptureAfter(
      String afterBlockId, String ref, String translation) {
    setState(() {
      final idx = _blocks.indexWhere((b) => b.id == afterBlockId);
      if (idx < 0) return;
      final scriptureBlock = SermonBlock.scripture(ref, translation: translation);
      _blocks.insert(idx + 1, scriptureBlock);
      // Insert an empty text block after to keep flow. Deliberately NOT
      // pre-creating its controller/FocusNode here (as this used to) —
      // that bare FocusNode() had no backspace handling whatsoever, which
      // silently blocked _buildInlineTextField's own lazy setup from ever
      // running for this block (it only creates one if none exists yet).
      // That's the actual reason backspace-delete-scripture never worked —
      // not an IME limitation. Leaving this block controller-less lets
      // _buildInlineTextField set it up properly (sentinel marker + real
      // key handling included) the next time it's built.
      _blocks.insert(idx + 2, SermonBlock.text(''));
    });
    _saveAfterDelay();
    HapticFeedback.selectionClick();
  }

  Widget _buildInlineTextField(
    int index,
    SermonBlock block,
    PulpitColors colors,
  ) {
    _ensureTextController(block.id);

    // ref.watch (not ref.read) so this rebuilds immediately when the font
    // is changed in Settings while this editor screen is already alive in
    // the bottom-nav shell — read() only reflects the value at first build.
    final editorFont = ref.watch(editorFontProvider);
    return TextField(
      controller: _controllers[block.id],
      focusNode: _focusNodes[block.id],
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: editorFont.bodyStyle(
        fontSize: 17,
        color: colors.textPrimary,
        height: 1.75,
      ),
      decoration: InputDecoration(
        hintText: _blocks.length == 1 && index == 0
            ? 'Start writing your sermon here...'
            : null,
        hintStyle: editorFont.bodyStyle(
          fontSize: 17,
          color: colors.textSecondary.withValues(alpha: 0.5),
          height: 1.75,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        isDense: true,
      ),
      onTap: () => setState(() => _activeCursorBlockIndex = index),
      onChanged: (value) {
        if (_sentinelBlockIds.contains(block.id)) {
          if (value.isEmpty) {
            // The marker itself just got backspaced away — this IS the
            // "delete something" signal that onKeyEvent couldn't reliably
            // catch on this keyboard. Same branching as the onKeyEvent
            // fallback: delete the preceding scripture if there is one,
            // otherwise this row was never anything but an empty gap, so
            // clear it and hand focus back.
            _sentinelBlockIds.remove(block.id);
            final idx = _blocks.indexWhere((b) => b.id == block.id);
            if (idx > 0 && _blocks[idx - 1].type == BlockType.scripture) {
              _deleteBlock(idx - 1);
            } else {
              _removeEmptyBlockAndFocusPrevious(block.id);
            }
            return;
          }
          if (value != _kBackspaceSentinel) {
            // Real typing started — strip the invisible marker so it's
            // never part of the saved sermon, then carry on normally.
            _sentinelBlockIds.remove(block.id);
            final stripped = _stripSentinel(value);
            final ctrl = _controllers[block.id]!;
            ctrl.value = TextEditingValue(
              text: stripped,
              selection: TextSelection.collapsed(offset: stripped.length),
            );
            _detectAndEmbedOnSpace(index, block, stripped);
            _saveAfterDelay();
            return;
          }
          // value == the marker, unchanged — nothing to do yet.
          return;
        }
        _detectAndEmbedOnSpace(index, block, value);
        _saveAfterDelay();
      },
    );
  }

  /// Renders an inserted scripture as an inline "quoted passage" card rather
  /// than a floating chat-style pill — full width, a left accent bar like a
  /// pull-quote, and the actual verse text in the sermon's serif typeface so
  /// it reads as part of the manuscript instead of a disconnected tag.
  /// (Was: a small centered pill showing only the reference — user feedback:
  /// "feels so bogus, disconnected from the whole page and archaic".)
  Widget _buildInlineScriptureChip(
    int index,
    SermonBlock block,
    PulpitColors colors,
  ) {
    final isHighlighted = _highlightedBlockId == block.id;
    final ref = block.scriptureRef ?? block.content;
    final translation = block.translation ?? _translation;
    return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: GestureDetector(
            // Tap → preview the scripture in the glassmorphism overlay.
            // Long-press → open the chip options sheet (delete, etc).
            onTap: () => _openScriptureOverlay(block),
            onLongPress: () => _showChipOptions(index, block, colors),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 13),
              decoration: BoxDecoration(
                color: isHighlighted
                    ? colors.accent.withValues(alpha: 0.1)
                    : colors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border(
                  left: BorderSide(
                    color: colors.accent,
                    width: isHighlighted ? 4 : 3,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.accent.withValues(
                      alpha: isHighlighted ? 0.2 : 0.08,
                    ),
                    blurRadius: isHighlighted ? 16 : 6,
                    offset: const Offset(0, 2),
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
                        size: 15,
                        color: colors.accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ref,
                          style: PulpitFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.accent,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          translation,
                          style: PulpitFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: colors.accent,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: colors.textSecondary.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FutureBuilder<ScripturePassage?>(
                    future: _loadScripturePreview(ref, translation),
                    builder: (ctx, snap) {
                      final text = snap.data?.verses
                          .map((v) => v.text.trim())
                          .join(' ')
                          .trim();
                      if (text == null || text.isEmpty) {
                        // Still loading (or offline/unavailable) — keep the
                        // card's shape stable instead of collapsing to blank.
                        return Text(
                          snap.connectionState == ConnectionState.waiting
                              ? 'Loading passage…'
                              : ref,
                          style: PulpitFonts.cormorantGaramond(
                            fontSize: 16,
                            fontStyle: FontStyle.italic,
                            color: colors.textSecondary,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        );
                      }
                      return Text(
                        '“$text”',
                        style: PulpitFonts.cormorantGaramond(
                          fontSize: 17,
                          fontStyle: FontStyle.italic,
                          color: colors.textPrimary,
                          height: 1.45,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 280.ms, curve: Curves.easeOut)
        .slideY(
          // easeOutBack overshoots slightly past 0 before settling back —
          // reads as the card physically dropping into place and coming to
          // rest, rather than just linearly easing into position.
          begin: 0.16,
          end: 0,
          duration: 480.ms,
          curve: Curves.easeOutBack,
        )
        .scaleXY(
          begin: 0.94,
          end: 1.0,
          duration: 480.ms,
          curve: Curves.easeOutBack,
        );
  }

  void _showChipOptions(int index, SermonBlock block, PulpitColors colors) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
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
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.menu_book_rounded, color: colors.accent, size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    block.scriptureRef ?? block.content,
                    style: PulpitFonts.cormorantGaramond(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.content_copy_rounded, color: colors.accent),
              title: Text(
                'Copy Reference',
                style: PulpitFonts.inter(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                '${block.scriptureRef ?? block.content} (${block.translation ?? _translation})',
                style: PulpitFonts.inter(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
              onTap: () async {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                final ref = block.scriptureRef ?? block.content;
                final translation = block.translation ?? _translation;
                await Clipboard.setData(
                  ClipboardData(text: '$ref ($translation)'),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Copied: $ref ($translation)',
                        style: PulpitFonts.inter(fontSize: 13),
                      ),
                      backgroundColor: colors.accent,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: colors.error),
              title: Text(
                'Remove Scripture',
                style: PulpitFonts.inter(
                  color: colors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(context);
                _deleteScriptureBlockAndCleanup(index);
              },
            ),
            ListTile(
              leading: Icon(Icons.close_rounded, color: colors.textSecondary),
              title: Text(
                'Cancel',
                style: PulpitFonts.inter(color: colors.textSecondary),
              ),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Auto-embed on space ──────────────────────────────────────────────────────

  /// Called on every keystroke. When the typed text ends with a complete
  /// scripture reference followed by a space, it instantly converts that
  /// reference into a scripture chip and moves the cursor to a new text block.
  void _detectAndEmbedOnSpace(int blockIndex, SermonBlock block, String value) {
    // Only trigger when the user just typed a space or newline
    if (!value.endsWith(' ') && !value.endsWith('\n')) return;

    final trimmed = value.trimRight();
    if (trimmed.isEmpty) return;

    final matches = _scriptureRefRegex.allMatches(trimmed).toList();
    if (matches.isEmpty) return;

    // Only embed if the reference sits at the very end of the typed text
    final lastMatch = matches.last;
    if (lastMatch.end != trimmed.length) return;

    // Build the normalised reference string
    final bookRaw = lastMatch.group(1)!;
    final book = _normaliseBookName(bookRaw);
    final chap = lastMatch.group(2)!;
    final verseNum = lastMatch.group(3)!;
    final endVerse = lastMatch.group(4);
    final scriptureRef = endVerse != null
        ? '$book $chap:$verseNum-$endVerse'
        : '$book $chap:$verseNum';

    // Text that remains in the current block (before the reference)
    final textBefore = trimmed.substring(0, lastMatch.start).trimRight();

    // Update the controller so the ref disappears from the text block
    final ctrl = _controllers[block.id]!;
    ctrl.value = TextEditingValue(
      text: textBefore,
      selection: TextSelection.collapsed(offset: textBefore.length),
    );

    // Build the new blocks
    final chipBlock = SermonBlock.scripture(
      scriptureRef,
      translation: _translation,
    );
    final afterBlock = SermonBlock.text('');

    setState(() {
      _blocks[blockIndex] = block.copyWith(content: textBefore);
      _blocks.insert(blockIndex + 1, chipBlock);
      _blocks.insert(blockIndex + 2, afterBlock);
      _activeCursorBlockIndex = blockIndex + 2;
    });

    _syncControllers();

    // Move focus to the blank block so the pastor can keep typing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNodes.containsKey(afterBlock.id)) {
        _focusNodes[afterBlock.id]!.requestFocus();
      }
    });

    _saveAfterDelay();

    // Brief confirmation — clears any previous snackbar first
    if (mounted) {
      final colors = PulpitColors.of(ref.read(themeProvider));
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 14,
                color: _onAccent(colors.accent),
              ),
              const SizedBox(width: 8),
              Text(
                '$scriptureRef embedded',
                style: PulpitFonts.inter(
                  fontSize: 13,
                  color: _onAccent(colors.accent),
                ),
              ),
            ],
          ),
          backgroundColor: colors.accent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  // ── Smart Paste ─────────────────────────────────────────────────────────────

  /// Builds a regex that matches any scripture reference using the real
  /// bibleBooks list, e.g. "John 3:16", "1 Cor 13:4–7", "Romans 8:28-30".
  static RegExp _buildScriptureRegex() {
    final bookPatterns = bibleBooks.map((b) {
      // Escape any regex special chars in the name
      final escaped = RegExp.escape(b.name);
      final abbrPatterns = b.abbreviations
          .map((a) => RegExp.escape(a))
          .join('|');
      return '(?:$escaped|$abbrPatterns)';
    }).join('|');

    return RegExp(
      r'(?<!\w)' // not preceded by a word char
      '($bookPatterns)'
      r'\.?\s+(\d+):(\d+)(?:\s*[–\-]\s*(\d+))?'
      r'(?!\w)', // not followed by a word char
      caseSensitive: false,
      multiLine: true,
    );
  }

  /// Reads clipboard, detects scripture references, and splits the pasted
  /// content into a mix of plain-text blocks and scripture-chip blocks.
  Future<void> _smartPaste() async {
    HapticFeedback.lightImpact();
    final clipData = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = clipData?.text?.trim();
    if (raw == null || raw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Clipboard is empty',
              style: PulpitFonts.inter(color: Colors.white),
            ),
            backgroundColor: Colors.grey[700],
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      return;
    }

    _insertSmartSegmentedText(raw);
  }

  // ── Document import (PDF / DOCX) ──────────────────────────────────────────
  //
  // Reuses exactly the same scripture-detection/segmentation pipeline as
  // Smart Paste above — the only genuinely new part is getting text out of
  // a file the user picked, instead of out of the clipboard. Extracted
  // _insertSmartSegmentedText so both paths share one source of truth
  // instead of two copies of the same regex-splitting logic drifting apart.
  bool _importingDocument = false;

  Future<void> _importDocument() async {
    if (_importingDocument) return;
    HapticFeedback.lightImpact();

    // withData forces the picker to also load the file into memory as
    // bytes — required on web, where there's no filesystem path at all
    // (PlatformFile.path is always null there). Scoped to kIsWeb so the
    // already-tested native path-based flow below is untouched.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx'],
      withData: kIsWeb,
    );
    final file = result?.files.single;
    if (file == null) return;
    // file.name (e.g. "sermon.docx") works on every platform; file.path
    // is null on web, so extension detection can't rely on path alone.
    final ext = file.name.split('.').last.toLowerCase();

    setState(() => _importingDocument = true);
    try {
      String text;
      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null) {
          throw const FormatException('Could not read that file');
        }
        if (ext == 'pdf') {
          // read_pdf_text is a native-only plugin (Apache PDFBox/PDFKit) —
          // it has no web implementation, so PDF import on web goes through
          // Syncfusion's pure-Dart PDF library instead, which extracts text
          // from raw bytes on every platform including web.
          final doc = syncfusion_pdf.PdfDocument(inputBytes: bytes);
          text = syncfusion_pdf.PdfTextExtractor(doc).extractText();
          doc.dispose();
        } else if (ext == 'docx') {
          text = docxToText(bytes);
        } else {
          throw const FormatException('Unsupported file type');
        }
      } else {
        final path = file.path;
        if (path == null) {
          throw const FormatException('Could not read that file');
        }
        if (ext == 'pdf') {
          text = await ReadPdfText.getPDFtext(path);
        } else if (ext == 'docx') {
          final bytes = await File(path).readAsBytes();
          text = docxToText(bytes);
        } else {
          throw const FormatException('Unsupported file type');
        }
      }

      text = text.trim();
      if (text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No readable text found in that file',
                style: PulpitFonts.inter(color: Colors.white),
              ),
              backgroundColor: Colors.grey[700],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
        return;
      }

      _insertSmartSegmentedText(text, noRefMessage: 'Document imported');
    } catch (e) {
      if (kDebugMode) debugPrint('Document import failed: $e');
      if (mounted) {
        final colors = PulpitColors.of(ref.read(themeProvider));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not read that file — try a different PDF or Word doc',
              style: PulpitFonts.inter(color: Colors.white),
            ),
            backgroundColor: colors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importingDocument = false);
    }
  }

  /// Detects scripture references against the full bibleBooks list (same
  /// regex Smart Paste and the auto-embed-on-space feature use) and splits
  /// [raw] into alternating text/scripture-chip blocks inserted at the
  /// active cursor position.
  void _insertSmartSegmentedText(String raw, {String noRefMessage = 'Text pasted'}) {
    final matches = _scriptureRefRegex.allMatches(raw).toList();

    if (matches.isEmpty) {
      // No refs — just insert as a plain text block at cursor
      _insertPlainTextBlock(raw);
      _showPasteSnackbar(0, noRefMessage: noRefMessage);
      return;
    }

    // Build segments: alternate text / scripture ref
    final List<({String text, bool isRef})> segments = [];
    int cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) {
        final plain = raw.substring(cursor, m.start).trim();
        if (plain.isNotEmpty) segments.add((text: plain, isRef: false));
      }
      // Normalise ref: capitalise book name, format as "Book chap:verse"
      final bookRaw = m.group(1)!;
      final book = _normaliseBookName(bookRaw);
      final chap = m.group(2)!;
      final verse = m.group(3)!;
      final endVerse = m.group(4);
      final ref = endVerse != null
          ? '$book $chap:$verse-$endVerse'
          : '$book $chap:$verse';
      segments.add((text: ref, isRef: true));
      cursor = m.end;
    }
    if (cursor < raw.length) {
      final trailing = raw.substring(cursor).trim();
      if (trailing.isNotEmpty) segments.add((text: trailing, isRef: false));
    }

    // Insert all segments starting at the active cursor block
    int insertIdx = _activeCursorBlockIndex;

    // If the active block is an empty text block, remove it first
    if (insertIdx < _blocks.length &&
        _blocks[insertIdx].type == BlockType.text &&
        (_controllers[_blocks[insertIdx].id]?.text.trim().isEmpty ?? true)) {
      setState(() => _blocks.removeAt(insertIdx));
    }

    for (final seg in segments) {
      final newBlock = seg.isRef
          ? SermonBlock.scripture(seg.text, translation: _translation)
          : SermonBlock.text(seg.text);
      setState(() {
        _blocks.insert(insertIdx, newBlock);
        insertIdx++;
      });
      if (!seg.isRef) _syncControllers();
    }

    // Add a trailing empty text block so the pastor can keep typing
    final trailing = SermonBlock.text('');
    setState(() {
      _blocks.insert(insertIdx, trailing);
    });
    _syncControllers();
    _saveAfterDelay();

    _showPasteSnackbar(matches.length, noRefMessage: noRefMessage);
  }

  void _insertPlainTextBlock(String text) {
    final block = SermonBlock.text(text);
    setState(() {
      _blocks.insert(_activeCursorBlockIndex, block);
    });
    _syncControllers();
    _saveAfterDelay();
  }

  String _normaliseBookName(String raw) {
    // Find matching book in bibleBooks list (case-insensitive)
    for (final book in bibleBooks) {
      if (book.name.toLowerCase() == raw.toLowerCase()) return book.name;
      if (book.abbreviations.any((a) => a.toLowerCase() == raw.toLowerCase())) {
        return book.name;
      }
    }
    // Capitalise first letter as fallback
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
  }

  void _showPasteSnackbar(int refCount, {PulpitColors? colors, String noRefMessage = 'Text pasted'}) {
    final pulpitColors = colors ?? PulpitColors.of(ref.read(themeProvider));
    final msg = refCount == 0
        ? noRefMessage
        : refCount == 1
            ? '1 scripture reference detected and embedded'
            : '$refCount scripture references detected and embedded';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              refCount > 0
                  ? Icons.menu_book_rounded
                  : Icons.content_paste_rounded,
              size: 16,
              color: _onAccent(pulpitColors.accent),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: PulpitFonts.inter(
                  fontSize: 13,
                  color: _onAccent(pulpitColors.accent),
                ),
              ),
            ),
          ],
        ),
        backgroundColor: pulpitColors.accent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildKeyboardToolbar(BuildContext context, PulpitColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Word count + scripture count (tap to set goal)
          GestureDetector(
            onTap: () => _showWordGoalPicker(context, colors),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _wordCountLabel,
                  style: PulpitFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
                Text(
                  '${_blocks.where((b) => b.type == BlockType.scripture).length}'
                  ' ref${_blocks.where((b) => b.type == BlockType.scripture).length == 1 ? '' : 's'}',
                  style: PulpitFonts.inter(
                    fontSize: 10,
                    color: colors.textSecondary.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // The icon cluster + CTA button used to sit in a plain Row with a
          // Spacer — fine with 3 icons, but adding a 4th (Import Document)
          // this session pushed the total past the available width on
          // narrower phones and clipped the CTA off-screen with a RenderFlex
          // overflow. Wrapping in a horizontally-scrollable, reversed
          // SingleChildScrollView means it can never overflow again no
          // matter how many icons get added later, and the reverse:true
          // keeps the most important action (Insert Scripture) in view by
          // default — the icons are one swipe away, not the other way round.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              physics: const ClampingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
          // ── Secondary actions (compact 32×32 icons) ──────────────────────
          // Copy all scripture references
          Builder(builder: (ctx) {
            final refs = _blocks
                .where((b) => b.type == BlockType.scripture)
                .map((b) => b.scriptureRef ?? b.content)
                .where((r) => r.isNotEmpty)
                .toList();
            if (refs.isEmpty) return const SizedBox.shrink();
            return Tooltip(
              message: 'Copy all scripture references',
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  final text = refs.join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            '${refs.length} ref${refs.length == 1 ? '' : 's'} copied',
                            style: PulpitFonts.inter(fontSize: 13, color: Colors.white),
                          ),
                        ],
                      ),
                      backgroundColor: const Color(0xFF374151),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: _toolbarIcon(Icons.format_list_bulleted_rounded, colors, rightMargin: 6),
              ),
            );
          }),
          // Keyword cloud
          Tooltip(
            message: 'Keyword cloud',
            child: GestureDetector(
              onTap: () => _showWordCloud(context, colors),
              child: _toolbarIcon(Icons.bubble_chart_rounded, colors, rightMargin: 6),
            ),
          ),
          // Smart Paste
          Tooltip(
            message: 'Smart Paste from clipboard',
            child: GestureDetector(
              onTap: _smartPaste,
              child: _toolbarIcon(Icons.content_paste_rounded, colors, rightMargin: 6),
            ),
          ),
          // Import PDF / DOCX
          Tooltip(
            message: 'Import PDF or Word document',
            child: GestureDetector(
              onTap: _importingDocument ? null : _importDocument,
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.border),
                ),
                child: _importingDocument
                    ? Center(
                        child: SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.accent,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.upload_file_rounded,
                        size: 15,
                        color: colors.textSecondary,
                      ),
              ),
            ),
          ),
          // Insert Scripture CTA
          GestureDetector(
                onTap: _insertScriptureAtCursor,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: colors.accent.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.menu_book_rounded, size: 15, color: _onAccent(colors.accent)),
                      const SizedBox(width: 6),
                      Text(
                        'Scripture',
                        style: PulpitFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _onAccent(colors.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .animate(onPlay: (controller) => controller.repeat())
              .shimmer(
                duration: 3000.ms,
                color: Colors.white.withValues(alpha: 0.15),
              ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Prep checklist ────────────────────────────────────────────────────────────

  void _showPrepChecklist(
    BuildContext context,
    Sermon sermon,
    PulpitColors colors,
  ) {
    HapticFeedback.lightImpact();

    // Compute checklist items from live state
    final wc = _wordCount;
    final scriptures = _blocks.where((b) => b.type == BlockType.scripture).length;
    final textBlocks = _blocks
        .where((b) => b.type == BlockType.text && (b.content.trim()).isNotEmpty)
        .toList();

    // "Has intro" = first text block ≥ 30 words
    final hasIntro = textBlocks.isNotEmpty &&
        textBlocks.first.content.trim().split(RegExp(r'\s+')).length >= 30;

    // "Has conclusion" = last text block ≥ 20 words and is different from intro
    final hasConclusion = textBlocks.length > 1 &&
        textBlocks.last.content.trim().split(RegExp(r'\s+')).length >= 20;

    final hasEnoughWords = wc >= 500;
    final hasEnoughScriptures = scriptures >= 3;
    final hasScheduledDate = sermon.scheduledDate != null;
    final isReadyOrPreached = sermon.status != SermonStatus.draft;

    final items = [
      _CheckItem(
        label: 'Introduction written',
        subtitle: 'First text block has ≥ 30 words',
        done: hasIntro,
      ),
      _CheckItem(
        label: '3+ scripture references',
        subtitle: '$scriptures scripture${scriptures == 1 ? '' : 's'} inserted',
        done: hasEnoughScriptures,
      ),
      _CheckItem(
        label: 'Conclusion written',
        subtitle: 'Final text block has ≥ 20 words',
        done: hasConclusion,
      ),
      _CheckItem(
        label: 'Word count ≥ 500',
        subtitle: '$wc words · ${_speakingTime.isEmpty ? 'very short' : _speakingTime}',
        done: hasEnoughWords,
      ),
      _CheckItem(
        label: 'Preaching date set',
        subtitle: hasScheduledDate
            ? _formatScheduledDate(sermon.scheduledDate!)
            : 'No date scheduled yet',
        done: hasScheduledDate,
      ),
      _CheckItem(
        label: 'Marked Ready or Preached',
        subtitle: 'Current status: ${sermon.status.name}',
        done: isReadyOrPreached,
      ),
    ];

    final doneCount = items.where((i) => i.done).length;
    final allDone = doneCount == items.length;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          // isScrollControlled removes the default 9/16-screen height cap,
          // so on a small device combined with larger accessibility text
          // sizes (or landscape) the fixed 6-item checklist could exceed
          // available height. SingleChildScrollView makes that safe without
          // changing how it looks on a normal-size screen.
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
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
                const SizedBox(height: 20),

                // Header row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sermon Prep Checklist',
                            style: PulpitFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            allDone
                                ? '🎉 You\'re ready to preach!'
                                : '$doneCount of ${items.length} complete',
                            style: PulpitFonts.inter(
                              fontSize: 13,
                              color: allDone
                                  ? const Color(0xFF22C55E)
                                  : colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Progress ring
                    _PrepProgress(
                      done: doneCount,
                      total: items.length,
                      colors: colors,
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                Divider(color: colors.border),
                const SizedBox(height: 8),

                // Checklist items
                ...items.map(
                  (item) => _PrepCheckRow(item: item, colors: colors),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Sermon Coach ──────────────────────────────────────────────────────────────

  /// Analyses the current sermon and surfaces targeted suggestions.
  void _showSermonCoach(
    BuildContext context,
    Sermon sermon,
    PulpitColors colors,
  ) {
    HapticFeedback.lightImpact();

    final wc = _wordCount;
    final scriptures =
        _blocks.where((b) => b.type == BlockType.scripture).toList();
    final textBlocks = _blocks
        .where((b) => b.type == BlockType.text && b.content.trim().isNotEmpty)
        .toList();

    // ── Build suggestions ─────────────────────────────────────────────────────
    final suggestions = <_CoachTip>[];

    // 1. Word count
    if (wc < 100) {
      suggestions.add(_CoachTip(
        icon: Icons.edit_outlined,
        color: const Color(0xFFEF4444),
        title: 'Very short sermon',
        body:
            'You\'ve written $wc words. A typical Sunday message runs 2,000–3,500 words. Consider expanding your main points.',
      ));
    } else if (wc < 500) {
      suggestions.add(_CoachTip(
        icon: Icons.edit_outlined,
        color: const Color(0xFFF97316),
        title: 'Growing — keep writing',
        body:
            '$wc words so far. You\'re building momentum. Aim for at least 1,000 words to cover your topic with depth.',
      ));
    } else if (wc >= 4000) {
      suggestions.add(_CoachTip(
        icon: Icons.timer_outlined,
        color: const Color(0xFFF97316),
        title: 'Long sermon detected',
        body:
            'At $wc words this will run 35+ minutes. Consider cutting one major point or moving it to a follow-up message.',
      ));
    } else {
      suggestions.add(_CoachTip(
        icon: Icons.check_circle_outline,
        color: const Color(0xFF22C55E),
        title: 'Good length',
        body:
            '$wc words — right in the sweet spot for a 15–30 min message.',
        isPositive: true,
      ));
    }

    // 2. Scripture balance
    if (scriptures.isEmpty) {
      suggestions.add(_CoachTip(
        icon: Icons.menu_book_rounded,
        color: const Color(0xFFEF4444),
        title: 'No scripture yet',
        body:
            'Every sermon should be grounded in at least one scripture. Use the + Scripture button to add your key passage.',
      ));
    } else if (scriptures.length == 1) {
      suggestions.add(_CoachTip(
        icon: Icons.menu_book_rounded,
        color: const Color(0xFFF97316),
        title: 'Consider a second scripture',
        body:
            'One scripture anchors the message. Adding a supporting verse from a different book enriches the teaching.',
      ));
    } else if (scriptures.length > 8) {
      suggestions.add(_CoachTip(
        icon: Icons.menu_book_rounded,
        color: const Color(0xFFF97316),
        title: 'Many scriptures (${scriptures.length})',
        body:
            'With ${scriptures.length} scriptures you risk rushing each one. Consider trimming to your 4–5 most essential passages.',
      ));
    }

    // 3. Block structure
    final lastTextBlock = textBlocks.lastOrNull;
    final hasIntro = textBlocks.isNotEmpty &&
        (textBlocks.first.content.length > 80);
    final hasConclusion = textBlocks.length >= 2 &&
        (lastTextBlock?.content.length ?? 0) > 80;

    if (!hasIntro && textBlocks.isNotEmpty) {
      suggestions.add(_CoachTip(
        icon: Icons.start_rounded,
        color: const Color(0xFFF97316),
        title: 'Strengthen the introduction',
        body:
            'Your first text block is short. A strong intro — a story, question, or striking fact — captures the congregation in the first 60 seconds.',
      ));
    }

    if (!hasConclusion && textBlocks.length >= 2) {
      suggestions.add(_CoachTip(
        icon: Icons.flag_rounded,
        color: const Color(0xFFF97316),
        title: 'Add a conclusion',
        body:
            'Your last text block is brief. Conclude with a clear call to action or application so the congregation leaves with something to do.',
      ));
    }

    // 4. Scripture placement — are all scriptures clumped together?
    if (scriptures.length >= 3) {
      final indices = scriptures
          .map((s) => _blocks.indexWhere((b) => b.id == s.id))
          .toList();
      final span = indices.last - indices.first;
      if (span <= 2) {
        suggestions.add(_CoachTip(
          icon: Icons.space_bar_rounded,
          color: const Color(0xFFF97316),
          title: 'Spread your scriptures',
          body:
              'All ${scriptures.length} scriptures are grouped together. Interspersing them between text blocks keeps the congregation engaged.',
        ));
      }
    }

    // 5. Scheduled date
    if (sermon.scheduledDate == null) {
      suggestions.add(_CoachTip(
        icon: Icons.calendar_today_rounded,
        color: colors.textSecondary,
        title: 'No preaching date set',
        body:
            'Add a scheduled date so this sermon appears in your Upcoming section and gets featured on the day you preach it.',
      ));
    }

    // 6. Status
    if (sermon.status == SermonStatus.draft && wc >= 800 && scriptures.isNotEmpty) {
      suggestions.add(_CoachTip(
        icon: Icons.check_circle_outline,
        color: colors.accent,
        title: 'Ready to mark as Ready?',
        body:
            'This sermon looks substantial. Tap the status badge in the top bar to mark it as Ready when you\'re satisfied.',
        isPositive: true,
      ));
    }

    // ── Show bottom sheet ─────────────────────────────────────────────────────
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetCtx).size.height * 0.78,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sermon Coach',
                        style: PulpitFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        '${suggestions.length} insight${suggestions.length == 1 ? '' : 's'}',
                        style: PulpitFonts.inter(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            // Suggestions list
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: suggestions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) =>
                    _CoachCard(tip: suggestions[i], colors: colors),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Keyword cloud ─────────────────────────────────────────────────────────────

  /// Common English stopwords to exclude from the keyword cloud.
  static const _kStopWords = {
    'the','a','an','and','or','but','in','on','at','to','for','of','with',
    'by','from','up','about','into','through','during','before','after',
    'above','below','between','out','off','over','under','again','further',
    'then','once','here','there','when','where','why','how','all','both',
    'each','few','more','most','other','some','such','no','nor','not','only',
    'own','same','so','than','too','very','can','will','just','don','should',
    'now','do','its','it','is','are','was','were','be','been','being',
    'have','has','had','having','he','she','they','we','you','i','me','him',
    'her','us','them','what','which','who','whom','this','that','these',
    'those','am','as','if','would','could','may','might','shall','must',
    'our','your','their','my','his','any','every','s','t','re','ve',
    'll','d','m','didn','doesnt','isnt','arent','wasnt','werent','wont','cant',
    'god','lord','said','unto','thee','thou','thy','thine','ye','hath','doth',
    'shalt','thus','also','let','say','says',
  };

  /// Extracts and ranks keywords from all text + scripture blocks.
  List<({String word, int count})> _extractKeywords() {
    final freq = <String, int>{};

    for (final block in _blocks) {
      final text = block.type == BlockType.scripture
          ? (block.scriptureRef ?? '')
          : block.content;
      // Tokenise: lowercase, strip punctuation, split on whitespace
      final words = text
          .toLowerCase()
          .replaceAll(RegExp(r"[^\w\s']"), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 4 && !_kStopWords.contains(w))
          .toList();
      for (final w in words) {
        freq[w] = (freq[w] ?? 0) + 1;
      }
    }

    // Sort by frequency desc, take top 40
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(40)
        .map((e) => (word: e.key, count: e.value))
        .toList();
  }

  void _showWordCloud(BuildContext context, PulpitColors colors) {
    HapticFeedback.lightImpact();
    final keywords = _extractKeywords();

    if (keywords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Write some content first to see your keyword cloud.',
            style: PulpitFonts.inter(fontSize: 13, color: Colors.white),
          ),
          backgroundColor: const Color(0xFF374151),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final maxCount = keywords.first.count;
    // Palette for chips — cycles through accent-derived shades
    final palette = [
      colors.accent,
      colors.accent.withValues(alpha: 0.75),
      colors.accent.withValues(alpha: 0.55),
      const Color(0xFF6366F1),
      const Color(0xFF8B5CF6),
      const Color(0xFF06B6D4),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetCtx).size.height * 0.72,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.bubble_chart_rounded,
                      size: 18,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Keyword Cloud',
                        style: PulpitFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        '${keywords.length} unique keywords found',
                        style: PulpitFonts.inter(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            // Cloud
            Flexible(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: keywords.asMap().entries.map((entry) {
                    final i = entry.key;
                    final kw = entry.value;
                    // Scale font 13–26 based on relative frequency
                    final fraction = maxCount > 1
                        ? (kw.count / maxCount)
                        : 1.0;
                    final fontSize = 13.0 + (fraction * 13.0);
                    final chipColor = palette[i % palette.length];
                    final bgAlpha = 0.10 + fraction * 0.12;

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        // Highlight in editor: find first block containing word
                        final word = kw.word;
                        for (final block in _blocks) {
                          if (block.type == BlockType.text &&
                              block.content.toLowerCase().contains(word)) {
                            final ctrl = _controllers[block.id];
                            if (ctrl != null) {
                              final idx = ctrl.text.toLowerCase().indexOf(word);
                              if (idx >= 0) {
                                ctrl.selection = TextSelection(
                                  baseOffset: idx,
                                  extentOffset: idx + word.length,
                                );
                              }
                            }
                            Navigator.pop(sheetCtx);
                            // Scroll to that block
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              final key = _blockKeys[block.id];
                              if (key?.currentContext != null) {
                                Scrollable.ensureVisible(
                                  key!.currentContext!,
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOutCubic,
                                  alignment: 0.3,
                                );
                              }
                            });
                            break;
                          }
                        }
                      },
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 200 + i * 15),
                        padding: EdgeInsets.symmetric(
                          horizontal: 10 + (fraction * 6),
                          vertical: 6 + (fraction * 3),
                        ),
                        decoration: BoxDecoration(
                          color: chipColor.withValues(alpha: bgAlpha),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: chipColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              kw.word,
                              style: PulpitFonts.inter(
                                fontSize: fontSize,
                                fontWeight: fraction >= 0.6
                                    ? FontWeight.w700
                                    : fraction >= 0.3
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                color: chipColor,
                              ),
                            ),
                            if (kw.count > 1) ...[
                              const SizedBox(width: 5),
                              Text(
                                '${kw.count}',
                                style: PulpitFonts.inter(
                                  fontSize: fontSize * 0.65,
                                  fontWeight: FontWeight.w600,
                                  color: chipColor.withValues(alpha: 0.65),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Share sheet ───────────────────────────────────────────────────────────────

  void _showShareSheet(
    BuildContext context,
    Sermon sermon,
    PulpitColors colors,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
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
                const SizedBox(height: 20),
                Text(
                  'Share Sermon',
                  style: PulpitFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Choose how you'd like to share this sermon.",
                  style: PulpitFonts.inter(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Option 1: Share Outline ────────────────────────────────
                _ShareOption(
                  colors: colors,
                  icon: Icons.format_list_bulleted_rounded,
                  title: 'Share Outline',
                  subtitle: 'Full sermon text — great for study or printing',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await SermonShareService.shareOutline(sermon);
                  },
                ),
                const SizedBox(height: 12),

                // ── Option 2: Copy as Outline ──────────────────────────────
                _ShareOption(
                  colors: colors,
                  icon: Icons.copy_all_rounded,
                  title: 'Copy as Outline',
                  subtitle: 'Paste anywhere — notes, email, messaging apps',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await SermonShareService.copyOutline(sermon);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Outline copied to clipboard',
                            style: PulpitFonts.inter(
                              color: colors.background,
                              fontSize: 13,
                            ),
                          ),
                          backgroundColor: colors.accent,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),

                // ── Option 3: Share for Social ─────────────────────────────
                _ShareOption(
                  colors: colors,
                  icon: Icons.auto_awesome_rounded,
                  title: 'Share for Social',
                  subtitle: 'Short post for Instagram, X, WhatsApp & more',
                  accent: true,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await SermonShareService.shareForSocial(sermon);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTitleEditor(
    BuildContext context,
    Sermon sermon,
    PulpitColors colors,
  ) {
    HapticFeedback.lightImpact();
    final titleCtrl = TextEditingController(text: _title);
    final seriesCtrl = TextEditingController(text: sermon.series ?? '');
    final tagsCtrl = TextEditingController(text: sermon.tags.join(', '));
    DateTime? pickedDate = sermon.scheduledDate;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Edit Sermon',
          style: PulpitFonts.cormorantGaramond(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        content: ConstrainedBox(
          // Bounded + scrollable so the dialog never overflows once the
          // autofocused title field pulls up the keyboard on small phones
          // (was a bare Column before — overflowed on 360dp-class devices).
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.6,
          ),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title field
            Text(
              'Title',
              style: PulpitFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              style: PulpitFonts.inter(color: colors.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: colors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.accent, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Series field
            Text(
              'Series (optional)',
              style: PulpitFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: seriesCtrl,
              style: PulpitFonts.inter(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g. Letters to the Church',
                hintStyle: PulpitFonts.inter(
                  color: colors.textSecondary.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: colors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.accent, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
                prefixIcon: Icon(
                  Icons.collections_bookmark_rounded,
                  size: 16,
                  color: colors.accent,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Tags field
            Text(
              'Tags (comma-separated)',
              style: PulpitFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: tagsCtrl,
              style: PulpitFonts.inter(
                color: colors.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. faith, grace, salvation',
                hintStyle: PulpitFonts.inter(
                  color: colors.textSecondary.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: colors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.accent, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
                prefixIcon: Icon(
                  Icons.label_outline_rounded,
                  size: 16,
                  color: colors.accent,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Scheduled date
            Text(
              'Scheduled Date (optional)',
              style: PulpitFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                final picked = await showDatePicker(
                  context: dialogContext,
                  initialDate: pickedDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: ColorScheme.light(
                        primary: colors.accent,
                        onPrimary: colors.background,
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) {
                  setDialogState(() => pickedDate = picked);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: pickedDate != null
                      ? colors.accent.withValues(alpha: 0.08)
                      : colors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: pickedDate != null
                        ? colors.accent.withValues(alpha: 0.5)
                        : colors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: pickedDate != null
                          ? colors.accent
                          : colors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        pickedDate != null
                            ? _formatScheduledDate(pickedDate!)
                            : 'Tap to set a preaching date',
                        style: PulpitFonts.inter(
                          fontSize: 14,
                          color: pickedDate != null
                              ? colors.accent
                              : colors.textSecondary,
                          fontWeight: pickedDate != null
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (pickedDate != null)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setDialogState(() => pickedDate = null);
                        },
                        child: Icon(
                          Icons.clear_rounded,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(dialogContext);
            },
            child: Text(
              'Cancel',
              style: PulpitFonts.inter(color: colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              final newTitle = titleCtrl.text.trim();
              final newSeries = seriesCtrl.text.trim().isEmpty
                  ? null
                  : seriesCtrl.text.trim();
              final newTags = tagsCtrl.text
                  .split(',')
                  .map((t) => t.trim().toLowerCase())
                  .where((t) => t.isNotEmpty)
                  .toList();
              if (newTitle.isNotEmpty) setState(() => _title = newTitle);
              Navigator.pop(dialogContext);
              // Persist changes via updateSermon immediately
              final notifier = ref.read(sermonProvider.notifier);
              notifier.updateSermon(
                sermon.copyWith(
                  title: newTitle.isNotEmpty ? newTitle : sermon.title,
                  series: newSeries,
                  tags: newTags,
                  scheduledDate: pickedDate,
                ),
              );
              _saveAfterDelay();
            },
            child: Text(
              'Save',
              style: PulpitFonts.inter(
                color: colors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      ),
    ).then((_) {
      // Dispose controllers when the dialog is dismissed
      titleCtrl.dispose();
      seriesCtrl.dispose();
      tagsCtrl.dispose();
    });
  }

  /// Formats a scheduled date as "Sunday, Jun 15" or "Today" / "Tomorrow".
  String _formatScheduledDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == today.add(const Duration(days: 1))) return 'Tomorrow';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final dayName = days[date.weekday - 1];
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '$dayName, ${months[date.month - 1]} ${date.day}';
  }

  // ── Contrast helper ─────────────────────────────────────────────────────────

  /// Returns a readable foreground colour for text/icons placed on [bg].
  /// Anything luminance > 0.4 (light backgrounds) gets dark text; else white.
  static Color _onAccent(Color bg) =>
      bg.computeLuminance() > 0.4
          ? const Color(0xFF1A1A1A)
          : Colors.white;

  void _showTranslationPicker(PulpitColors colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
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
            const SizedBox(height: 20),
            Text(
              'Default Translation',
              style: PulpitFonts.cormorantGaramond(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            ...availableTranslations.map((t) {
              final isSelected = _translation == t.code;
              return ListTile(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _translation = t.code);
                  Navigator.pop(context);
                  _saveAfterDelay();
                },
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected ? colors.accent : colors.card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      t.shortName,
                      style: PulpitFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? colors.background : colors.accent,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  t.name,
                  style: PulpitFonts.inter(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: colors.textPrimary,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check_rounded, color: colors.accent)
                    : null,
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// EDITOR HELPER DATA CLASSES & WIDGETS
// ─────────────────────────────────────────

// ── Prep checklist ────────────────────────────────────────────────────────────

class _CheckItem {
  final String label;
  final String subtitle;
  final bool done;
  const _CheckItem({
    required this.label,
    required this.subtitle,
    required this.done,
  });
}

class _PrepCheckRow extends StatelessWidget {
  final _CheckItem item;
  final PulpitColors colors;

  const _PrepCheckRow({required this.item, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: item.done
                  ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                  : colors.border.withValues(alpha: 0.4),
              shape: BoxShape.circle,
              border: Border.all(
                color: item.done
                    ? const Color(0xFF22C55E)
                    : colors.textSecondary.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: item.done
                ? const Icon(
                    Icons.check_rounded,
                    size: 13,
                    color: Color(0xFF22C55E),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: PulpitFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: item.done
                        ? colors.textPrimary
                        : colors.textSecondary,
                    decoration: item.done
                        ? TextDecoration.none
                        : TextDecoration.none,
                  ),
                ),
                Text(
                  item.subtitle,
                  style: PulpitFonts.inter(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrepProgress extends StatelessWidget {
  final int done;
  final int total;
  final PulpitColors colors;

  const _PrepProgress({
    required this.done,
    required this.total,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : done / total;
    final isComplete = done == total;
    final progressColor =
        isComplete ? const Color(0xFF22C55E) : colors.accent;

    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: fraction,
            strokeWidth: 4,
            backgroundColor: colors.border.withValues(alpha: 0.4),
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          ),
          Text(
            '$done/$total',
            style: PulpitFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Word count goal bar ────────────────────────────────────────────────────────

class _WordCountGoalBar extends StatelessWidget {
  final int current;
  final int goal;
  final PulpitColors colors;
  final VoidCallback? onTap;

  const _WordCountGoalBar({
    required this.current,
    required this.goal,
    required this.colors,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = (goal > 0 ? (current / goal).clamp(0.0, 1.0) : 0.0);
    final isComplete = current >= goal;
    final barColor = isComplete ? const Color(0xFF22C55E) : colors.accent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    Container(
                      height: 6,
                      color: colors.border.withValues(alpha: 0.5),
                    ),
                    FractionallySizedBox(
                      widthFactor: fraction,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isComplete
                  ? '✓ Goal reached'
                  : '$current / $goal words',
              style: PulpitFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: isComplete ? const Color(0xFF22C55E) : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Share option tile ─────────────────────────────────────────────────────────

class _ShareOption extends StatelessWidget {
  final PulpitColors colors;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool accent;
  final VoidCallback? onTap;

  const _ShareOption({
    required this.colors,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = accent
        ? colors.accent
        : colors.accent.withValues(alpha: 0.08);
    final fg = accent ? colors.background : colors.textPrimary;
    final iconFg = accent ? colors.background : colors.accent;

    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              // Generalized here — covers every share/copy option this
              // widget is used for (Share Outline, Copy as Outline, Share
              // for Social) in one place.
              HapticFeedback.lightImpact();
              onTap!();
            },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: accent
              ? null
              : Border.all(
                  color: colors.accent.withValues(alpha: 0.2),
                ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent
                    ? colors.background.withValues(alpha: 0.15)
                    : colors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconFg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: PulpitFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: PulpitFonts.inter(
                      fontSize: 12,
                      color: accent
                          ? colors.background.withValues(alpha: 0.75)
                          : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: accent
                  ? colors.background.withValues(alpha: 0.6)
                  : colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sermon Coach card ─────────────────────────────────────────────────────────

class _CoachTip {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final bool isPositive;

  const _CoachTip({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.isPositive = false,
  });
}

class _CoachCard extends StatelessWidget {
  final _CoachTip tip;
  final PulpitColors colors;

  const _CoachCard({required this.tip, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tip.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tip.color.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tip.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(tip.icon, size: 17, color: tip.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.title,
                  style: PulpitFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tip.body,
                  style: PulpitFonts.inter(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// SCRIPTURE CHIP WIDGET
// ─────────────────────────────────────────
class ScriptureChip extends StatelessWidget {
  final String reference;
  final String translation;
  final PulpitColors colors;
  final VoidCallback? onTap;

  const ScriptureChip({
    super.key,
    required this.reference,
    required this.translation,
    required this.colors,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.chipBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colors.accent.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_rounded, size: 13, color: colors.accent),
            const SizedBox(width: 6),
            Text(
              reference,
              style: PulpitFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.accent,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              translation,
              style: PulpitFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: colors.accent.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// PREMIUM SCRIPTURE PICKER
// ─────────────────────────────────────────
class PremiumScripturePicker extends StatefulWidget {
  final PulpitColors colors;
  final String defaultTranslation;
  final Function(String ref, String translation) onInsert;

  const PremiumScripturePicker({
    super.key,
    required this.colors,
    required this.defaultTranslation,
    required this.onInsert,
  });

  @override
  State<PremiumScripturePicker> createState() => _PremiumScripturePickerState();
}

class _PremiumScripturePickerState extends State<PremiumScripturePicker>
    with TickerProviderStateMixin {
  int _step = 0;
  String? _selectedBook;
  int? _selectedChapter;
  // Was a start/end int pair capping selection at one contiguous range —
  // replaced with a Set so a pastor can select as many verses as they want,
  // contiguous or not (e.g. verse 1-3 AND verse 7), matching the same
  // selection model as the Bible tab reader.
  Set<int> _selectedVerses = {};
  late String _selectedTranslation;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  // Chapter verse data from API
  // ignore: unused_field
  List<ScriptureVerse> _chapterVerses = [];
  bool _loadingChapter = false;

  // ── Quick reference (autocomplete) ────────────────────────────────────────────
  // This is the fast path users actually want (type "jn 3:16", get a live
  // suggestion) — it already existed but was easy to miss underneath the
  // tap-through book grid below it. Autofocusing it means the keyboard is up
  // and the cursor is waiting the instant this sheet opens, so typing is the
  // obvious first move instead of the grid.
  final _quickRefController = TextEditingController();
  final _quickRefFocusNode = FocusNode();
  String _quickRefText = '';
  /// Parsed result: (bookName, chapter, verseStart, verseEnd?) — null if unparsed
  ({String book, int chapter, int verseStart, int? verseEnd})? _quickRefParsed;
  List<BibleBook> _quickSuggestions = [];

  // ── Word search (search the whole Bible by keyword/phrase) ──────────────────
  // Sits alongside Quick Reference as a second input mode — pastors know a
  // phrase ("steadfast love", "shepherd") but not always the reference. Backed
  // by API.Bible's real search endpoint, not a local scan, since the app never
  // holds full Bible text offline.
  bool _searchMode = false;
  final _wordSearchController = TextEditingController();
  final _wordSearchFocusNode = FocusNode();
  String _wordSearchQuery = '';
  bool _searching = false;
  List<ScriptureSearchHit> _searchResults = [];
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _selectedTranslation = widget.defaultTranslation;
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );
    _slideController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quickRefController.dispose();
    _quickRefFocusNode.dispose();
    _wordSearchController.dispose();
    _wordSearchFocusNode.dispose();
    _searchDebounce?.cancel();
    _slideController.dispose();
    super.dispose();
  }

  // ── Word search handlers ─────────────────────────────────────────────────

  void _onWordSearchChanged(String raw) {
    setState(() => _wordSearchQuery = raw);
    _searchDebounce?.cancel();

    if (raw.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 450), () async {
      final results = await scriptureService.searchScripture(
        raw,
        _selectedTranslation,
      );
      // Guard against a slower, stale request landing after a newer one.
      if (mounted && _wordSearchQuery == raw) {
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      }
    });
  }

  void _insertSearchHit(ScriptureSearchHit hit) {
    HapticFeedback.selectionClick();
    widget.onInsert(hit.reference, hit.translation);
    Navigator.pop(context);
  }

  void _goToStep(int step) {
    _slideController.reset();
    setState(() => _step = step);
    _slideController.forward();
  }

  Future<void> _loadChapter() async {
    if (_selectedBook == null || _selectedChapter == null) return;
    setState(() => _loadingChapter = true);
    try {
      final verses = await scriptureService.getChapter(
        _selectedBook!,
        _selectedChapter!,
        _selectedTranslation,
      );
      if (mounted) {
        setState(() {
          _chapterVerses = verses;
          _loadingChapter = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingChapter = false);
      }
    }
  }

  BibleBook? get _currentBook {
    if (_selectedBook == null) return null;
    try {
      return bibleBooks.firstWhere((b) => b.name == _selectedBook);
    } catch (_) {
      return null;
    }
  }

  int get _chapterCount => _currentBook?.chapters.length ?? 0;

  int get _verseCount {
    if (_selectedBook == null || _selectedChapter == null) return 0;
    final book = _currentBook;
    if (book == null) return 0;
    final chapterIdx = _selectedChapter! - 1;
    if (chapterIdx < 0 || chapterIdx >= book.chapters.length) {
      return 0;
    }
    return book.chapters[chapterIdx];
  }

  /// Groups sorted selected verse numbers into contiguous (start, end) runs,
  /// e.g. {1,2,3,7} -> [(1,3), (7,7)] so "verse 1-3 and verse 7" both read
  /// as real references. Mirrors bible_reader_screen.dart's _contiguousRuns().
  List<(int, int)> _contiguousRuns() {
    if (_selectedVerses.isEmpty) return [];
    final sorted = _selectedVerses.toList()..sort();
    final runs = <(int, int)>[];
    int start = sorted.first;
    int prev = sorted.first;
    for (final v in sorted.skip(1)) {
      if (v == prev + 1) {
        prev = v;
        continue;
      }
      runs.add((start, prev));
      start = v;
      prev = v;
    }
    runs.add((start, prev));
    return runs;
  }

  /// One ref string per contiguous run, e.g. ["Genesis 3:1-3", "Genesis 3:7"].
  List<String> _selectionRefs() {
    if (_selectedBook == null || _selectedChapter == null) return [];
    return _contiguousRuns().map((r) {
      final base = '$_selectedBook $_selectedChapter';
      return r.$1 == r.$2 ? '$base:${r.$1}' : '$base:${r.$1}-${r.$2}';
    }).toList();
  }

  String get _currentRef {
    if (_selectedBook == null) return '';
    if (_selectedChapter == null) return _selectedBook!;
    if (_selectedVerses.isEmpty) {
      return '$_selectedBook $_selectedChapter';
    }
    final runs = _contiguousRuns();
    final label = runs
        .map((r) => r.$1 == r.$2 ? '${r.$1}' : '${r.$1}-${r.$2}')
        .join(', ');
    return '$_selectedBook $_selectedChapter:$label';
  }

  List<BibleBook> get _filteredBooks {
    if (_searchQuery.isEmpty) return bibleBooks;
    final q = _searchQuery.toLowerCase();
    return bibleBooks.where((b) {
      return b.name.toLowerCase().contains(q) ||
          b.abbreviations.any((a) => a.toLowerCase().startsWith(q));
    }).toList();
  }

  // ── Quick reference parser ────────────────────────────────────────────────────

  /// Parses a free-text input such as "Rom 8:28", "1 Cor 13:4-7", "Genesis 1"
  /// into a structured reference. Updates [_quickRefParsed] and [_quickSuggestions].
  void _onQuickRefChanged(String raw) {
    setState(() {
      _quickRefText = raw;
      _quickRefParsed = null;
      _quickSuggestions = [];
    });

    if (raw.trim().isEmpty) return;

    // ── Parse: optional leading digit (for "1 Corinthians") + book word(s) + optional "chapter:verse-verse"
    // Pattern: [1|2|3] <bookWord> [<chapter>[:<verseStart>[-<verseEnd>]]]
    final trimmed = raw.trim();

    // Split on whitespace; first token(s) form the book name
    // e.g. "1 cor 13:4-7" → tokens: ["1", "cor", "13:4-7"]
    final tokens = trimmed.split(RegExp(r'\s+'));

    // Try to find which prefix of tokens is a valid book abbreviation/name
    BibleBook? matchedBook;
    int bookTokenCount = 0;

    for (int len = (tokens.length).clamp(1, 3); len >= 1; len--) {
      final candidate = tokens.take(len).join(' ').toLowerCase();
      final match = bibleBooks.firstWhere(
        (b) =>
            b.name.toLowerCase() == candidate ||
            b.abbreviations.any((a) => a.toLowerCase() == candidate),
        orElse: () => bibleBooks.firstWhere(
          (b) =>
              b.name.toLowerCase().startsWith(candidate) ||
              b.abbreviations.any((a) => a.toLowerCase().startsWith(candidate)),
          orElse: () => bibleBooks.firstWhere(
            (b) => b.name.toLowerCase().contains(candidate),
            orElse: () => const BibleBook(name: '', abbreviations: [], chapters: []),
          ),
        ),
      );
      if (match.name.isNotEmpty) {
        matchedBook = match;
        bookTokenCount = len;
        break;
      }
    }

    // Build book suggestions for the first token if no exact match yet
    if (matchedBook == null && tokens.isNotEmpty) {
      final q = tokens.first.toLowerCase();
      final suggestions = bibleBooks.where((b) =>
        b.name.toLowerCase().startsWith(q) ||
        b.abbreviations.any((a) => a.toLowerCase().startsWith(q)),
      ).take(5).toList();
      setState(() => _quickSuggestions = suggestions);
      return;
    }

    if (matchedBook == null) return;

    // Remaining tokens after the book portion
    final rest = tokens.skip(bookTokenCount).toList();

    int? chapter;
    int? verseStart;
    int? verseEnd;

    if (rest.isNotEmpty) {
      // rest[0] might be "13:4-7" or "13:4" or "13"
      final chapterPart = rest.first;
      if (chapterPart.contains(':')) {
        final parts = chapterPart.split(':');
        chapter = int.tryParse(parts[0]);
        if (parts.length > 1) {
          final versePart = parts[1];
          if (versePart.contains('-')) {
            final vp = versePart.split('-');
            verseStart = int.tryParse(vp[0]);
            verseEnd = int.tryParse(vp[1]);
          } else {
            verseStart = int.tryParse(versePart);
          }
        }
      } else {
        chapter = int.tryParse(chapterPart);
        // Check for verse in next token: "13 4" or "13 4-7"
        if (chapter != null && rest.length > 1) {
          final vp2 = rest[1];
          if (vp2.contains('-')) {
            final vparts = vp2.split('-');
            verseStart = int.tryParse(vparts[0]);
            verseEnd = int.tryParse(vparts[1]);
          } else {
            verseStart = int.tryParse(vp2);
          }
        }
      }
    }

    // Validate chapter range
    if (chapter != null) {
      if (chapter < 1 || chapter > matchedBook.chapters.length) {
        chapter = null;
        verseStart = null;
        verseEnd = null;
      }
    }

    // Validate verse range
    if (chapter != null && verseStart != null) {
      final maxVerse = matchedBook.chapters[chapter - 1];
      verseStart = verseStart.clamp(1, maxVerse);
      if (verseEnd != null) {
        verseEnd = verseEnd.clamp(verseStart, maxVerse);
        if (verseEnd <= verseStart) verseEnd = null;
      }
    }

    if (chapter != null && verseStart != null) {
      setState(() {
        _quickRefParsed = (
          book: matchedBook!.name,
          chapter: chapter!,
          verseStart: verseStart!,
          verseEnd: verseEnd,
        );
      });
    } else {
      // Partial match — show the book as suggestion
      setState(() => _quickSuggestions = [matchedBook!]);
    }
  }

  String get _quickRefLabel {
    final p = _quickRefParsed;
    if (p == null) return '';
    if (p.verseEnd != null) return '${p.book} ${p.chapter}:${p.verseStart}–${p.verseEnd}';
    return '${p.book} ${p.chapter}:${p.verseStart}';
  }

  void _insertQuickRef() {
    final p = _quickRefParsed;
    if (p == null) return;
    HapticFeedback.mediumImpact();
    final refStr = p.verseEnd != null
        ? '${p.book} ${p.chapter}:${p.verseStart}-${p.verseEnd}'
        : '${p.book} ${p.chapter}:${p.verseStart}';
    widget.onInsert(refStr, _selectedTranslation);
    Navigator.pop(context);
  }

  Widget _buildModeToggle(PulpitColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: _ModeToggleTab(
                label: 'Reference',
                icon: Icons.menu_book_rounded,
                selected: !_searchMode,
                colors: colors,
                onTap: () {
                  if (_searchMode) {
                    HapticFeedback.selectionClick();
                    setState(() => _searchMode = false);
                  }
                },
              ),
            ),
            Expanded(
              child: _ModeToggleTab(
                label: 'Search by Word',
                icon: Icons.search_rounded,
                selected: _searchMode,
                colors: colors,
                onTap: () {
                  if (!_searchMode) {
                    HapticFeedback.selectionClick();
                    setState(() => _searchMode = true);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _wordSearchFocusNode.requestFocus();
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWordSearchBar(PulpitColors colors) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: colors.accent),
              const SizedBox(width: 4),
              Text(
                'Search Scripture',
                style: PulpitFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Text(
                'e.g. "shepherd" or "steadfast love"',
                style: PulpitFonts.inter(fontSize: 10, color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _wordSearchController,
            focusNode: _wordSearchFocusNode,
            style: PulpitFonts.inter(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Type a word or phrase...',
              hintStyle: PulpitFonts.inter(color: colors.textSecondary, fontSize: 14),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: _wordSearchQuery.isNotEmpty ? colors.accent : colors.textSecondary,
                size: 18,
              ),
              suffixIcon: _wordSearchQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _wordSearchController.clear();
                        _onWordSearchChanged('');
                      },
                      child: Icon(Icons.close_rounded, size: 16, color: colors.textSecondary),
                    )
                  : null,
              filled: true,
              fillColor: colors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.accent, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: _onWordSearchChanged,
            textInputAction: TextInputAction.search,
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: colors.border),
        ],
      ),
    );
  }

  Widget _buildWordSearchResults(PulpitColors colors) {
    if (_wordSearchQuery.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.travel_explore_rounded,
                size: 44,
                color: colors.textSecondary.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                'Search across the whole Bible',
                style: PulpitFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Type a word or phrase above to find every verse that mentions it.',
                textAlign: TextAlign.center,
                style: PulpitFonts.inter(
                  fontSize: 12,
                  color: colors.textSecondary.withValues(alpha: 0.7),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_searching) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 44,
                color: colors.textSecondary.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                'No verses found for "$_wordSearchQuery"',
                textAlign: TextAlign.center,
                style: PulpitFonts.inter(fontSize: 13, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      itemCount: _searchResults.length,
      itemBuilder: (ctx, i) {
        final hit = _searchResults[i];
        return _SearchResultTile(
          hit: hit,
          colors: colors,
          onTap: () => _insertSearchHit(hit),
        ).animate().fadeIn(
          delay: Duration(milliseconds: 20 * (i.clamp(0, 15))),
          duration: 200.ms,
        );
      },
    );
  }

  Widget _buildQuickRefBar(PulpitColors colors) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 14, color: colors.accent),
              const SizedBox(width: 4),
              Text(
                'Quick Reference',
                style: PulpitFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Text(
                'e.g. "Rom 8:28" or "John 3:16"',
                style: PulpitFonts.inter(
                  fontSize: 10,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Input row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quickRefController,
                  focusNode: _quickRefFocusNode,
                  autofocus: true,
                  style: PulpitFonts.inter(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Type a reference...',
                    hintStyle: PulpitFonts.inter(
                      color: colors.textSecondary,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: _quickRefParsed != null
                          ? colors.accent
                          : colors.textSecondary,
                      size: 18,
                    ),
                    suffixIcon: _quickRefText.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _quickRefController.clear();
                              _onQuickRefChanged('');
                            },
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: colors.textSecondary,
                            ),
                          )
                        : null,
                    filled: true,
                    fillColor: colors.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: _quickRefParsed != null
                            ? colors.accent
                            : colors.border,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: _onQuickRefChanged,
                  onSubmitted: (_) {
                    if (_quickRefParsed != null) _insertQuickRef();
                  },
                  textInputAction: TextInputAction.done,
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: _quickRefParsed != null
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: GestureDetector(
                          onTap: _insertQuickRef,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: colors.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Insert',
                              style: PulpitFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: colors.background,
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          if (_quickRefParsed != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colors.accent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.menu_book_rounded,
                          size: 12,
                          color: colors.accent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _quickRefLabel,
                          style: PulpitFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.accent,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '· $_selectedTranslation',
                          style: PulpitFonts.inter(
                            fontSize: 11,
                            color: colors.accent.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_quickSuggestions.isNotEmpty && _quickRefParsed == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickSuggestions.map((book) {
                  // Suggestion chips used to be flat bordered boxes —
                  // identical to plain static text. A little elevation,
                  // accent tint, and an animated tap response is what makes
                  // this actually read as "live autocomplete" instead of a
                  // static hint the user has to notice on their own.
                  return _QuickRefSuggestionChip(
                    label: book.name,
                    colors: colors,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _quickRefController.text = '${book.name} ';
                      _quickRefController.selection =
                          TextSelection.fromPosition(
                        TextPosition(
                          offset: _quickRefController.text.length,
                        ),
                      );
                      _onQuickRefChanged(_quickRefController.text);
                      _quickRefFocusNode.requestFocus();
                    },
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 8),
          Divider(height: 1, color: colors.border),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          _buildHandle(colors),
          _buildPickerHeader(colors),
          _buildModeToggle(colors),
          if (_searchMode) _buildWordSearchBar(colors) else _buildQuickRefBar(colors),
          if (!_searchMode) _buildStepIndicator(colors),
          Expanded(
            child: _searchMode
                ? _buildWordSearchResults(colors)
                : SlideTransition(
                    position: _slideAnimation,
                    child: _buildCurrentStep(colors),
                  ),
          ),
          if (!_searchMode && _selectedVerses.isNotEmpty) _buildInsertBar(colors),
        ],
      ),
    );
  }

  Widget _buildHandle(PulpitColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: colors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildPickerHeader(PulpitColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          if (!_searchMode && _step > 0)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                if (_step == 1) {
                  _selectedBook = null;
                  _goToStep(0);
                } else if (_step == 2) {
                  _selectedChapter = null;
                  _selectedVerses = {};
                  _chapterVerses = [];
                  _goToStep(1);
                }
              },
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.arrow_back_ios_rounded,
                  size: 14,
                  color: colors.textPrimary,
                ),
              ),
            ),
          Text(
            _searchMode
                ? 'Search Scripture'
                : _step == 0
                    ? 'Choose Book'
                    : _step == 1
                        ? 'Choose Chapter'
                        : 'Choose Verses',
            style: PulpitFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          // Translation selector
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              final options = ['KJV', 'NIV', 'ESV', 'NLT', 'NKJV', 'NASB', 'CSB', 'AMP'];
              showModalBottomSheet<void>(
                context: context,
                backgroundColor: colors.card,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...options.map((t) => ListTile(
                        title: Text(
                          t,
                          style: PulpitFonts.inter(
                            fontWeight: t == _selectedTranslation
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: t == _selectedTranslation
                                ? colors.accent
                                : colors.textPrimary,
                          ),
                        ),
                        trailing: t == _selectedTranslation
                            ? Icon(Icons.check_rounded, color: colors.accent)
                            : null,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedTranslation = t);
                          Navigator.pop(ctx);
                        },
                      )),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _selectedTranslation,
                style: PulpitFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(PulpitColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: List.generate(3, (i) {
          final active = i <= _step;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
              height: 3,
              decoration: BoxDecoration(
                color: active
                    ? colors.accent
                    : colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep(PulpitColors colors) {
    return switch (_step) {
      0 => _buildBookStep(colors),
      1 => _buildChapterStep(colors),
      _ => _buildVerseStep(colors),
    };
  }

  Widget _buildBookStep(PulpitColors colors) {
    final filtered = _filteredBooks;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: TextField(
            controller: _searchController,
            style: PulpitFonts.inter(color: colors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search books...',
              hintStyle: PulpitFonts.inter(
                color: colors.textSecondary,
                fontSize: 14,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: colors.textSecondary,
                size: 18,
              ),
              filled: true,
              fillColor: colors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.accent, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final book = filtered[i];
              return ListTile(
                dense: true,
                title: Text(
                  book.name,
                  style: PulpitFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
                trailing: Text(
                  '${book.chapters.length} ch.',
                  style: PulpitFonts.inter(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedBook = book.name;
                    _selectedChapter = null;
                    _selectedVerses = {};
                    _chapterVerses = [];
                    _searchQuery = '';
                    _searchController.clear();
                  });
                  _goToStep(1);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChapterStep(PulpitColors colors) {
    final count = _chapterCount;
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: count,
      itemBuilder: (ctx, i) {
        final ch = i + 1;
        final selected = _selectedChapter == ch;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _selectedChapter = ch;
              _selectedVerses = {};
              _chapterVerses = [];
            });
            _loadChapter();
            _goToStep(2);
          },
          child: Container(
            decoration: BoxDecoration(
              color: selected
                  ? colors.accent
                  : colors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? colors.accent : colors.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '$ch',
              style: PulpitFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? colors.background : colors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVerseStep(PulpitColors colors) {
    if (_loadingChapter) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    final verseCount = _verseCount;
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: verseCount,
      itemBuilder: (ctx, i) {
        final v = i + 1;
        final selected = _selectedVerses.contains(v);
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              // Toggle this verse in/out of the set — a pastor can pick as
              // many verses as they want, contiguous or not (e.g. 1-3 AND 7),
              // matching the same selection model as the Bible tab reader.
              if (selected) {
                _selectedVerses.remove(v);
              } else {
                _selectedVerses.add(v);
              }
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: selected
                  ? colors.accent.withValues(alpha: 0.15)
                  : colors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? colors.accent : colors.border,
                width: selected ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '$v',
              style: PulpitFonts.inter(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? colors.accent : colors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInsertBar(PulpitColors colors) {
    final ref = _currentRef;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          ref,
                          overflow: TextOverflow.ellipsis,
                          style: PulpitFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      if (_selectedVerses.length > 1) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_selectedVerses.length} verses',
                            style: PulpitFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colors.accent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    _selectedTranslation,
                    style: PulpitFonts.inter(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                if (_selectedVerses.isEmpty) return;
                HapticFeedback.mediumImpact();
                // One scripture block per contiguous run, so a selection like
                // "1-3, 7" becomes two separate blocks — mirrors how the
                // Bible tab's "Add to Sermon" action behaves.
                for (final refStr in _selectionRefs()) {
                  widget.onInsert(refStr, _selectedTranslation);
                }
                Navigator.pop(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Insert',
                  style: PulpitFonts.inter(
                    fontSize: 14,
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
}

/// One tab of the Reference / Search-by-Word segmented toggle atop the
/// scripture picker.
class _ModeToggleTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final PulpitColors colors;
  final VoidCallback onTap;

  const _ModeToggleTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: PulpitMotion.standard,
        curve: PulpitMotion.curve,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? colors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? colors.background : colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: PulpitFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? colors.background : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single verse result row inside the word-search results list.
class _SearchResultTile extends StatefulWidget {
  final ScriptureSearchHit hit;
  final PulpitColors colors;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.hit,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends State<_SearchResultTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: PulpitMotion.fast,
        curve: Curves.easeOut,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
            boxShadow: _pressed ? [] : PulpitElevation.card(colors),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.menu_book_rounded, size: 14, color: colors.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.hit.reference,
                      style: PulpitFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.hit.translation,
                      style: PulpitFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.hit.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PulpitFonts.lora(
                  fontSize: 13,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick-reference book suggestion chip. A tiny lift + tap-scale is enough
/// to make a plain text-in-a-box read as "live, tappable suggestion" rather
/// than a static hint — cheap to add, and it's the kind of small motion
/// that's largely absent from this app's flatter, border-only surfaces.
class _QuickRefSuggestionChip extends StatefulWidget {
  final String label;
  final PulpitColors colors;
  final VoidCallback onTap;

  const _QuickRefSuggestionChip({
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_QuickRefSuggestionChip> createState() =>
      _QuickRefSuggestionChipState();
}

class _QuickRefSuggestionChipState extends State<_QuickRefSuggestionChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.accentSoft,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.accent.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: _pressed
                ? []
                : [
                    BoxShadow(
                      color: colors.accent.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 12,
                color: colors.accent,
              ),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: PulpitFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
