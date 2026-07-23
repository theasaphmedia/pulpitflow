import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/scripture_model.dart';
import '../../../data/models/sermon_model.dart';
import '../../../data/services/bible_api_service.dart';
import '../../../shared/state/profile_provider.dart';
import '../../../shared/state/sermon_provider.dart';
import '../../../shared/state/theme_provider.dart';
import '../../../shared/widgets/pulpit_ui.dart' show PulpitCard;

/// The app's landing destination.
///
/// Before this existed, the app opened straight into the Sermons tab —
/// Solomon's exact complaint was that the "reach" (his term) was Sermons by
/// default, with no moment to decide where to go. Home is that moment: a
/// greeting, a shortcut back into whatever sermon was last touched (so
/// landing here doesn't cost the most common action a tap versus the old
/// behavior), today's verse, and a grid of destination tiles.
///
/// The grid was briefly removed on the theory that it duplicated the
/// bottom tab bar. Solomon's actual design: the tab bar is HIDDEN while on
/// Home (see AppShell) — these tiles are the only way to navigate from
/// here. Once the user taps into a section, the tab bar appears for lateral
/// navigation between sections, and collapses again if they tap back to
/// Home. So the grid isn't a duplicate of the tab bar — it's the thing the
/// tab bar defers to on this screen.
///
/// The Verse-of-the-Day card used to live on SermonListScreen — it moved
/// here wholesale (fetch + card) since Home is now the "give this app life
/// on open" screen, and having it in two tabs at once would mean firing the
/// same network fetch twice on a cold start for no reason.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  ScripturePassage? _votd;
  bool _votdLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVOTD();
  }

  Future<void> _loadVOTD() async {
    try {
      final passage = await scriptureService.getVerseOfTheDay();
      if (mounted) {
        setState(() {
          _votd = passage;
          _votdLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _votdLoading = false);
    }
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);
    final sermonsAsync = ref.watch(sermonProvider);
    final profileAsync = ref.watch(profileProvider);
    final name = profileAsync.value?.displayName ?? 'Minister';

    Sermon? lastSermon;
    final sermons = sermonsAsync.value;
    if (sermons != null && sermons.isNotEmpty) {
      lastSermon = sermons.reduce(
        (a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b,
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            Text(
              'PulpitFlow',
              style: PulpitFonts.cormorantGaramond(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: colors.accent,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$_greeting, $name',
              style: PulpitFonts.inter(
                fontSize: 14,
                color: colors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 24),
            if (lastSermon != null) _buildContinueCard(colors, lastSermon),
            _buildVOTDCard(colors),
            const SizedBox(height: 12),
            Text(
              'EXPLORE',
              style: PulpitFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: colors.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            _buildDestinationGrid(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueCard(PulpitColors colors, Sermon sermon) {
    return PulpitCard(
      colors: colors,
      margin: const EdgeInsets.only(bottom: 14),
      onTap: () {
        HapticFeedback.lightImpact();
        context.push('/sermons/${sermon.id}/edit');
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.edit_note_rounded,
                color: colors.accent,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONTINUE WHERE YOU LEFT OFF',
                    style: PulpitFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: colors.textSecondary,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sermon.title,
                    style: PulpitFonts.cormorantGaramond(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.08, end: 0);
  }

  Widget _buildVOTDCard(PulpitColors colors) {
    if (_votdLoading) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: colors.accent,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Loading verse of the day...',
              style: PulpitFonts.inter(fontSize: 13, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    final votd = _votd;
    if (votd == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.push('/votd-history');
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.accent.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: colors.accent.withValues(alpha: 0.08),
              blurRadius: 20,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.wb_sunny_rounded, size: 14, color: colors.accent),
                        const SizedBox(width: 6),
                        Text(
                          'VERSE OF THE DAY',
                          style: PulpitFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: colors.accent,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('MMM d').format(DateTime.now()),
                          style: PulpitFonts.inter(
                            fontSize: 10,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      votd.verses.isNotEmpty
                          ? votd.verses.first.text
                          : votd.fullText,
                      style: PulpitFonts.cormorantGaramond(
                        fontSize: 17,
                        color: colors.textPrimary,
                        height: 1.6,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '— ${votd.reference} (${votd.translation})',
                      style: PulpitFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 600.ms, delay: 100.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildDestinationGrid(PulpitColors colors) {
    final tiles = [
      _DestinationTile(
        icon: Icons.menu_book_rounded,
        label: 'Sermons',
        subtitle: 'Write & organize',
        path: '/sermons',
        colors: colors,
      ),
      _DestinationTile(
        icon: Icons.auto_stories_rounded,
        label: 'Bible',
        subtitle: 'Read & study',
        path: '/bible',
        colors: colors,
      ),
      _DestinationTile(
        icon: Icons.psychology_alt_rounded,
        label: 'Word Study',
        subtitle: 'Greek & Hebrew',
        path: '/word-study',
        colors: colors,
      ),
      _DestinationTile(
        icon: Icons.lightbulb_rounded,
        label: 'Idea Bank',
        subtitle: 'Capture a thought',
        path: '/idea-bank',
        colors: colors,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.25,
      children: tiles,
    ).animate().fadeIn(duration: 500.ms, delay: 200.ms);
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.path,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String path;
  final PulpitColors colors;

  @override
  Widget build(BuildContext context) {
    return PulpitCard(
      colors: colors,
      margin: EdgeInsets.zero,
      onTap: () {
        HapticFeedback.selectionClick();
        context.go(path);
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colors.accent, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: PulpitFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
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
    );
  }
}
