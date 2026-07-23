import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/bible_books.dart';
import '../../../core/constants/highlight_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/scripture_model.dart';
import '../../../data/services/scripture_service.dart';
import '../../../shared/state/theme_provider.dart';
import '../../library/screens/concordance_screen.dart';
import '../../library/screens/highlights_screen.dart';
import '../data/highlights_service.dart';
import '../widgets/scripture_overlay.dart';

const List<Map<String, String>> _kBibleTranslations = [
  {'code': 'KJV', 'name': 'King James Version'},
  {'code': 'NIV', 'name': 'New International Version'},
  {'code': 'AMP', 'name': 'Amplified Bible'},
  {'code': 'ESV', 'name': 'English Standard Version'},
  {'code': 'NLT', 'name': 'New Living Translation'},
  {'code': 'NKJV', 'name': 'New King James Version'},
];

/// A flat global chapter index: a list of (book name, chapter number) tuples
/// spanning every chapter of every book in [bibleBooks]. Used by the PageView
/// to enable smooth swipe-paging across book boundaries.
class _ChapterPos {
  final String book;
  final int chapter;
  const _ChapterPos(this.book, this.chapter);
}

final List<_ChapterPos> _kGlobalChapterIndex = () {
  final list = <_ChapterPos>[];
  for (final book in bibleBooks) {
    for (var i = 1; i <= book.chapters.length; i++) {
      list.add(_ChapterPos(book.name, i));
    }
  }
  return list;
}();

int _indexFor(String book, int chapter) {
  final idx = _kGlobalChapterIndex.indexWhere(
    (p) => p.book == book && p.chapter == chapter,
  );
  return idx < 0 ? 0 : idx;
}

/// Full-screen Bible reader with swipe-paging across all 66 books.
class BibleReaderScreen extends ConsumerStatefulWidget {
  final String? initialBook;
  final int? initialChapter;
  final String? initialTranslation;
  final int? initialVerse;
  final void Function(String reference, String translation)? onAddToSermon;

  const BibleReaderScreen({
    super.key,
    this.initialBook,
    this.initialChapter,
    this.initialTranslation,
    this.initialVerse,
    this.onAddToSermon,
  });

  @override
  ConsumerState<BibleReaderScreen> createState() => _BibleReaderScreenState();
}

class _BibleReaderScreenState extends ConsumerState<BibleReaderScreen> {
  late PageController _pageController;
  late int _currentPage;
  late String _translation;
  int? _initialTargetVerse;

  // Per-page caches so swiping back doesn't refetch.
  final Map<int, List<ScriptureVerse>> _chapterCache = {};
  final Map<int, bool> _loadingPages = {};

  // verseNumber -> colorKey for whichever chapter is currently on screen.
  // HighlightsService and its Supabase table already existed but were never
  // actually wired to any screen — this is the read side of finally using it.
  Map<int, String> _currentHighlights = {};

  // ── Verse selection ──────────────────────────────────────────────────────
  // Replaces the old long-press-only "verse menu" bottom sheet (which had
  // grown to 5-6 stacked buttons and started overflowing off small screens).
  // Tapping a verse now selects it immediately and shows a compact action
  // bar in the footer's place — tapping further verses extends the
  // selection to as many as the pastor wants, YouVersion-style but with
  // highlight + translation compare unified into the same bar instead of
  // being separate flows.
  Set<int> _selectedVerses = {};

  // Verse numbers whose highlight was just toggled by an explicit user
  // action (as opposed to highlight data simply finishing its async load on
  // chapter open) — drives the one-shot pulse animation in [_VerseRow].
  // Cleared a beat after the pulse would have finished playing.
  Set<int> _justChangedVerses = {};

  static const String _kBookKey = 'bible_reader_book';
  static const String _kChapterKey = 'bible_reader_chapter';
  static const String _kTranslationKey = 'bible_reader_translation';

  _ChapterPos get _currentPos => _kGlobalChapterIndex[_currentPage];
  String get _book => _currentPos.book;
  int get _chapter => _currentPos.chapter;

  @override
  void initState() {
    super.initState();
    _translation = widget.initialTranslation ?? 'KJV';
    _initialTargetVerse = widget.initialVerse;

    final initialBook = widget.initialBook ?? 'John';
    final initialChapter = widget.initialChapter ?? 1;
    _currentPage = _indexFor(initialBook, initialChapter);
    _pageController = PageController(initialPage: _currentPage);

    // Restore previously saved position only when caller didn't supply one.
    if (widget.initialBook == null) {
      _restorePosition();
    }
    _loadPage(_currentPage);
    // Prefetch neighbours for snappy swipe.
    _loadPage(_currentPage - 1);
    _loadPage(_currentPage + 1);
    _loadHighlights();
  }

  Future<void> _loadHighlights() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final map = await highlightsService.fetchHighlights(
        userId: userId,
        book: _book,
        chapter: _chapter,
      );
      if (mounted) setState(() => _currentHighlights = map);
    } catch (_) {
      // Not signed in / offline — just show no highlights rather than error.
    }
  }

  Future<void> _restorePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final book = prefs.getString(_kBookKey);
      final chapter = prefs.getInt(_kChapterKey);
      final translation = prefs.getString(_kTranslationKey);
      if (!mounted || book == null) return;
      final page = _indexFor(book, chapter ?? 1);
      setState(() {
        _translation = translation ?? _translation;
        _currentPage = page;
      });
      _pageController.jumpToPage(page);
      _loadPage(page);
      _loadPage(page - 1);
      _loadPage(page + 1);
    } catch (_) {}
  }

  Future<void> _savePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBookKey, _book);
      await prefs.setInt(_kChapterKey, _chapter);
      await prefs.setString(_kTranslationKey, _translation);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int _cacheKey(int page) => page * 100 + _translationIndex();
  int _translationIndex() =>
      _kBibleTranslations.indexWhere((t) => t['code'] == _translation);

  Future<void> _loadPage(int page) async {
    if (page < 0 || page >= _kGlobalChapterIndex.length) return;
    final key = _cacheKey(page);
    if (_chapterCache.containsKey(key) || _loadingPages[key] == true) return;
    _loadingPages[key] = true;
    try {
      final pos = _kGlobalChapterIndex[page];
      final verses = await scriptureService.getChapter(
        pos.book,
        pos.chapter,
        _translation,
      );
      if (!mounted) return;
      setState(() {
        _chapterCache[key] = verses;
        _loadingPages[key] = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPages[key] = false);
    }
  }

  void _onPageChanged(int page) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentPage = page;
      _selectedVerses = {};
    });
    _savePosition();
    // Prefetch neighbours.
    _loadPage(page - 1);
    _loadPage(page + 1);
    _currentHighlights = {};
    _loadHighlights();
  }

  Future<void> _switchTranslation(String code) async {
    if (code == _translation) return;
    HapticFeedback.selectionClick();
    setState(() => _translation = code);
    _loadPage(_currentPage);
    _loadPage(_currentPage - 1);
    _loadPage(_currentPage + 1);
    _savePosition();
  }

  void _jumpTo(String book, int chapter, {int? verse}) {
    final page = _indexFor(book, chapter);
    setState(() {
      _currentPage = page;
      _initialTargetVerse = verse;
      _selectedVerses = {};
    });
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    _loadPage(page);
    _savePosition();
    _currentHighlights = {};
    _loadHighlights();
  }

  // ── Verse selection handlers ─────────────────────────────────────────────

  void _onVerseTap(ScriptureVerse verse) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedVerses.contains(verse.verseNumber)) {
        _selectedVerses.remove(verse.verseNumber);
      } else {
        _selectedVerses.add(verse.verseNumber);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedVerses = {});

  List<ScriptureVerse> get _currentChapterVerses =>
      _chapterCache[_cacheKey(_currentPage)] ?? const [];

  /// Selected verse objects, in verse-number order, actually resolved
  /// against the loaded chapter (not just the bare numbers).
  List<ScriptureVerse> _resolvedSelectedVerses() {
    final byNumber = {for (final v in _currentChapterVerses) v.verseNumber: v};
    final nums = _selectedVerses.toList()..sort();
    return [for (final n in nums) if (byNumber[n] != null) byNumber[n]!];
  }

  /// Groups selected verse numbers into contiguous runs, e.g. {1,2,3,7} ->
  /// [(1,3), (7,7)] — lets "Genesis 3:1-3, 7" read as a real reference
  /// instead of one row per verse, while still supporting arbitrary,
  /// non-contiguous multi-select.
  List<(int, int)> _contiguousRuns() {
    final nums = _selectedVerses.toList()..sort();
    final runs = <(int, int)>[];
    for (final n in nums) {
      if (runs.isNotEmpty && runs.last.$2 == n - 1) {
        runs[runs.length - 1] = (runs.last.$1, n);
      } else {
        runs.add((n, n));
      }
    }
    return runs;
  }

  List<String> _selectionRefs() => _contiguousRuns()
      .map((r) => r.$1 == r.$2 ? '$_book $_chapter:${r.$1}' : '$_book $_chapter:${r.$1}-${r.$2}')
      .toList();

  String _selectionLabel() {
    final refs = _selectionRefs();
    if (refs.isEmpty) return '';
    return refs.map((r) => r.replaceFirst('$_book $_chapter:', '')).join(', ');
  }

  /// Opens the whole-Bible word/phrase search. This existed only inside the
  /// sermon editor's scripture picker — moved here too since the Bible tab
  /// is where a pastor is more likely to reach for "find every verse that
  /// mentions X" while just reading, not just while drafting.
  void _showWordSearch(PulpitColors colors) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WordSearchSheet(
        colors: colors,
        translation: _translation,
        onJump: (book, chapter, verse) {
          Navigator.pop(context);
          _jumpTo(book, chapter, verse: verse);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = PulpitColors.of(ref.watch(themeProvider));

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(colors),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: _onPageChanged,
                itemCount: _kGlobalChapterIndex.length,
                // Reverted the 3D page-turn wrapper per Solomon's on-device
                // call — he preferred the ordinary flat swipe over the tilt
                // effect even after the RepaintBoundary lag fix. Plain
                // PageView.builder, no _PageTurn.
                itemBuilder: (context, page) => _buildChapterPage(page, colors),
              ),
            ),
            _selectedVerses.isEmpty
                ? _buildFooter(colors)
                : _buildSelectionBar(colors),
          ],
        ),
      ),
    );
  }

  /// Replaces the footer (Prev / chapter / Next) the instant a verse is
  /// tapped — the compact bar this session's overflowing verse-menu sheet
  /// got replaced with. Copy, Highlight, and Compare Translations now live
  /// side by side instead of being separate flows, and tapping more verses
  /// (arbitrary, non-contiguous — not capped at two) extends the same
  /// selection instead of opening a new menu per verse.
  Widget _buildSelectionBar(PulpitColors colors) {
    final count = _selectedVerses.length;
    final canAdd = widget.onAddToSermon != null;
    final currentColorKey = count == 1
        ? _currentHighlights[_selectedVerses.first]
        : null;

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
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _clearSelection();
                  },
                  child: Icon(Icons.close_rounded, size: 20, color: colors.textSecondary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$_book $_chapter:${_selectionLabel()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PulpitFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  count == 1 ? '1 verse' : '$count verses',
                  style: PulpitFonts.inter(fontSize: 11, color: colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Highlight swatches — shown inline (not a second tap away) so
            // highlighting and translation-comparing genuinely sit together
            // in the same bar, per the "should be together" ask.
            SizedBox(
              height: 34,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                scrollDirection: Axis.horizontal,
                children: [
                  ...kHighlightColors.entries.map((entry) {
                    final selected = currentColorKey == entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _applyHighlight(entry.key),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: entry.value,
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(color: colors.textPrimary, width: 2)
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: entry.value.withValues(alpha: 0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: selected
                              ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                              : null,
                        ),
                      ),
                    );
                  }),
                  if (currentColorKey != null)
                    GestureDetector(
                      onTap: () => _applyHighlight(null),
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: colors.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.border),
                        ),
                        child: Icon(Icons.close_rounded, size: 14, color: colors.textSecondary),
                      ),
                    ),
                  Container(width: 1, height: 24, color: colors.border, margin: const EdgeInsets.symmetric(horizontal: 4)),
                  _selectionActionIcon(
                    colors,
                    icon: Icons.content_copy_rounded,
                    label: 'Copy',
                    onTap: _copySelection,
                  ),
                  _selectionActionIcon(
                    colors,
                    icon: Icons.translate_rounded,
                    label: 'Translate',
                    onTap: _compareSelectionTranslations,
                  ),
                  if (count == 1)
                    _selectionActionIcon(
                      colors,
                      icon: Icons.link_rounded,
                      label: 'Cross-refs',
                      onTap: () {
                        final scriptureRef = '$_book $_chapter:${_selectedVerses.first}';
                        _clearSelection();
                        showScriptureOverlay(
                          context: context,
                          reference: scriptureRef,
                          translation: _translation,
                          onAddToSermon: widget.onAddToSermon,
                        );
                      },
                    ),
                  if (canAdd)
                    _selectionActionIcon(
                      colors,
                      icon: Icons.add_rounded,
                      label: 'Add',
                      primary: true,
                      onTap: _addSelectionToSermon,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionActionIcon(
    PulpitColors colors, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          // Generalized here — covers Copy/Translate/Cross-refs/Add in one
          // place. `primary` (Add) and Cross-refs both open something
          // heavier (a full overlay) so they get the extra tier; Copy and
          // Translate stay at the standard confirm tier.
          HapticFeedback.lightImpact();
          if (primary || label == 'Cross-refs') {
            HapticFeedback.mediumImpact();
          }
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: primary ? colors.accent : colors.card,
            borderRadius: BorderRadius.circular(20),
            border: primary ? null : Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: primary ? colors.background : colors.accent),
              const SizedBox(width: 5),
              Text(
                label,
                style: PulpitFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: primary ? colors.background : colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(PulpitColors colors) {
    final book = bibleBooks.firstWhere(
      (b) => b.name == _book,
      orElse: () => bibleBooks.first,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // Only shown when this screen was pushed on top of something
          // (from the editor, preaching mode, or a scripture overlay).
          // When it's the Bible tab root in the bottom-nav shell, there's
          // nothing to pop back to, so the button is hidden instead of
          // being a dead tap target.
          if (Navigator.of(context).canPop()) ...[
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _savePosition();
                Navigator.of(context).pop();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back_rounded,
                      size: 14,
                      color: colors.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.onAddToSermon != null ? 'Back to Sermon' : 'Back',
                      style: PulpitFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: GestureDetector(
              // Was: book-only picker that jumped straight to chapter 1,
              // skipping chapter/verse selection entirely. Now opens the
              // same book -> chapter -> verse(s) wizard used everywhere
              // else in the app, and shows exactly what was picked instead
              // of always dropping into the full chapter.
              onTap: () {
                HapticFeedback.lightImpact();
                _showPassageSelector(colors);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        '$_book $_chapter',
                        key: ValueKey('$_book-$_chapter'),
                        style: PulpitFonts.cormorantGaramond(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ch ${book.chapters.length}',
                    style: PulpitFonts.inter(
                      fontSize: 10,
                      color: colors.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // The translation chip + Concordance + Highlights (+ Search, added
          // this session) used to sit as bare fixed-width siblings after the
          // Expanded book/chapter selector. That's fine until "Back to
          // Sermon" is also showing (long label) — then the fixed cluster's
          // total width leaves the Expanded's own minimum content nowhere to
          // go, and it overflows off the right edge. Flexible + an internal
          // horizontal scroll means this cluster shrinks and, failing that,
          // scrolls internally instead of ever pushing the row past the
          // screen edge — same fix shape as the editor toolbar below.
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              physics: const ClampingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _showTranslationPicker(colors);
                    },
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
                            _translation,
                            style: PulpitFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: colors.accent,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 12,
                            color: colors.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Word search belongs in the Bible tab, not just buried in
                  // the sermon editor's scripture picker — this is the
                  // primary place a pastor would reach for it.
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _savePosition();
                      _showWordSearch(colors);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.border),
                      ),
                      child: Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: colors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Concordance was a fully-built screen with no way to reach
                  // it anywhere in the app — this is its new home, since it's
                  // a Bible-study tool and this is the Bible tab.
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _savePosition();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ConcordanceScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.border),
                      ),
                      child: Icon(
                        Icons.menu_book_rounded,
                        size: 16,
                        color: colors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Same story as Concordance above: HighlightsService + the
                  // Supabase table already existed but had no screen to live in.
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _savePosition();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HighlightsScreen(
                            onJumpTo: (book, chapter, verse) {
                              _jumpTo(book, chapter, verse: verse);
                            },
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.border),
                      ),
                      child: Icon(
                        Icons.bookmark_rounded,
                        size: 16,
                        color: colors.accent,
                      ),
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

  Widget _buildChapterPage(int page, PulpitColors colors) {
    final pos = _kGlobalChapterIndex[page];
    final key = _cacheKey(page);
    final verses = _chapterCache[key];
    final loading = _loadingPages[key] ?? false;

    // Auto-scroll to target verse on the *current* page only.
    final targetVerse = page == _currentPage ? _initialTargetVerse : null;

    return _ChapterPage(
      key: ValueKey('$page-$_translation'),
      book: pos.book,
      chapter: pos.chapter,
      translation: _translation,
      verses: verses ?? const [],
      loading: loading && verses == null,
      colors: colors,
      targetVerse: targetVerse,
      highlights: page == _currentPage ? _currentHighlights : const {},
      selectedVerses: page == _currentPage ? _selectedVerses : const {},
      justChangedVerses: page == _currentPage ? _justChangedVerses : const {},
      onVerseTap: _onVerseTap,
      onVerseConsumed: () {
        if (_initialTargetVerse != null) {
          setState(() => _initialTargetVerse = null);
        }
      },
    );
  }

  Widget _buildFooter(PulpitColors colors) {
    final book = bibleBooks.firstWhere(
      (b) => b.name == _book,
      orElse: () => bibleBooks.first,
    );
    final canPrev = _currentPage > 0;
    final canNext = _currentPage < _kGlobalChapterIndex.length - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.border.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _navButton(
            colors,
            label: 'Prev',
            iconLeft: true,
            enabled: canPrev,
            onTap: () {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
              );
            },
          ),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _showChapterPicker(colors, book.chapters.length);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colors.accent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.swipe_rounded,
                    size: 12,
                    color: colors.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Ch $_chapter / ${book.chapters.length}',
                    style: PulpitFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _navButton(
            colors,
            label: 'Next',
            iconLeft: false,
            enabled: canNext,
            onTap: () {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _navButton(
    PulpitColors colors, {
    required String label,
    required bool iconLeft,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final icon = Icon(
      iconLeft ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
      size: 16,
      color: colors.textSecondary,
    );
    final text = Text(
      label,
      style: PulpitFonts.inter(fontSize: 12, color: colors.textSecondary),
    );

    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap();
            }
          : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.3,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: iconLeft ? [icon, text] : [text, icon],
          ),
        ),
      ),
    );
  }

  /// Opens a sheet showing the same verse/passage rendered across every
  /// translation the app supports, fetched in parallel. Lets a pastor see at
  /// a glance how KJV phrases something versus NLT, without re-navigating
  /// the picker six times.
  void _showTranslationComparison(String scriptureRef, PulpitColors colors) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TranslationCompareSheet(
        reference: scriptureRef,
        colors: colors,
      ),
    );
  }

  /// Applies (or clears, if [colorKey] is null) a highlight color to every
  /// verse currently selected — shared by the new selection action bar so
  /// highlighting works the same whether one verse or many are selected.
  Future<void> _applyHighlight(String? colorKey) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    HapticFeedback.selectionClick();
    final touchedVerses = Set<int>.from(_selectedVerses);
    try {
      for (final verseNum in _selectedVerses) {
        if (colorKey == null) {
          await highlightsService.removeHighlight(
            userId: userId,
            book: _book,
            chapter: _chapter,
            verse: verseNum,
          );
        } else {
          await highlightsService.upsertHighlight(
            userId: userId,
            book: _book,
            chapter: _chapter,
            verse: verseNum,
            color: colorKey,
          );
        }
      }
      if (mounted) {
        // _VerseRow paints the accent selection tint over the highlight
        // color whenever isSelected is true (so an actively-selected verse
        // doesn't look like it already has a random highlight color). Since
        // this method never used to clear selection afterward, the verse
        // stayed visually "selected" — the highlight color (and the pulse
        // meant to announce it) were both firing correctly but invisibly,
        // painted underneath the selection outline. Deselecting here is
        // what actually reveals them.
        setState(() {
          _justChangedVerses = touchedVerses;
          _selectedVerses = {};
        });
        await _loadHighlights();
        // Pulse plays over ~420ms; give it a little headroom then clear so
        // the flag doesn't linger and false-trigger on some later unrelated
        // rebuild (e.g. switching translation) for the same verse numbers.
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _justChangedVerses = {});
        });
      }
    } catch (_) {
      if (mounted) {
        final colors = PulpitColors.of(ref.read(themeProvider));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not save highlight — check your connection',
              style: PulpitFonts.inter(color: Colors.white),
            ),
            backgroundColor: colors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  void _copySelection() {
    final verses = _resolvedSelectedVerses();
    if (verses.isEmpty) return;
    final label = _selectionLabel();
    final text =
        '$_book $_chapter:$label ($_translation)\n${verses.map((v) => '${v.verseNumber} ${v.text}').join(' ')}';
    Clipboard.setData(ClipboardData(text: text));
    final colors = PulpitColors.of(ref.read(themeProvider));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied $_book $_chapter:$label',
          style: PulpitFonts.inter(color: colors.background),
        ),
        backgroundColor: colors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
    _clearSelection();
  }

  void _addSelectionToSermon() {
    final refs = _selectionRefs();
    for (final refStr in refs) {
      widget.onAddToSermon?.call(refStr, _translation);
    }
    final colors = PulpitColors.of(ref.read(themeProvider));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${refs.length == 1 ? refs.first : '${refs.length} references'} added to sermon',
          style: PulpitFonts.inter(color: colors.background),
        ),
        backgroundColor: colors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
    _clearSelection();
  }

  void _compareSelectionTranslations() {
    final refs = _selectionRefs();
    if (refs.isEmpty) return;
    final colors = PulpitColors.of(ref.read(themeProvider));
    _showTranslationComparison(refs.first, colors);
  }

  /// Opens the book -> chapter -> verse(s) passage-selection wizard.
  /// Replaces the old book-only picker (which always jumped to chapter 1
  /// and had no verse step at all). Confirming a selection shows exactly
  /// those verses in [_showPassageResult] rather than the whole chapter,
  /// with a "Read full chapter" option available at every step.
  ///
  /// Awaits the sheet's own dismissal (it pops itself with a result value)
  /// instead of the previous approach — passing callbacks down that called
  /// Navigator.pop(context) and then immediately opened a second bottom
  /// sheet in the same synchronous call. That pop-then-push-another-modal
  /// chaining is what caused an on-device crash ("'_dependents.isEmpty':
  /// is not true" — a Flutter framework assertion about an InheritedWidget
  /// element being unmounted before its dependents were cleared). Awaiting
  /// the first sheet's Future guarantees its route has fully torn down
  /// before we ever touch the Navigator again.
  Future<void> _showPassageSelector(PulpitColors colors) async {
    final result = await showModalBottomSheet<_PassageWizardResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PassageSelectorSheet(colors: colors),
    );
    if (result == null || !mounted) return;
    if (result.readFullChapter) {
      _jumpTo(result.book, result.chapter);
    } else {
      _showPassageResult(result.book, result.chapter, result.verses, colors);
    }
  }

  /// Fetches the chosen chapter (cached the same way the main pager caches
  /// it) then shows only the selected verse(s) — never the whole chapter —
  /// with a button to expand into the full chapter reading view if wanted.
  /// Same await-the-sheet's-own-pop pattern as [_showPassageSelector], for
  /// the same crash-avoidance reason.
  Future<void> _showPassageResult(
    String book,
    int chapter,
    List<int> verseNumbers,
    PulpitColors colors,
  ) async {
    if (!mounted) return;
    final readFullChapter = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PassageResultSheet(
        colors: colors,
        book: book,
        chapter: chapter,
        translation: _translation,
        verseNumbers: verseNumbers,
        onAddToSermon: widget.onAddToSermon,
      ),
    );
    if (readFullChapter == true && mounted) {
      _jumpTo(book, chapter, verse: verseNumbers.isNotEmpty ? verseNumbers.first : null);
    }
  }

  void _showChapterPicker(PulpitColors colors, int totalChapters) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(sheetContext).size.height * 0.5,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Choose Chapter',
                style: PulpitFonts.cormorantGaramond(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                itemCount: totalChapters,
                itemBuilder: (context, index) {
                  final chapter = index + 1;
                  final isSelected = chapter == _chapter;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(sheetContext);
                      _jumpTo(_book, chapter);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: isSelected ? colors.accent : colors.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? colors.accent : colors.border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$chapter',
                          style: PulpitFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? colors.background
                                : colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTranslationPicker(PulpitColors colors) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        // Six translation rows + header comfortably clear the default
        // (~9/16-screen) bottom-sheet cap on smaller phones, which pushed
        // the last 1-2 rows off-screen with no way to reach them — hence
        // isScrollControlled + an explicit height cap + SingleChildScrollView
        // instead of letting Column's intrinsic height decide.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
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
              'Translation',
              style: PulpitFonts.cormorantGaramond(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            ..._kBibleTranslations.map((t) {
              final isSelected = t['code'] == _translation;
              return GestureDetector(
                onTap: () {
                  Navigator.pop(sheetContext);
                  _switchTranslation(t['code']!);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.accent.withValues(alpha: 0.1)
                        : colors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? colors.accent : colors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t['code']!,
                              style: PulpitFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? colors.accent
                                    : colors.textPrimary,
                              ),
                            ),
                            Text(
                              t['name']!,
                              style: PulpitFonts.inter(
                                fontSize: 11,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle_rounded,
                          color: colors.accent,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-chapter page, scrolling its own list. Kept as a separate widget so
/// PageView's lazy build + the chapter-level scroll state are isolated per
/// page. Also has a one-shot scroll-to-verse on first build when [targetVerse]
/// is non-null.
class _ChapterPage extends StatefulWidget {
  final String book;
  final int chapter;
  final String translation;
  final List<ScriptureVerse> verses;
  final bool loading;
  final PulpitColors colors;
  final int? targetVerse;
  final Map<int, String> highlights;
  final Set<int> selectedVerses;
  final Set<int> justChangedVerses;
  final void Function(ScriptureVerse verse) onVerseTap;
  final VoidCallback onVerseConsumed;

  const _ChapterPage({
    super.key,
    required this.book,
    required this.chapter,
    required this.translation,
    required this.verses,
    required this.loading,
    required this.colors,
    required this.onVerseTap,
    required this.onVerseConsumed,
    this.targetVerse,
    this.highlights = const {},
    this.selectedVerses = const {},
    this.justChangedVerses = const {},
  });

  @override
  State<_ChapterPage> createState() => _ChapterPageState();
}

class _ChapterPageState extends State<_ChapterPage> {
  final ScrollController _scroll = ScrollController();
  bool _consumedTarget = false;

  @override
  void didUpdateWidget(covariant _ChapterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeScrollToTarget();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScrollToTarget());
  }

  void _maybeScrollToTarget() {
    if (_consumedTarget) return;
    final v = widget.targetVerse;
    if (v == null || v <= 1) {
      _consumedTarget = true;
      return;
    }
    if (!_scroll.hasClients) return;
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted || !_scroll.hasClients) return;
      final offset = (v - 1) * 64.0;
      _scroll.animateTo(
        offset.clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
      _consumedTarget = true;
      widget.onVerseConsumed();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    if (widget.loading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (widget.verses.isEmpty) {
      return Center(
        child: Text(
          'No content available',
          style: PulpitFonts.inter(color: colors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      // This was the actual "scrolling feels hard, lacks oil" culprit — no
      // physics meant Android's default Clamping physics (rigid, no
      // momentum/overscroll), while the chapter pager right above it already
      // used BouncingScrollPhysics. Matching them makes reading within a
      // chapter feel as fluid as swiping between chapters.
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
      itemCount: widget.verses.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // Chapter title for visual anchoring during swipes.
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${widget.book} ${widget.chapter}',
              style: PulpitFonts.cormorantGaramond(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
          );
        }
        final verse = widget.verses[index - 1];
        final highlightKey = widget.highlights[verse.verseNumber];
        final isSelected = widget.selectedVerses.contains(verse.verseNumber);
        final justChanged = widget.justChangedVerses.contains(
          verse.verseNumber,
        );
        return _VerseRow(
          key: ValueKey('verse-${verse.verseNumber}'),
          verse: verse,
          highlightKey: highlightKey,
          isSelected: isSelected,
          justChanged: justChanged,
          colors: colors,
          onTap: () => widget.onVerseTap(verse),
        );
      },
    );
  }
}

/// One verse line in the chapter reader. Split out from the inline
/// itemBuilder purely so it can hold the AnimationController needed for the
/// highlight pulse — [didUpdateWidget] compares the incoming [highlightKey]
/// against what this verse had last frame, and if it just changed (color
/// applied, changed, or cleared), fires a brief scale+glow pulse instead of
/// the highlight tint just appearing flat. Keyed by verse number in the
/// parent so Flutter reuses (rather than recreates) this state as the list
/// rebuilds on scroll/highlight updates.
class _VerseRow extends StatefulWidget {
  final ScriptureVerse verse;
  final String? highlightKey;
  final bool isSelected;
  final bool justChanged;
  final PulpitColors colors;
  final VoidCallback onTap;

  const _VerseRow({
    super.key,
    required this.verse,
    required this.highlightKey,
    required this.isSelected,
    required this.justChanged,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_VerseRow> createState() => _VerseRowState();
}

class _VerseRowState extends State<_VerseRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.045)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.045, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 60,
      ),
    ]).animate(_pulseController);
    _glow = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 70,
      ),
    ]).animate(_pulseController);
  }

  @override
  void didUpdateWidget(covariant _VerseRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Edge-triggered on the explicit `justChanged` flag the screen sets
    // right after a highlight upsert/remove succeeds — NOT on comparing old
    // vs new highlightKey directly. Highlight data also changes color when
    // it first loads from Supabase on chapter open (async, arrives a beat
    // after the verse text itself), which would false-trigger a pulse for
    // every already-highlighted verse on every chapter visit if we keyed
    // off the color alone. `justChanged` only flips true when the user
    // actually tapped a highlight color for this verse.
    if (widget.justChanged && !oldWidget.justChanged) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final highlightColor = widget.highlightKey != null
        ? kHighlightColors[widget.highlightKey]
        : null;
    // The pulse glows in whichever color the verse is transitioning to —
    // the new highlight color, or the accent if a highlight was just
    // cleared, so "removing" reads as a distinct event too.
    final glowColor = highlightColor ?? colors.accent;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: Container(
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: _glow.value > 0.01
                    ? [
                        BoxShadow(
                          color: glowColor.withValues(
                            alpha: 0.35 * _glow.value,
                          ),
                          blurRadius: 14 * _glow.value,
                          spreadRadius: 1.5 * _glow.value,
                        ),
                      ]
                    : null,
              ),
              child: child,
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? colors.accent.withValues(alpha: 0.14)
                : highlightColor?.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: widget.isSelected
                ? Border.all(color: colors.accent, width: 1.5)
                : highlightColor != null
                    ? Border(
                        left: BorderSide(color: highlightColor, width: 3),
                      )
                    : null,
          ),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${widget.verse.verseNumber}  ',
                  style: PulpitFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: colors.accent,
                    letterSpacing: 0.5,
                  ),
                ),
                TextSpan(
                  text: widget.verse.text,
                  style: PulpitFonts.cormorantGaramond(
                    fontSize: 22,
                    color: colors.textPrimary,
                    height: 1.9,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sheet body for "Compare Translations" — fetches [reference] in every
/// supported translation in parallel and renders each as its own card so a
/// pastor can scan wording differences at a glance.
class _TranslationCompareSheet extends StatefulWidget {
  final String reference;
  final PulpitColors colors;

  const _TranslationCompareSheet({
    required this.reference,
    required this.colors,
  });

  @override
  State<_TranslationCompareSheet> createState() =>
      _TranslationCompareSheetState();
}

class _TranslationCompareSheetState extends State<_TranslationCompareSheet> {
  bool _loading = true;
  final Map<String, ScripturePassage?> _passages = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait(
      _kBibleTranslations.map(
        (t) => scriptureService.getPassage(widget.reference, t['code']!),
      ),
    );
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _kBibleTranslations.length; i++) {
        _passages[_kBibleTranslations[i]['code']!] = results[i];
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.translate_rounded, size: 18, color: colors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.reference,
                      style: PulpitFonts.cormorantGaramond(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: CircularProgressIndicator(color: colors.accent),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: _kBibleTranslations.length,
                      itemBuilder: (ctx, i) {
                        final t = _kBibleTranslations[i];
                        final passage = _passages[t['code']];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
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
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.accent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      t['code']!,
                                      style: PulpitFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: colors.accent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      t['name']!,
                                      style: PulpitFonts.inter(
                                        fontSize: 11,
                                        color: colors.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                passage?.fullText ??
                                    'Not available for this reference',
                                style: PulpitFonts.cormorantGaramond(
                                  fontSize: 16,
                                  color: passage != null
                                      ? colors.textPrimary
                                      : colors.textSecondary.withValues(alpha: 0.6),
                                  height: 1.6,
                                  fontStyle: passage == null
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whole-Bible word/phrase search sheet for the Bible tab. Same
/// `searchScripture` API as the sermon editor's picker, but tapping a result
/// here jumps the reader to that verse instead of inserting a scripture
/// block — there's no sermon context to insert into from this screen.
class _WordSearchSheet extends StatefulWidget {
  final PulpitColors colors;
  final String translation;
  final void Function(String book, int chapter, int verse) onJump;

  const _WordSearchSheet({
    required this.colors,
    required this.translation,
    required this.onJump,
  });

  @override
  State<_WordSearchSheet> createState() => _WordSearchSheetState();
}

class _WordSearchSheetState extends State<_WordSearchSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  bool _searching = false;
  List<ScriptureSearchHit> _results = [];
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String raw) {
    setState(() => _query = raw);
    _debounce?.cancel();
    if (raw.trim().isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final results = await scriptureService.searchScripture(
        raw,
        widget.translation,
      );
      if (mounted && _query == raw) {
        setState(() {
          _results = results;
          _searching = false;
        });
      }
    });
  }

  /// Parses a single-verse reference like "1 Corinthians 13:4" (the shape
  /// API.Bible search results always come back in) into book/chapter/verse.
  ({String book, int chapter, int verse})? _parseRef(String ref) {
    final match = RegExp(r'^(.*?)\s+(\d+):(\d+)$').firstMatch(ref.trim());
    if (match == null) return null;
    final book = match.group(1)!.trim();
    final chapter = int.tryParse(match.group(2)!);
    final verse = int.tryParse(match.group(3)!);
    if (chapter == null || verse == null) return null;
    return (book: book, chapter: chapter, verse: verse);
  }

  void _tapResult(ScriptureSearchHit hit) {
    final parsed = _parseRef(hit.reference);
    if (parsed == null) return;
    HapticFeedback.selectionClick();
    widget.onJump(parsed.book, parsed.chapter, parsed.verse);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 16, color: colors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Search Scripture',
                    style: PulpitFonts.cormorantGaramond(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                style: PulpitFonts.inter(fontSize: 14, color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g. "shepherd" or "steadfast love"',
                  hintStyle: PulpitFonts.inter(color: colors.textSecondary, fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: colors.textSecondary, size: 18),
                  suffixIcon: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _controller.clear();
                            _onChanged('');
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
                onChanged: _onChanged,
              ),
            ),
            Divider(height: 1, color: colors.border),
            Expanded(child: _buildResults(colors)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(PulpitColors colors) {
    if (_query.trim().isEmpty) {
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
                'Tap a result to jump straight to it.',
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

    if (_results.isEmpty) {
      // Small bonus consistency touch — was a static Text with zero
      // animation, everywhere else on this screen has motion. No new
      // import needed for a plain fade, so kept lightweight for this
      // compact search-sheet context rather than pulling in the full
      // illustrated PulpitEmptyState (sized for full-page empty states).
      return Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 300),
          builder: (context, value, child) =>
              Opacity(opacity: value, child: child),
          child: Text(
            'No verses found for "$_query"',
            textAlign: TextAlign.center,
            style: PulpitFonts.inter(fontSize: 13, color: colors.textSecondary),
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      itemCount: _results.length,
      itemBuilder: (ctx, i) {
        final hit = _results[i];
        return GestureDetector(
          onTap: () => _tapResult(hit),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
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
                    Icon(Icons.menu_book_rounded, size: 14, color: colors.accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        hit.reference,
                        style: PulpitFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 16, color: colors.textSecondary),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  hit.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PulpitFonts.lora(fontSize: 13, color: colors.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Book -> chapter -> verse(s) selection wizard for the Bible tab — the
/// same procession used when inserting scripture into a sermon draft
/// (PremiumScripturePicker in sermon_editor_screen.dart), so choosing a
/// passage works identically everywhere in the app. Confirming hands back
/// exactly what was picked; "Read whole chapter instead" is offered at the
/// verse step for anyone who didn't actually want a narrow passage.
class _PassageSelectorSheet extends StatefulWidget {
  final PulpitColors colors;

  const _PassageSelectorSheet({required this.colors});

  @override
  State<_PassageSelectorSheet> createState() => _PassageSelectorSheetState();
}

/// Result of the passage-selection wizard, returned via Navigator.pop —
/// either a set of specific verses to show as a passage, or a request to
/// jump straight to the full chapter. Popping the sheet with this value
/// (rather than the sheet calling a parent-supplied callback that itself
/// pops and immediately opens another sheet) is what avoids the framework
/// crash described on [_showPassageSelector].
class _PassageWizardResult {
  final String book;
  final int chapter;
  final List<int> verses;
  final bool readFullChapter;

  const _PassageWizardResult({
    required this.book,
    required this.chapter,
    this.verses = const [],
    this.readFullChapter = false,
  });
}

class _PassageSelectorSheetState extends State<_PassageSelectorSheet> {
  int _step = 0; // 0 = book, 1 = chapter, 2 = verse(s)
  String? _selectedBook;
  int? _selectedChapter;
  final Set<int> _selectedVerses = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BibleBook> get _filteredBooks {
    if (_searchQuery.isEmpty) return bibleBooks;
    final q = _searchQuery.toLowerCase();
    return bibleBooks
        .where(
          (b) =>
              b.name.toLowerCase().contains(q) ||
              b.abbreviations.any((a) => a.toLowerCase().startsWith(q)),
        )
        .toList();
  }

  BibleBook? get _currentBook {
    if (_selectedBook == null) return null;
    try {
      return bibleBooks.firstWhere((b) => b.name == _selectedBook);
    } catch (_) {
      return null;
    }
  }

  int get _verseCount {
    final book = _currentBook;
    if (book == null || _selectedChapter == null) return 0;
    final idx = _selectedChapter! - 1;
    if (idx < 0 || idx >= book.chapters.length) return 0;
    return book.chapters[idx];
  }

  void _goToStep(int step) => setState(() => _step = step);

  /// Groups the selection into contiguous runs so "1-3, 7" reads as a real
  /// reference, matching the same helper pattern used in the main reader
  /// state and the sermon editor's picker.
  List<(int, int)> _runs() {
    final sorted = _selectedVerses.toList()..sort();
    final runs = <(int, int)>[];
    for (final n in sorted) {
      if (runs.isNotEmpty && runs.last.$2 == n - 1) {
        runs[runs.length - 1] = (runs.last.$1, n);
      } else {
        runs.add((n, n));
      }
    }
    return runs;
  }

  String get _selectionLabel {
    final runs = _runs();
    if (runs.isEmpty) return '';
    return runs.map((r) => r.$1 == r.$2 ? '${r.$1}' : '${r.$1}-${r.$2}').join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                if (_step > 0)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      if (_step == 1) {
                        setState(() => _selectedBook = null);
                        _goToStep(0);
                      } else if (_step == 2) {
                        setState(() {
                          _selectedChapter = null;
                          _selectedVerses.clear();
                        });
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
                  _step == 0
                      ? 'Choose Book'
                      : _step == 1
                          ? 'Choose Chapter'
                          : 'Choose Verse(s)',
                  style: PulpitFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: List.generate(3, (i) {
                final active = i <= _step;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                    height: 3,
                    decoration: BoxDecoration(
                      color: active ? colors.accent : colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: switch (_step) {
              0 => _buildBookStep(colors),
              1 => _buildChapterStep(colors),
              _ => _buildVerseStep(colors),
            },
          ),
        ],
      ),
    );
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
              hintStyle: PulpitFonts.inter(color: colors.textSecondary, fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: colors.textSecondary, size: 18),
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
                  style: PulpitFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary),
                ),
                trailing: Text(
                  '${book.chapters.length} ch.',
                  style: PulpitFonts.inter(fontSize: 12, color: colors.textSecondary),
                ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedBook = book.name;
                    _selectedChapter = null;
                    _selectedVerses.clear();
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
    final count = _currentBook?.chapters.length ?? 0;
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
              _selectedVerses.clear();
            });
            _goToStep(2);
          },
          child: Container(
            decoration: BoxDecoration(
              color: selected ? colors.accent : colors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? colors.accent : colors.border),
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
    final verseCount = _verseCount;
    return Column(
      children: [
        // The explicitly-requested escape hatch: pick a chapter but skip
        // verse selection entirely and just read the whole thing.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pop(
                context,
                _PassageWizardResult(
                  book: _selectedBook!,
                  chapter: _selectedChapter!,
                  readFullChapter: true,
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_stories_rounded, size: 15, color: colors.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Read whole chapter instead',
                    style: PulpitFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: colors.accent),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Container(height: 1, color: colors.border.withValues(alpha: 0.5)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'or choose verse(s)',
                  style: PulpitFonts.inter(fontSize: 11, color: colors.textSecondary),
                ),
              ),
              Expanded(
                child: Container(height: 1, color: colors.border.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
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
                    if (selected) {
                      _selectedVerses.remove(v);
                    } else {
                      _selectedVerses.add(v);
                    }
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: selected ? colors.accent.withValues(alpha: 0.15) : colors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? colors.accent : colors.border, width: selected ? 2 : 1),
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
          ),
        ),
        if (_selectedVerses.isNotEmpty)
          SafeArea(
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
                        Text(
                          '$_selectedBook $_selectedChapter:$_selectionLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PulpitFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: colors.textPrimary),
                        ),
                        Text(
                          _selectedVerses.length == 1 ? '1 verse' : '${_selectedVerses.length} verses',
                          style: PulpitFonts.inter(fontSize: 12, color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      final verses = _selectedVerses.toList()..sort();
                      Navigator.pop(
                        context,
                        _PassageWizardResult(
                          book: _selectedBook!,
                          chapter: _selectedChapter!,
                          verses: verses,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'View Passage',
                        style: PulpitFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: colors.background),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Shows exactly the verse(s) picked in [_PassageSelectorSheet] — not the
/// surrounding chapter — with translation switching, copy/add-to-sermon
/// actions, and a "Read full chapter" button for expanding out when wanted.
class _PassageResultSheet extends StatefulWidget {
  final PulpitColors colors;
  final String book;
  final int chapter;
  final String translation;
  final List<int> verseNumbers;
  final void Function(String ref, String translation)? onAddToSermon;

  const _PassageResultSheet({
    required this.colors,
    required this.book,
    required this.chapter,
    required this.translation,
    required this.verseNumbers,
    this.onAddToSermon,
  });

  @override
  State<_PassageResultSheet> createState() => _PassageResultSheetState();
}

class _PassageResultSheetState extends State<_PassageResultSheet> {
  late String _translation;
  List<ScriptureVerse> _verses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _translation = widget.translation;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final chapterVerses = await scriptureService.getChapter(widget.book, widget.chapter, _translation);
    if (!mounted) return;
    final byNumber = {for (final v in chapterVerses) v.verseNumber: v};
    setState(() {
      _verses = [for (final n in widget.verseNumbers) if (byNumber[n] != null) byNumber[n]!];
      _loading = false;
    });
  }

  Future<void> _switchTranslation(String code) async {
    if (code == _translation) return;
    HapticFeedback.selectionClick();
    setState(() => _translation = code);
    await _load();
  }

  List<(int, int)> _runs() {
    final sorted = List<int>.from(widget.verseNumbers)..sort();
    final runs = <(int, int)>[];
    for (final n in sorted) {
      if (runs.isNotEmpty && runs.last.$2 == n - 1) {
        runs[runs.length - 1] = (runs.last.$1, n);
      } else {
        runs.add((n, n));
      }
    }
    return runs;
  }

  String get _refLabel {
    final joined = _runs().map((r) => r.$1 == r.$2 ? '${r.$1}' : '${r.$1}-${r.$2}').join(', ');
    return '${widget.book} ${widget.chapter}:$joined';
  }

  void _copy() {
    final text = _verses.map((v) => '${v.verseNumber} ${v.text}').join(' ');
    Clipboard.setData(ClipboardData(text: '$_refLabel ($_translation)\n$text'));
    HapticFeedback.lightImpact();
  }

  void _addToSermon() {
    final add = widget.onAddToSermon;
    if (add == null) return;
    HapticFeedback.mediumImpact();
    // One scripture block per contiguous run, matching how multi-select
    // insert works everywhere else (Bible tab's main selection bar, and
    // the sermon editor's own picker).
    for (final r in _runs()) {
      final ref = r.$1 == r.$2
          ? '${widget.book} ${widget.chapter}:${r.$1}'
          : '${widget.book} ${widget.chapter}:${r.$1}-${r.$2}';
      add(ref, _translation);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: colors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.format_quote_rounded, color: colors.accent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _refLabel,
                        style: PulpitFonts.cormorantGaramond(fontSize: 20, fontWeight: FontWeight.w700, color: colors.textPrimary),
                      ),
                      Text(
                        _translation,
                        style: PulpitFonts.inter(fontSize: 11, color: colors.textSecondary, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.border.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.close_rounded, color: colors.textSecondary, size: 16),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _verses.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No content available for $_refLabel ($_translation).',
                          style: PulpitFonts.inter(color: colors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _verses
                              .map(
                                (verse) => Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${verse.verseNumber}  ',
                                          style: PulpitFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: colors.accent,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        TextSpan(
                                          text: verse.text,
                                          style: PulpitFonts.cormorantGaramond(
                                            fontSize: 21,
                                            color: colors.textPrimary,
                                            height: 1.8,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
          ),
          Container(height: 1, color: colors.border.withValues(alpha: 0.4)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _kBibleTranslations.map((t) {
                  final code = t['code']!;
                  final isSelected = code == _translation;
                  return GestureDetector(
                    onTap: () => _switchTranslation(code),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: isSelected ? colors.accent : colors.border.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isSelected ? colors.accent : colors.border.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        code,
                        style: PulpitFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? colors.background : colors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  _resultActionIcon(colors, icon: Icons.content_copy_rounded, label: 'Copy', onTap: _copy),
                  if (widget.onAddToSermon != null) ...[
                    const SizedBox(width: 8),
                    _resultActionIcon(colors, icon: Icons.add_rounded, label: 'Add to Sermon', onTap: _addToSermon, primary: true),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context, true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_stories_rounded, size: 14, color: colors.accent),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Read full chapter',
                                overflow: TextOverflow.ellipsis,
                                style: PulpitFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: colors.accent),
                              ),
                            ),
                          ],
                        ),
                      ),
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

  Widget _resultActionIcon(
    PulpitColors colors, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: primary ? colors.accent : colors.card,
          borderRadius: BorderRadius.circular(12),
          border: primary ? null : Border.all(color: colors.border),
        ),
        child: Icon(icon, size: 18, color: primary ? colors.background : colors.accent),
      ),
    );
  }
}
