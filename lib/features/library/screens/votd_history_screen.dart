import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/scripture_model.dart';
import '../../../data/services/bible_api_service.dart';
import '../../../shared/state/sermon_provider.dart';
import '../../../shared/state/theme_provider.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

// Must match the list in bible_api_service.dart exactly.
const List<String> _votdRefs = [
  'John 3:16', 'Romans 8:28', 'Philippians 4:13', 'Jeremiah 29:11',
  'Isaiah 40:31', 'Psalm 23:1', 'Proverbs 3:5-6', 'Romans 5:1',
  'Ephesians 2:8', 'Hebrews 11:1', 'Matthew 6:33', 'Joshua 1:9',
  'Romans 8:38-39', 'Psalm 46:1', '2 Timothy 1:7', 'Galatians 2:20',
  'John 14:6', 'Philippians 4:7', 'Isaiah 41:10', 'Psalm 119:105',
  'Romans 12:2', 'Colossians 3:23', '1 Corinthians 10:13', 'Matthew 11:28',
  'John 15:5', '2 Corinthians 5:17', 'Psalm 27:1', 'Romans 1:16',
  'Ephesians 6:10', 'James 1:5',
];

String _refForDate(DateTime date) {
  final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays;
  return _votdRefs[dayOfYear % _votdRefs.length];
}

String _monthName(int month) => const [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ][month];

// ── Screen ─────────────────────────────────────────────────────────────────────

class VotdHistoryScreen extends ConsumerStatefulWidget {
  const VotdHistoryScreen({super.key});

  @override
  ConsumerState<VotdHistoryScreen> createState() => _VotdHistoryScreenState();
}

class _VotdHistoryScreenState extends ConsumerState<VotdHistoryScreen> {
  /// Generates the last [count] days starting from today.
  List<DateTime> get _days {
    final today = DateTime.now();
    return List.generate(
      30,
      (i) => DateTime(today.year, today.month, today.day - i),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);
    final days = _days;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, colors),
            Expanded(
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                itemCount: days.length,
                itemBuilder: (context, i) {
                  final day = days[i];
                  final ref = _refForDate(day);
                  final isToday = i == 0;
                  return _VotdDayCard(
                    date: day,
                    reference: ref,
                    isToday: isToday,
                    colors: colors,
                    index: i,
                  ).animate().fadeIn(
                        delay: Duration(milliseconds: 20 * (i % 15)),
                        duration: 300.ms,
                      );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
                  'Daily Verse Archive',
                  style: PulpitFonts.cormorantGaramond(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  'Last 30 days of verses',
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
}

// ── Day Card ────────────────────────────────────────────────────────────────────

class _VotdDayCard extends ConsumerStatefulWidget {
  final DateTime date;
  final String reference;
  final bool isToday;
  final PulpitColors colors;
  final int index;

  const _VotdDayCard({
    required this.date,
    required this.reference,
    required this.isToday,
    required this.colors,
    required this.index,
  });

  @override
  ConsumerState<_VotdDayCard> createState() => _VotdDayCardState();
}

class _VotdDayCardState extends ConsumerState<_VotdDayCard> {
  bool _expanded = false;
  bool _loading = false;
  ScripturePassage? _passage;

  // ignore: unused_element
  String get _dateLabel {
    if (widget.isToday) return 'Today';
    final d = widget.date;
    return '${_monthName(d.month)} ${d.day}';
  }

  Future<void> _loadPassage() async {
    if (_passage != null || _loading) return;
    setState(() => _loading = true);
    try {
      final p = await scriptureService.getPassage(widget.reference, 'KJV');
      if (mounted) setState(() => _passage = p);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isToday
              ? colors.accent.withValues(alpha: 0.4)
              : _expanded
                  ? colors.accent.withValues(alpha: 0.2)
                  : colors.border,
          width: widget.isToday ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header row
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
              if (!_expanded) _loadPassage();
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  // Date badge
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: widget.isToday
                          ? colors.accent.withValues(alpha: 0.12)
                          : colors.border.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.isToday)
                          Text(
                            'TODAY',
                            style: PulpitFonts.inter(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: colors.accent,
                              letterSpacing: 0.5,
                            ),
                          )
                        else ...[
                          Text(
                            _monthName(widget.date.month).toUpperCase(),
                            style: PulpitFonts.inter(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            '${widget.date.day}',
                            style: PulpitFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.reference,
                          style: PulpitFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: widget.isToday
                                ? colors.accent
                                : colors.textPrimary,
                          ),
                        ),
                        Text(
                          'King James Version',
                          style: PulpitFonts.inter(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: colors.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: _expanded
                ? Column(
                    children: [
                      Divider(height: 1, color: colors.border),
                      // Passage text
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                        child: _loading
                            ? Center(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: CircularProgressIndicator(
                                    color: colors.accent,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : _passage != null
                                ? Text(
                                    _passage!.displayText,
                                    style: PulpitFonts.inter(
                                      fontSize: 13,
                                      color: colors.textPrimary,
                                      height: 1.65,
                                    ),
                                  )
                                : Text(
                                    'Tap to load verse text',
                                    style: PulpitFonts.inter(
                                      fontSize: 13,
                                      color: colors.textSecondary,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                      ),
                      // Action buttons
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        child: Row(
                          children: [
                            // Preach This button
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _preachThis(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.accent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.mic_rounded,
                                        size: 14,
                                        color: colors.background,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Preach This',
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
                            ),
                            const SizedBox(width: 10),
                            // Word Study button
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  context.push(
                                    '/word-study?word=${_firstKeyword(widget.reference)}',
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.accent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: colors.accent.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.school_rounded,
                                        size: 14,
                                        color: colors.accent,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Word Study',
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
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Creates a new sermon seeded from this verse and navigates to the editor.
  Future<void> _preachThis(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final sermon = await ref.read(sermonProvider.notifier).addSermon(
          widget.reference,
          'KJV',
        );
    if (context.mounted) {
      context.push('/sermons/${sermon.id}/edit');
    }
  }

  /// Extracts the book name from a reference as the word-study seed.
  String _firstKeyword(String ref) {
    // e.g. "John 3:16" → "John", "1 Corinthians 10:13" → "Corinthians"
    final parts = ref.split(' ');
    if (parts.length >= 2) {
      // Skip numeric book prefixes like "1", "2"
      final candidate = parts.first;
      if (int.tryParse(candidate) != null && parts.length > 1) {
        return parts[1];
      }
      return candidate;
    }
    return ref;
  }
}
