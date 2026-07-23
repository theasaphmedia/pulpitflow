import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/highlight_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/state/theme_provider.dart';
import '../../../shared/widgets/pulpit_ui.dart'
    show
        PulpitCard,
        pulpitFlameRefreshSliver,
        PulpitEmptyState,
        PulpitEmptyStateType;
import '../../bible/data/highlights_service.dart';

/// "My Highlights" — a consolidated list of every verse the user has
/// highlighted from the Bible reader. HighlightsService and the Supabase
/// `highlights` table already existed with full CRUD before this screen was
/// built; there was simply nowhere in the app that ever showed them back.
class HighlightsScreen extends ConsumerStatefulWidget {
  /// Called when the user taps a highlight to jump to it in the reader.
  /// The caller is expected to pop this screen after handling the jump.
  final void Function(String book, int chapter, int verse)? onJumpTo;

  const HighlightsScreen({super.key, this.onJumpTo});

  @override
  ConsumerState<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends ConsumerState<HighlightsScreen> {
  List<SavedHighlight>? _highlights;
  String? _error;
  String? _filterColor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _error = 'Sign in to see your highlights.');
      return;
    }
    try {
      final list = await highlightsService.fetchAllHighlights(userId: userId);
      if (mounted) setState(() => _highlights = list);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load highlights — check your connection.');
      }
    }
  }

  Future<void> _remove(SavedHighlight h) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _highlights?.remove(h));
    try {
      await highlightsService.removeHighlight(
        userId: userId,
        book: h.book,
        chapter: h.chapter,
        verse: h.verse,
      );
    } catch (_) {
      // Put it back if the delete failed server-side.
      if (mounted) setState(() => _highlights?.add(h));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = PulpitColors.of(ref.watch(themeProvider));
    final all = _highlights;
    final visible = all == null
        ? null
        : (_filterColor == null
            ? all
            : all.where((h) => h.color == _filterColor).toList());

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(colors, all),
            if (all != null && all.isNotEmpty) _buildColorFilterRow(colors, all),
            Expanded(child: _buildBody(colors, visible)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(PulpitColors colors, List<SavedHighlight>? all) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Highlights',
                  style: PulpitFonts.cormorantGaramond(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                if (all != null)
                  Text(
                    '${all.length} verse${all.length == 1 ? '' : 's'} highlighted',
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
    );
  }

  Widget _buildColorFilterRow(PulpitColors colors, List<SavedHighlight> all) {
    final counts = <String, int>{};
    for (final h in all) {
      counts[h.color] = (counts[h.color] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _colorFilterChip(colors, null, all.length, isAll: true),
            ...kHighlightColors.keys
                .where((k) => counts.containsKey(k))
                .map((k) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _colorFilterChip(colors, k, counts[k]!),
                    )),
          ],
        ),
      ),
    );
  }

  Widget _colorFilterChip(
    PulpitColors colors,
    String? colorKey,
    int count, {
    bool isAll = false,
  }) {
    final selected = _filterColor == colorKey;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _filterColor = colorKey);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft : colors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? colors.accent : colors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isAll) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: kHighlightColors[colorKey],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              isAll ? 'All' : colorKey!.substring(0, 1).toUpperCase() + colorKey.substring(1),
              style: PulpitFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? colors.accent : colors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: PulpitFonts.inter(
                fontSize: 11,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(PulpitColors colors, List<SavedHighlight>? visible) {
    // Every state (error/loading/empty/data) is wrapped in the same
    // CustomScrollView + flame refresh sliver so pull-to-refresh works
    // regardless of what's currently on screen — e.g. retrying after an
    // error, or re-checking after "No highlights yet" in case one was just
    // added from another device.
    if (_error != null) {
      return _refreshableSliver(
        colors,
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: PulpitFonts.inter(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (visible == null) {
      return _refreshableSliver(
        colors,
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: colors.accent)),
        ),
      );
    }
    if (visible.isEmpty) {
      // Was a bare Column with no entrance animation at all — swapped for
      // the shared illustrated PulpitEmptyState (was built, never wired
      // in anywhere in the app until now) so this screen doesn't read as
      // static/dead compared to every other polished surface.
      return _refreshableSliver(
        colors,
        const SliverFillRemaining(
          hasScrollBody: false,
          child: PulpitEmptyState(type: PulpitEmptyStateType.highlights),
        ),
      );
    }

    return _refreshableSliver(
      colors,
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        // Manual odd/even-index separator trick instead of a named
        // "separated" sliver constructor — keeps this independent of any
        // one Flutter version's sliver API surface, which can't be verified
        // by running `flutter analyze` in this environment.
        sliver: SliverList.builder(
            itemCount: visible.length * 2 - 1,
            itemBuilder: (context, i) {
              if (i.isOdd) return const SizedBox(height: 8);
              final h = visible[i ~/ 2];
              final color = kHighlightColors[h.color] ?? colors.accent;
              return Dismissible(
                key: ValueKey('${h.book}-${h.chapter}-${h.verse}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: colors.error,
                  ),
                ),
                onDismissed: (_) => _remove(h),
                child: PulpitCard(
                  colors: colors,
                  margin: EdgeInsets.zero,
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    widget.onJumpTo?.call(h.book, h.chapter, h.verse);
                    if (widget.onJumpTo != null) Navigator.of(context).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border(
                        left: BorderSide(color: color, width: 3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                h.reference,
                                style: PulpitFonts.cormorantGaramond(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _relativeTime(h.createdAt),
                                style: PulpitFonts.inter(
                                  fontSize: 11,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
  }

  /// Wraps [content] (a single sliver) in a CustomScrollView with the flame
  /// pull-to-refresh control above it — shared by every state _buildBody can
  /// return (error/loading/empty/data) so pulling to refresh works no matter
  /// what's currently on screen.
  Widget _refreshableSliver(PulpitColors colors, Widget content) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        pulpitFlameRefreshSliver(colors: colors, onRefresh: _load),
        content,
      ],
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
