import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/scripture_model.dart';
import '../../../data/services/scripture_service.dart';
import '../../../shared/state/theme_provider.dart';
import '../screens/bible_reader_screen.dart';

const List<Map<String, String>> _kBibleTranslations = [
  {'code': 'KJV', 'name': 'King James Version'},
  {'code': 'NIV', 'name': 'New International Version'},
  {'code': 'AMP', 'name': 'Amplified Bible'},
  {'code': 'ESV', 'name': 'English Standard Version'},
  {'code': 'NLT', 'name': 'New Living Translation'},
  {'code': 'NKJV', 'name': 'New King James Version'},
];

/// Pushes the glassmorphism scripture overlay over the current route.
///
/// If [onAddToSermon] is provided, it gets forwarded to the Bible Reader
/// (reachable via the "Read full chapter in Bible" button) so that
/// long-press-add works there too.
Future<void> showScriptureOverlay({
  required BuildContext context,
  required String reference,
  required String translation,
  void Function(String ref, String translation)? onAddToSermon,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => _ScriptureOverlay(
        initialReference: reference,
        initialTranslation: translation,
        onAddToSermon: onAddToSermon,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        final scale = Tween<double>(begin: 0.88, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
    ),
  );
}

class _ScriptureOverlay extends ConsumerStatefulWidget {
  final String initialReference;
  final String initialTranslation;
  final void Function(String ref, String translation)? onAddToSermon;

  const _ScriptureOverlay({
    required this.initialReference,
    required this.initialTranslation,
    this.onAddToSermon,
  });

  @override
  ConsumerState<_ScriptureOverlay> createState() => _ScriptureOverlayState();
}

class _ScriptureOverlayState extends ConsumerState<_ScriptureOverlay>
    with SingleTickerProviderStateMixin {
  late String _ref;
  late String _translation;
  ScripturePassage? _passage;
  bool _loading = true;

  late final AnimationController _bgController;
  late final Animation<double> _bgFade;

  int get _currentIndex =>
      _kBibleTranslations.indexWhere((t) => t['code'] == _translation);

  @override
  void initState() {
    super.initState();
    _ref = widget.initialReference;
    _translation = widget.initialTranslation;
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _bgFade = CurvedAnimation(parent: _bgController, curve: Curves.easeOut);
    _bgController.forward();
    _loadPassage();
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  Future<void> _loadPassage() async {
    setState(() => _loading = true);
    final passage = await scriptureService.getPassage(_ref, _translation);
    if (!mounted) return;
    setState(() {
      _passage = passage;
      _loading = false;
    });
  }

  Future<void> _switchTranslation(String code) async {
    if (code == _translation) return;
    HapticFeedback.selectionClick();
    setState(() {
      _translation = code;
      _loading = true;
    });
    final passage = await scriptureService.getPassage(_ref, code);
    if (!mounted) return;
    setState(() {
      _passage = passage;
      _loading = false;
    });
  }

  Future<void> _close() async {
    // Single choke point for every dismiss path (header X, swipe-down,
    // backdrop tap) — one haptic here covers all three instead of
    // duplicating it at each call site.
    HapticFeedback.lightImpact();
    await _bgController.reverse();
    if (mounted) Navigator.of(context).pop();
  }

  void _openFullChapter() {
    final parsed = _parseRef(_ref);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BibleReaderScreen(
          initialBook: parsed['book'] as String,
          initialChapter: parsed['chapter'] as int,
          initialTranslation: _translation,
          onAddToSermon: widget.onAddToSermon,
        ),
      ),
    );
  }

  Map<String, dynamic> _parseRef(String ref) {
    try {
      final colon = ref.lastIndexOf(':');
      final bookChapter = colon >= 0 ? ref.substring(0, colon) : ref;
      final lastSpace = bookChapter.lastIndexOf(' ');
      if (lastSpace < 0) return {'book': ref, 'chapter': 1};
      final book = bookChapter.substring(0, lastSpace).trim();
      final chapter =
          int.tryParse(bookChapter.substring(lastSpace + 1).trim()) ?? 1;
      return {'book': book, 'chapter': chapter};
    } catch (_) {
      return {'book': 'John', 'chapter': 1};
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = PulpitColors.of(ref.watch(themeProvider));

    return AnimatedBuilder(
      animation: _bgController,
      builder: (context, child) {
        // Outer GestureDetector: tap on the dim area closes the overlay.
        return GestureDetector(
          onTap: _close,
          behavior: HitTestBehavior.opaque,
          child: Container(
            color: Colors.black.withValues(alpha: 0.6 * _bgFade.value),
            child: Opacity(opacity: _bgFade.value, child: child),
          ),
        );
      },
      child: SafeArea(
        child: Center(
          // Inner GestureDetector wraps ONLY the card so taps on the card
          // (and its action button) don't bubble to the outer dismiss.
          child: GestureDetector(
            onTap: () {},
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 300) _close();
            },
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              final i = _currentIndex;
              if (velocity < -300 && i < _kBibleTranslations.length - 1) {
                _switchTranslation(_kBibleTranslations[i + 1]['code']!);
              } else if (velocity > 300 && i > 0) {
                _switchTranslation(_kBibleTranslations[i - 1]['code']!);
              }
            },
            child: _buildCard(colors),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(PulpitColors colors) {
    final cardColor = colors.isDark ? const Color(0xFF1a1a1a) : colors.surface;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colors.accent.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.08),
            blurRadius: 60,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        // Bounded so a long passage's scrollable verse list can never push
        // the footer (translation tabs, "Read full chapter", swipe hint)
        // off the bottom of the screen — previously this Column had no
        // height cap, so on long passages the card just grew past the
        // visible viewport and the footer was rendered off-screen.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.top -
                MediaQuery.of(context).padding.bottom -
                64, // matches the Container's vertical margin (32 + 32)
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(colors, cardColor),
              Flexible(child: _buildBody(colors)),
              _buildFooter(colors, cardColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(PulpitColors colors, Color cardColor) {
    final translationName = _kBibleTranslations.firstWhere(
      (t) => t['code'] == _translation,
      orElse: () => {'name': _translation},
    )['name']!;

    return Container(
      color: cardColor,
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.menu_book_rounded,
              color: colors.accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ref,
                  style: PulpitFonts.cormorantGaramond(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  translationName,
                  style: PulpitFonts.inter(
                    fontSize: 11,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _close,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.border.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.close_rounded,
                color: colors.textSecondary,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(PulpitColors colors) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final passage = _passage;
    if (passage == null || passage.verses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No content available for $_ref ($_translation).',
          style: PulpitFonts.inter(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          ...passage.verses.map(
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
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildFooter(PulpitColors colors, Color cardColor) {
    return Container(
      color: cardColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, color: colors.border.withValues(alpha: 0.4)),
          _buildTranslationSwiper(colors, cardColor),
          Container(height: 1, color: colors.border.withValues(alpha: 0.4)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _openFullChapter();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colors.accent.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.auto_stories_rounded,
                      size: 15,
                      color: colors.accent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Read full chapter in Bible',
                      style: PulpitFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: colors.accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 3,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Swipe ←/→ to change translation · Swipe ↓ to close',
                  style: PulpitFonts.inter(
                    fontSize: 10,
                    color: colors.textSecondary.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranslationSwiper(PulpitColors colors, Color cardColor) {
    final i = _currentIndex;
    return Container(
      color: cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: i > 0
                ? () => _switchTranslation(_kBibleTranslations[i - 1]['code']!)
                : null,
            child: AnimatedOpacity(
              opacity: i > 0 ? 1.0 : 0.2,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.border.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.chevron_left_rounded,
                  color: colors.textSecondary,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
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
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colors.accent
                            : colors.border.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isSelected
                              ? colors.accent
                              : colors.border.withValues(alpha: 0.5),
                          width: 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: colors.accent.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : [],
                      ),
                      child: Text(
                        code,
                        style: PulpitFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? colors.background
                              : colors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: i < _kBibleTranslations.length - 1
                ? () => _switchTranslation(_kBibleTranslations[i + 1]['code']!)
                : null,
            child: AnimatedOpacity(
              opacity: i < _kBibleTranslations.length - 1 ? 1.0 : 0.2,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.border.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: colors.textSecondary,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
