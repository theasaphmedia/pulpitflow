import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/sermon_model.dart';
import '../../../shared/state/sermon_provider.dart';
import '../../../shared/state/theme_provider.dart';
import '../../../shared/widgets/pulpit_ui.dart'
    show PulpitEmptyState, PulpitEmptyStateType;

// ── Scripture of the Week data ────────────────────────────────────────────────

class _WeeklyVerse {
  final String ref;
  final String text;
  final String theme;
  final String prompt;
  const _WeeklyVerse({
    required this.ref,
    required this.text,
    required this.theme,
    required this.prompt,
  });
}

const List<_WeeklyVerse> _kWeeklyVerses = [
  _WeeklyVerse(
    ref: 'John 3:16',
    text: 'For God so loved the world, that he gave his only Son...',
    theme: 'The Heart of the Gospel',
    prompt: 'What does sacrificial love look like in your congregation today?',
  ),
  _WeeklyVerse(
    ref: 'Romans 8:28',
    text:
        'And we know that in all things God works for the good of those who love him...',
    theme: 'Sovereign Purpose',
    prompt: 'How can you help your people find purpose in difficult seasons?',
  ),
  _WeeklyVerse(
    ref: 'Isaiah 40:31',
    text: 'But those who hope in the Lord will renew their strength...',
    theme: 'Renewed Strength',
    prompt:
        'Where does your community most need God\'s renewing power right now?',
  ),
  _WeeklyVerse(
    ref: 'Jeremiah 29:11',
    text: '"For I know the plans I have for you," declares the Lord...',
    theme: 'Hope and a Future',
    prompt:
        'How does God\'s long-term plan reshape how we face short-term pain?',
  ),
  _WeeklyVerse(
    ref: 'Philippians 4:13',
    text: 'I can do all this through him who gives me strength.',
    theme: 'Strength in Christ',
    prompt:
        'What is the difference between self-confidence and Christ-confidence?',
  ),
  _WeeklyVerse(
    ref: 'Psalm 23:1',
    text: 'The Lord is my shepherd, I lack nothing.',
    theme: 'The Good Shepherd',
    prompt:
        'In what areas of life does your congregation need to experience God\'s provision?',
  ),
  _WeeklyVerse(
    ref: 'Matthew 5:16',
    text:
        'Let your light shine before others, that they may see your good deeds...',
    theme: 'Living as Light',
    prompt: 'What practical ways can the church shine in your local community?',
  ),
  _WeeklyVerse(
    ref: 'Proverbs 3:5-6',
    text:
        'Trust in the Lord with all your heart and lean not on your own understanding...',
    theme: 'Walking in Trust',
    prompt: 'What does it mean to truly surrender our plans and wisdom to God?',
  ),
  _WeeklyVerse(
    ref: 'Ephesians 2:8-9',
    text:
        'For it is by grace you have been saved, through faith — and this is not from yourselves...',
    theme: 'Grace Alone',
    prompt:
        'How does understanding grace transform how we treat others and ourselves?',
  ),
  _WeeklyVerse(
    ref: 'Romans 12:2',
    text:
        'Do not conform to the pattern of this world, but be transformed by the renewing of your mind...',
    theme: 'Transformed Minds',
    prompt:
        'What cultural patterns are most challenging the church to resist today?',
  ),
  _WeeklyVerse(
    ref: 'Matthew 6:33',
    text:
        'But seek first his kingdom and his righteousness, and all these things will be given to you as well.',
    theme: 'First Things First',
    prompt:
        'What competes with God\'s kingdom for first place in your congregation\'s priorities?',
  ),
  _WeeklyVerse(
    ref: '2 Timothy 3:16-17',
    text:
        'All Scripture is God-breathed and is useful for teaching, rebuking, correcting...',
    theme: 'The Power of Scripture',
    prompt: 'How can you help your people love and apply God\'s Word daily?',
  ),
  _WeeklyVerse(
    ref: 'Hebrews 11:1',
    text:
        'Now faith is confidence in what we hope for and assurance about what we do not see.',
    theme: 'The Nature of Faith',
    prompt:
        'Where does your community need to step out in faith despite uncertainty?',
  ),
  _WeeklyVerse(
    ref: '1 Corinthians 13:13',
    text:
        'And now these three remain: faith, hope and love. But the greatest of these is love.',
    theme: 'The Greatest of These',
    prompt:
        'How does love as a foundation change the way we lead and shepherd?',
  ),
  _WeeklyVerse(
    ref: 'Galatians 5:22-23',
    text:
        'But the fruit of the Spirit is love, joy, peace, forbearance, kindness...',
    theme: 'Fruit of the Spirit',
    prompt:
        'Which fruit of the Spirit does your congregation most need to cultivate right now?',
  ),
  _WeeklyVerse(
    ref: 'Psalm 46:10',
    text: 'He says, "Be still, and know that I am God..."',
    theme: 'Stillness and Knowing God',
    prompt:
        'In a busy, anxious world, how do we help people practice the discipline of stillness?',
  ),
  _WeeklyVerse(
    ref: 'Acts 1:8',
    text:
        'But you will receive power when the Holy Spirit comes on you; and you will be my witnesses...',
    theme: 'Empowered Witnesses',
    prompt:
        'What does Spirit-empowered witness look like in your specific city and context?',
  ),
  _WeeklyVerse(
    ref: 'James 1:2-3',
    text:
        'Consider it pure joy, my brothers and sisters, whenever you face trials of many kinds...',
    theme: 'Joy Through Trials',
    prompt:
        'How can suffering become a doorway to deeper faith rather than a stumbling block?',
  ),
  _WeeklyVerse(
    ref: 'Micah 6:8',
    text:
        'He has shown you, O mortal, what is good. And what does the Lord require of you?...',
    theme: 'Justice, Mercy, Humility',
    prompt:
        'How does your church embody justice and mercy in tangible, practical ways?',
  ),
  _WeeklyVerse(
    ref: 'Revelation 21:5',
    text: 'He who was seated on the throne said, "I am making everything new!"',
    theme: 'All Things New',
    prompt:
        'How does the hope of renewal in Christ reshape how we engage a broken world today?',
  ),
];

/// Pairs a sermon with the specific block ID that contains a scripture ref.
class _SermonHit {
  final Sermon sermon;
  final String blockId;
  const _SermonHit({required this.sermon, required this.blockId});
}

/// Groups sermons by scripture reference so a pastor can quickly see
/// which of their sermons touch a given passage.
class ConcordanceScreen extends ConsumerStatefulWidget {
  const ConcordanceScreen({super.key});

  @override
  ConsumerState<ConcordanceScreen> createState() => _ConcordanceScreenState();
}

class _ConcordanceScreenState extends ConsumerState<ConcordanceScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Returns map of ref → list of [_SermonHit]s that contain it, sorted by ref.
  Map<String, List<_SermonHit>> _buildConcordance(List<Sermon> sermons) {
    final map = <String, List<_SermonHit>>{};
    for (final sermon in sermons) {
      for (final block in sermon.blocks) {
        if (block.type == BlockType.scripture) {
          final ref = block.scriptureRef ?? block.content;
          if (ref.isEmpty) continue;
          map.putIfAbsent(ref, () => []);
          // Avoid duplicates if same ref appears twice in one sermon —
          // but do record it if a different block in the same sermon uses it.
          final alreadyHasSameBlock = map[ref]!.any(
            (h) => h.sermon.id == sermon.id && h.blockId == block.id,
          );
          if (!alreadyHasSameBlock) {
            map[ref]!.add(_SermonHit(sermon: sermon, blockId: block.id));
          }
        }
      }
    }
    // Sort refs alphabetically
    final sorted = Map.fromEntries(
      map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final sermonsAsync = ref.watch(sermonProvider);
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, colors),
            _buildSearchBar(colors),
            Expanded(
              child: sermonsAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(color: colors.accent),
                ),
                error: (e, _) => Center(
                  child: Text(
                    'Error loading sermons',
                    style: PulpitFonts.inter(color: colors.textSecondary),
                  ),
                ),
                data: (sermons) {
                  if (sermons.isEmpty) {
                    return _buildEmptySermons(colors);
                  }

                  final concordance = _buildConcordance(sermons);

                  // Count unique refs & unique sermons
                  final totalRefs = concordance.length;
                  final totalSermons = sermons.length;

                  // Filter by search query — matches ref text OR sermon title
                  final q = _query.toLowerCase();
                  final filtered = _query.isEmpty
                      ? concordance
                      : Map.fromEntries(
                          concordance.entries.where(
                            (e) =>
                                e.key.toLowerCase().contains(q) ||
                                e.value.any(
                                  (h) =>
                                      h.sermon.title.toLowerCase().contains(q),
                                ),
                          ),
                        );

                  if (filtered.isEmpty) {
                    return _buildEmptySearch(colors);
                  }

                  // Scripture of the Week — seeded by current week number
                  final weekNum = _weekOfYear();
                  final sotw = _kWeeklyVerses[weekNum % _kWeeklyVerses.length];
                  final showSotw = _query.isEmpty;

                  return Column(
                    children: [
                      _buildStats(colors, totalRefs, totalSermons),
                      Expanded(
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          itemCount: filtered.length + (showSotw ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (showSotw && index == 0) {
                              return _buildScriptureOfTheWeek(
                                sotw,
                                weekNum,
                                colors,
                              );
                            }
                            final i = index - (showSotw ? 1 : 0);
                            final entry = filtered.entries.elementAt(i);
                            return _ConcordanceEntry(
                              scriptureRef: entry.key,
                              hits: entry.value,
                              colors: colors,
                              index: i,
                            ).animate().fadeIn(
                              delay: Duration(milliseconds: 20 * (i % 20)),
                              duration: 300.ms,
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Scripture of the Week helpers ────────────────────────────────────────────

  static int _weekOfYear() {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final dayOfYear = now.difference(startOfYear).inDays + 1;
    return ((dayOfYear - 1) ~/ 7) + 1; // 1-based week number
  }

  /// Returns a readable foreground for content placed on the accent gradient.
  Color _onAccent(Color accent) =>
      accent.computeLuminance() > 0.35 ? const Color(0xFF1A1A1A) : Colors.white;

  Widget _buildScriptureOfTheWeek(
    _WeeklyVerse verse,
    int weekNum,
    PulpitColors colors,
  ) {
    final fg = _onAccent(colors.accent);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            colors.accent.withValues(alpha: 0.85),
            colors.accent.withValues(alpha: 0.55),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background decorative circle
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            left: -10,
            bottom: -30,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: label + week badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: fg.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 11,
                            color: fg.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'SCRIPTURE OF THE WEEK',
                            style: PulpitFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: fg.withValues(alpha: 0.9),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Week $weekNum',
                      style: PulpitFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: fg.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Theme title
                Text(
                  verse.theme,
                  style: PulpitFonts.cormorantGaramond(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                // Scripture reference
                Text(
                  verse.ref,
                  style: PulpitFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                // Verse text excerpt
                Text(
                  '"${verse.text}"',
                  style: PulpitFonts.lora(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: fg.withValues(alpha: 0.9),
                    height: 1.55,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                // Reflection prompt
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 14,
                        color: fg.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          verse.prompt,
                          style: PulpitFonts.inter(
                            fontSize: 12,
                            color: fg.withValues(alpha: 0.88),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Action row
                Row(
                  children: [
                    // Copy reference
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Clipboard.setData(ClipboardData(text: verse.ref));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${verse.ref} copied',
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
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: fg.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: fg.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded, size: 13, color: fg),
                            const SizedBox(width: 5),
                            Text(
                              'Copy Ref',
                              style: PulpitFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: fg,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Start sermon
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        _startSermonFromSotw(verse);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_rounded,
                              size: 13,
                              color: const Color(0xFF1A1A1A),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Start Sermon',
                              style: PulpitFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.06, end: 0);
  }

  Future<void> _startSermonFromSotw(_WeeklyVerse verse) async {
    final colors = PulpitColors.of(ref.read(themeProvider));
    try {
      final sermon = await ref
          .read(sermonProvider.notifier)
          .addSermon(
            verse.theme,
            'NIV',
            blocks: [
              SermonBlock.scripture(verse.ref, translation: 'NIV'),
              SermonBlock.text(''),
            ],
          );
      if (mounted) {
        context.push('/sermons/${sermon.id}/edit');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not create sermon. Please try again.',
              style: PulpitFonts.inter(color: colors.background),
            ),
            backgroundColor: colors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          ),
        );
      }
    }
  }

  Widget _buildHeader(BuildContext context, PulpitColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              context.pop();
            },
            icon: Icon(
              Icons.arrow_back_rounded,
              color: colors.textPrimary,
              size: 22,
            ),
            tooltip: 'Back',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scripture Concordance',
                  style: PulpitFonts.cormorantGaramond(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  "Every verse you've ever preached",
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
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildSearchBar(PulpitColors colors) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: TextField(
        controller: _searchCtrl,
        style: PulpitFonts.inter(fontSize: 14, color: colors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search references or sermon titles…',
          hintStyle: PulpitFonts.inter(
            color: colors.textSecondary,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: colors.textSecondary,
            size: 18,
          ),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear_rounded,
                    color: colors.textSecondary,
                    size: 16,
                  ),
                  tooltip: 'Clear search',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 300.ms);
  }

  Widget _buildStats(PulpitColors colors, int totalRefs, int totalSermons) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.accent.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          _statChip(colors, '$totalRefs', 'unique refs'),
          Container(
            width: 1,
            height: 28,
            color: colors.border,
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          _statChip(colors, '$totalSermons', 'sermons'),
          const Spacer(),
          Icon(
            Icons.auto_stories_rounded,
            color: colors.accent.withValues(alpha: 0.5),
            size: 18,
          ),
        ],
      ),
    );
  }

  Widget _statChip(PulpitColors colors, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: PulpitFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: colors.accent,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: PulpitFonts.inter(fontSize: 12, color: colors.textSecondary),
        ),
      ],
    );
  }

  // Both of these were bare, unanimated Columns — same fix as the other
  // list screens: wire in the shared illustrated PulpitEmptyState instead
  // of a one-off. No dedicated concordance illustration exists, so these
  // ride on `sermons`/`search` with this screen's own copy overridden via
  // customTitle/customSubtitle.
  Widget _buildEmptySermons(PulpitColors colors) {
    return const PulpitEmptyState(
      type: PulpitEmptyStateType.sermons,
      customTitle: 'No sermons yet',
      customSubtitle: "Add scripture blocks to your sermons\nand they'll appear here.",
    );
  }

  Widget _buildEmptySearch(PulpitColors colors) {
    return PulpitEmptyState(
      type: PulpitEmptyStateType.search,
      customTitle: 'No matches for "$_query"',
      customSubtitle: 'Try a different word or reference.',
    );
  }
}

// ── Concordance Entry ──────────────────────────────────────────────────────────

class _ConcordanceEntry extends StatefulWidget {
  final String scriptureRef;
  final List<_SermonHit> hits;
  final PulpitColors colors;
  final int index;

  const _ConcordanceEntry({
    required this.scriptureRef,
    required this.hits,
    required this.colors,
    required this.index,
  });

  @override
  State<_ConcordanceEntry> createState() => _ConcordanceEntryState();
}

class _ConcordanceEntryState extends State<_ConcordanceEntry> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    // Count unique sermons (same sermon can appear with multiple blocks)
    final count = widget.hits.map((h) => h.sermon.id).toSet().length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _expanded
              ? colors.accent.withValues(alpha: 0.3)
              : colors.border,
        ),
      ),
      child: Column(
        children: [
          // Header row
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  // Book icon
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.menu_book_rounded,
                      size: 16,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Reference
                  Expanded(
                    child: Text(
                      widget.scriptureRef,
                      style: PulpitFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  // Count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      count == 1 ? '1 sermon' : '$count sermons',
                      style: PulpitFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: colors.textSecondary,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded sermon list
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: _expanded
                ? Column(
                    children: [
                      Divider(
                        height: 1,
                        color: colors.border,
                        indent: 14,
                        endIndent: 14,
                      ),
                      ...widget.hits.asMap().entries.map((entry) {
                        final hit = entry.value;
                        final isLast = entry.key == widget.hits.length - 1;
                        return _SermonRef(
                          sermon: hit.sermon,
                          colors: colors,
                          isLast: isLast,
                          onTap: () => context.push(
                            '/sermons/${hit.sermon.id}/edit'
                            '?highlightBlock=${hit.blockId}',
                          ),
                        );
                      }),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ── Sermon ref row inside expanded entry ──────────────────────────────────────

class _SermonRef extends StatelessWidget {
  final Sermon sermon;
  final PulpitColors colors;
  final bool isLast;
  final VoidCallback onTap;

  const _SermonRef({
    required this.sermon,
    required this.colors,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (sermon.status) {
      SermonStatus.draft => colors.textSecondary,
      SermonStatus.ready => const Color(0xFF22C55E),
      SermonStatus.preached => colors.accent,
    };
    final statusLabel = switch (sermon.status) {
      SermonStatus.draft => 'Draft',
      SermonStatus.ready => 'Ready',
      SermonStatus.preached => 'Preached',
    };

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 10, 14, isLast ? 12 : 6),
        child: Row(
          children: [
            const SizedBox(width: 48), // align with title above

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sermon.title,
                    style: PulpitFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sermon.series != null && sermon.series!.isNotEmpty)
                    Text(
                      sermon.series!,
                      style: PulpitFonts.inter(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusLabel,
                style: PulpitFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: colors.textSecondary.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
