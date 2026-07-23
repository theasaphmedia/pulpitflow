import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/services/word_study_service.dart';
import '../../../shared/state/theme_provider.dart';

class WordStudyScreen extends ConsumerStatefulWidget {
  /// If launched from the editor/reader, a word can be pre-filled.
  final String? initialWord;
  const WordStudyScreen({super.key, this.initialWord});

  @override
  ConsumerState<WordStudyScreen> createState() => _WordStudyScreenState();
}

class _WordStudyScreenState extends ConsumerState<WordStudyScreen> {
  late final TextEditingController _searchCtrl;
  final FocusNode _focusNode = FocusNode();

  WordStudyResult? _result;
  bool _loading = false;
  String? _error;
  List<String> _recentSearches = [];

  static const _kRecentKey = 'word_study_recent';
  static const _kMaxRecent = 10;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.initialWord ?? '');
    _loadRecent();
    if (widget.initialWord != null && widget.initialWord!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentSearches = prefs.getStringList(_kRecentKey) ?? [];
    });
  }

  Future<void> _saveRecent(String word) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = [
      word,
      ..._recentSearches.where((w) => w.toLowerCase() != word.toLowerCase()),
    ].take(_kMaxRecent).toList();
    await prefs.setStringList(_kRecentKey, updated);
    setState(() => _recentSearches = updated);
  }

  Future<void> _search() async {
    final word = _searchCtrl.text.trim();
    if (word.isEmpty) return;

    _focusNode.unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await wordStudyService.study(word);
      await _saveRecent(word);
      if (mounted) {
        setState(() {
          _result = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        // Word Study is now a bottom-nav tab root as well as still being
        // reachable via a push from VOTD History — only show a back arrow
        // when there's actually something to pop back to.
        leading: context.canPop()
            ? IconButton(
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
              )
            : null,
        title: Text(
          'Word Study',
          style: PulpitFonts.cormorantGaramond(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        actions: [
          if (_result != null)
            IconButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                _copyResult();
              },
              icon: Icon(
                Icons.copy_rounded,
                color: colors.textSecondary,
                size: 20,
              ),
              tooltip: 'Copy study',
            ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(colors),
          Expanded(
            child: _loading
                ? _buildLoading(colors)
                : _error != null
                ? _buildError(colors)
                : _result != null
                ? _buildResult(colors, _result!)
                : _buildEmpty(colors),
          ),
        ],
      ),
    );
  }

  // ── Search bar ───────────────────────────────────────────────────────────

  Widget _buildSearchBar(PulpitColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _focusNode,
              style: PulpitFonts.cormorantGaramond(
                fontSize: 18,
                color: colors.textPrimary,
              ),
              textCapitalization: TextCapitalization.none,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                // Was 'e.g. grace  •  world in John 3:16' — that plus the
                // prefix icon and a serif font at 17px was too long for a
                // 360dp phone and clipped mid-word. Shortened so it
                // reliably fits on one line without truncating.
                hintText: 'e.g. grace  •  John 3:16',
                hintStyle: PulpitFonts.cormorantGaramond(
                  fontSize: 17,
                  color: colors.textSecondary.withValues(alpha: 0.5),
                  fontStyle: FontStyle.italic,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: colors.accent,
                  size: 20,
                ),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _searchCtrl.clear();
                          setState(() {
                            _result = null;
                            _error = null;
                          });
                        },
                        icon: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                        tooltip: 'Clear',
                      )
                    : null,
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
                  borderSide: BorderSide(color: colors.accent, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              _search();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: colors.accent.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                'Study',
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
    );
  }

  // ── States ───────────────────────────────────────────────────────────────

  Widget _buildLoading(PulpitColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: colors.accent),
          const SizedBox(height: 20),
          Text(
            'Searching the ancient texts...',
            style: PulpitFonts.cormorantGaramond(
              fontSize: 18,
              color: colors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(PulpitColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: colors.error),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: PulpitFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              style: PulpitFonts.inter(
                fontSize: 13,
                color: colors.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _search();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Try again',
                  style: PulpitFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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

  Widget _buildEmpty(PulpitColors colors) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Intro card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.accent.withValues(alpha: 0.12),
                  colors.accent.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.accent.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'αβγ',
                      style: PulpitFonts.inter(
                        fontSize: 22,
                        color: colors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Biblical Lexicon',
                      style: PulpitFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Type any word or phrase to uncover its original Hebrew, Aramaic, or Greek meaning — the root, the depth, and the preacher\'s insight hidden in the original text.',
                  style: PulpitFonts.cormorantGaramond(
                    fontSize: 16,
                    color: colors.textSecondary,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Tip banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.tips_and_updates_rounded,
                  size: 15,
                  color: colors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Search a word, a phrase, or add a verse — e.g. '
                    '"world in John 3:16" to get the exact meaning in that passage.',
                    style: PulpitFonts.inter(
                      fontSize: 12,
                      color: colors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Example searches
          Text(
            'TRY THESE',
            style: PulpitFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'agape',
              'logos',
              'hesed',
              'shalom',
              'grace',
              'world in John 3:16',
              'faith',
              'blood in Hebrews 9:22',
              'covenant',
              'repentance',
            ].map((w) => _exampleChip(colors, w)).toList(),
          ),

          if (_recentSearches.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              'RECENT',
              style: PulpitFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            ..._recentSearches.map((w) => _recentItem(colors, w)),
          ],
        ],
      ),
    );
  }

  Widget _exampleChip(PulpitColors colors, String word) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _searchCtrl.text = word;
        _search();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.border),
        ),
        child: Text(
          word,
          style: PulpitFonts.cormorantGaramond(
            fontSize: 16,
            color: colors.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _recentItem(PulpitColors colors, String word) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        _searchCtrl.text = word;
        _search();
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 16, color: colors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                word,
                style: PulpitFonts.inter(fontSize: 14, color: colors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.north_west_rounded,
              size: 14,
              color: colors.textSecondary.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  // ── Result ───────────────────────────────────────────────────────────────

  Widget _buildResult(PulpitColors colors, WordStudyResult r) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero card
          _buildHeroCard(colors, r),
          const SizedBox(height: 16),

          // Full definition
          _buildSection(
            colors,
            icon: Icons.auto_stories_rounded,
            title: 'Definition',
            child: Text(
              r.fullDefinition,
              style: PulpitFonts.cormorantGaramond(
                fontSize: 17,
                color: colors.textPrimary,
                height: 1.8,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Theological significance
          _buildSection(
            colors,
            icon: Icons.lightbulb_rounded,
            title: 'Theological Significance',
            accent: true,
            child: Text(
              r.theologicalSignificance,
              style: PulpitFonts.cormorantGaramond(
                fontSize: 17,
                color: colors.textPrimary,
                height: 1.8,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Preacher's insight
          _buildSection(
            colors,
            icon: Icons.record_voice_over_rounded,
            title: "Preacher's Insight",
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.accent.withValues(alpha: 0.2)),
              ),
              child: Text(
                '"${r.preachersInsight}"',
                style: PulpitFonts.cormorantGaramond(
                  fontSize: 18,
                  color: colors.textPrimary,
                  height: 1.7,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Key usages
          if (r.keyUsages.isNotEmpty)
            _buildSection(
              colors,
              icon: Icons.menu_book_rounded,
              title: 'Key Usages in Scripture',
              child: Column(
                children: r.keyUsages
                    .map(
                      (u) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: colors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                u,
                                style: PulpitFonts.cormorantGaramond(
                                  fontSize: 16,
                                  color: colors.textPrimary,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          if (r.keyUsages.isNotEmpty) const SizedBox(height: 12),

          // Related words
          if (r.relatedWords.isNotEmpty)
            _buildSection(
              colors,
              icon: Icons.link_rounded,
              title: 'Related Words',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: r.relatedWords
                    .map(
                      (w) => GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          final wordOnly = w.contains('(')
                              ? w.substring(0, w.indexOf('(')).trim()
                              : w;
                          _searchCtrl.text = wordOnly;
                          _search();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: colors.accent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            w,
                            style: PulpitFonts.inter(
                              fontSize: 12,
                              color: colors.accent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(PulpitColors colors, WordStudyResult r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.accent.withValues(alpha: 0.15),
            colors.accent.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Original script + language badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.originalScript.isNotEmpty)
                      Text(
                        r.originalScript,
                        style: PulpitFonts.cormorantGaramond(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: colors.accent,
                          height: 1.1,
                        ),
                      ),
                    if (r.transliteration.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        r.transliteration,
                        style: PulpitFonts.inter(
                          fontSize: 14,
                          color: colors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      r.originalLanguage,
                      style: PulpitFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.background,
                      ),
                    ),
                  ),
                  if (r.strongsNumber.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      r.strongsNumber,
                      style: PulpitFonts.inter(
                        fontSize: 11,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: colors.accent.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          // Root meaning
          Text(
            'ROOT MEANING',
            style: PulpitFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            r.rootMeaning,
            style: PulpitFonts.cormorantGaramond(
              fontSize: 20,
              color: colors.textPrimary,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    PulpitColors colors, {
    required IconData icon,
    required String title,
    required Widget child,
    bool accent = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent ? colors.accent.withValues(alpha: 0.06) : colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent ? colors.accent.withValues(alpha: 0.2) : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: PulpitFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  void _copyResult() {
    if (_result == null) return;
    final r = _result!;
    final text =
        '''
WORD STUDY: ${r.word.toUpperCase()}
${r.originalScript} (${r.transliteration}) · ${r.originalLanguage} · ${r.strongsNumber}

ROOT MEANING
${r.rootMeaning}

DEFINITION
${r.fullDefinition}

THEOLOGICAL SIGNIFICANCE
${r.theologicalSignificance}

PREACHER'S INSIGHT
"${r.preachersInsight}"

KEY USAGES
${r.keyUsages.map((u) => '• $u').join('\n')}

RELATED WORDS
${r.relatedWords.join(', ')}
''';
    Clipboard.setData(ClipboardData(text: text));
    final colors = PulpitColors.of(ref.read(themeProvider));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Word study copied',
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
