// PulpitUI — the single shared component library for PulpitFlow.
// Import this one file to get every shared widget:
//   import '../../../shared/widgets/pulpit_ui.dart';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PULPIT CARD
// ─────────────────────────────────────────────────────────────────────────────
//
// The shared card treatment for the app-wide "feels too analog / beginner"
// fix. Before this existed, every list card in the app (sermon cards,
// highlight rows, idea cards, etc.) was its own bespoke flat Container with
// a 1px border and nothing else — no shadow, no press feedback. This is
// the one place that depth + motion for a tappable card now lives, so every
// screen adopting it looks and feels consistent instead of each screen
// re-inventing (or skipping) it.

class PulpitCard extends StatefulWidget {
  final PulpitColors colors;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final EdgeInsetsGeometry margin;
  final BorderRadius borderRadius;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadowOverride;

  const PulpitCard({
    super.key,
    required this.colors,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.border,
    this.boxShadowOverride,
  });

  @override
  State<PulpitCard> createState() => _PulpitCardState();
}

class _PulpitCardState extends State<PulpitCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final content = AnimatedScale(
      scale: _pressed ? PulpitMotion.pressScale : 1.0,
      duration: PulpitMotion.fast,
      curve: PulpitMotion.curve,
      child: AnimatedContainer(
        duration: PulpitMotion.standard,
        curve: PulpitMotion.curve,
        margin: widget.margin,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: widget.borderRadius,
          border: widget.border ?? Border.all(color: colors.border, width: 1),
          boxShadow: widget.boxShadowOverride ??
              (_pressed
                  ? PulpitElevation.cardPressed(colors)
                  : PulpitElevation.card(colors)),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: widget.borderRadius,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            borderRadius: widget.borderRadius,
            child: widget.child,
          ),
        ),
      ),
    );

    if (widget.onTap == null && widget.onLongPress == null) return content;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: content,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PULPIT BUTTON
// ─────────────────────────────────────────────────────────────────────────────

enum PulpitButtonVariant { primary, secondary, ghost, danger }

class PulpitButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final PulpitButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;
  final double? fontSize;

  const PulpitButton({
    super.key,
    required this.label,
    required this.onTap,
    this.variant = PulpitButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.fullWidth = true,
    this.fontSize,
  });

  @override
  State<PulpitButton> createState() => _PulpitButtonState();
}

class _PulpitButtonState extends State<PulpitButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = PulpitColors.of(
      Theme.of(context).brightness == Brightness.dark
          ? PulpitTheme.sacredDark
          : PulpitTheme.sacredLight,
    );

    // Pull colors from nearest InheritedWidget if available
    final theme = _PulpitThemeData.maybeOf(context);
    final c = theme ?? colors;

    Color bg, fg, border;
    switch (widget.variant) {
      case PulpitButtonVariant.primary:
        bg = c.accent;
        fg = c.background;
        border = c.accent;
      case PulpitButtonVariant.secondary:
        bg = c.accent.withValues(alpha: 0.12);
        fg = c.accent;
        border = c.accent.withValues(alpha: 0.3);
      case PulpitButtonVariant.ghost:
        bg = Colors.transparent;
        fg = c.textSecondary;
        border = c.border;
      case PulpitButtonVariant.danger:
        bg = c.error.withValues(alpha: 0.1);
        fg = c.error;
        border = c.error.withValues(alpha: 0.3);
    }

    return GestureDetector(
      onTapDown: (_) {
        if (widget.onTap != null) {
          _press.forward();
          HapticFeedback.lightImpact();
        }
      },
      onTapUp: (_) {
        _press.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _press.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: widget.fullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
            boxShadow: widget.variant == PulpitButtonVariant.primary
                ? [
                    BoxShadow(
                      color: c.accent.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: widget.loading
              ? SizedBox(
                  height: 18,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    ),
                  ),
                )
              : Row(
                  mainAxisSize: widget.fullWidth
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 16, color: fg),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.label,
                      style: PulpitFonts.inter(
                        fontSize: widget.fontSize ?? 15,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PULPIT TEXT FIELD
// ─────────────────────────────────────────────────────────────────────────────

class PulpitTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;

  const PulpitTextField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.maxLines = 1,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.sentences,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = _PulpitThemeData.of(context);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: PulpitFonts.inter(fontSize: 15, color: c.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 18, color: c.accent)
            : null,
        suffixIcon: suffixIcon != null
            ? IconButton(
                onPressed: onSuffixTap,
                icon: Icon(suffixIcon, size: 18, color: c.textSecondary),
              )
            : null,
        labelStyle: PulpitFonts.inter(
          fontSize: 13,
          color: c.textSecondary,
        ),
        hintStyle: PulpitFonts.inter(
          fontSize: 14,
          color: c.textSecondary.withValues(alpha: 0.5),
        ),
        filled: true,
        fillColor: c.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.accent, width: 2),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: maxLines > 1 ? 14 : 0,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PULPIT SECTION HEADER
// ─────────────────────────────────────────────────────────────────────────────

class PulpitSectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const PulpitSectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = _PulpitThemeData.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: PulpitFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: c.textSecondary,
              letterSpacing: 1.3,
            ),
          ),
          if (action != null) ...[
            const Spacer(),
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: PulpitFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PULPIT TAG / CHIP
// ─────────────────────────────────────────────────────────────────────────────

class PulpitTag extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;

  const PulpitTag({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = _PulpitThemeData.of(context);
    final col = color ?? c.accent;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? col : col.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? col : col.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 12,
                color: selected ? c.background : col,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: PulpitFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? c.background : col,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PULPIT BOTTOM SHEET WRAPPER
// ─────────────────────────────────────────────────────────────────────────────

class PulpitBottomSheet extends StatelessWidget {
  final Widget child;
  final String? title;
  final bool scrollable;

  const PulpitBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.scrollable = false,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    bool scrollable = false,
    bool isScrollControlled = false,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: isScrollControlled,
      builder: (_) => PulpitBottomSheet(
        title: title,
        scrollable: scrollable,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _PulpitThemeData.of(context);

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        if (title != null) ...[
          Text(
            title!,
            style: PulpitFonts.cormorantGaramond(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
        ],
        child,
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ],
    );

    if (scrollable) {
      content = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: content,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PULPIT EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class PulpitEmptyState extends StatelessWidget {
  final PulpitEmptyStateType type;
  final String? customTitle;
  final String? customSubtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const PulpitEmptyState({
    super.key,
    required this.type,
    this.customTitle,
    this.customSubtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = _PulpitThemeData.of(context);
    final data = _emptyStateData[type]!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Illustrated icon
            _EmptyIllustration(type: type, colors: c)
                .animate()
                .fadeIn(duration: 600.ms)
                .scale(
                  begin: const Offset(0.8, 0.8),
                  curve: Curves.elasticOut,
                  duration: 800.ms,
                ),
            const SizedBox(height: 28),
            Text(
              customTitle ?? data['title']!,
              style: PulpitFonts.cormorantGaramond(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
              textAlign: TextAlign.center,
            )
                .animate(delay: 200.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.2, end: 0),
            const SizedBox(height: 10),
            Text(
              customSubtitle ?? data['subtitle']!,
              style: PulpitFonts.inter(
                fontSize: 14,
                color: c.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            )
                .animate(delay: 300.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.2, end: 0),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 28),
              PulpitButton(
                label: actionLabel!,
                onTap: onAction,
                fullWidth: false,
              ).animate(delay: 400.ms).fadeIn(duration: 400.ms),
            ],
          ],
        ),
      ),
    );
  }
}

enum PulpitEmptyStateType {
  sermons,
  search,
  wordStudy,
  highlights,
  ideas,
  generic,
}

const _emptyStateData = {
  PulpitEmptyStateType.sermons: {
    'title': 'Your pulpit awaits',
    'subtitle':
        'Every great sermon begins with a single word.\nTap + to write your first.',
  },
  PulpitEmptyStateType.search: {
    'title': 'No sermons found',
    'subtitle': 'Try a different title, tag, or scripture reference.',
  },
  PulpitEmptyStateType.wordStudy: {
    'title': 'Dig into the Word',
    'subtitle':
        'Type any word to uncover its original\nHebrew, Aramaic, or Greek meaning.',
  },
  PulpitEmptyStateType.highlights: {
    'title': 'No highlights yet',
    'subtitle': 'Tap and hold any verse in the Bible reader to highlight it.',
  },
  PulpitEmptyStateType.ideas: {
    'title': 'Your idea bank is empty',
    'subtitle': 'Tap the + button to capture your first idea.',
  },
  PulpitEmptyStateType.generic: {
    'title': 'Nothing here yet',
    'subtitle': 'Check back soon.',
  },
};

class _EmptyIllustration extends StatelessWidget {
  final PulpitEmptyStateType type;
  final PulpitColors colors;

  const _EmptyIllustration({required this.type, required this.colors});

  @override
  Widget build(BuildContext context) {
    // Ideas: two rounds of a hand-drawn CustomPainter bulb (glass + base +
    // filament) both read as "wacky" on-device per Solomon — the small
    // canvas linework just doesn't hold up at this size the way the other
    // illustrations do. Rather than attempt a third hand-drawn version,
    // this uses the same Icons.lightbulb_rounded glyph already used for
    // Idea Bank everywhere else in the app (tab bar, FAB), in a soft
    // accent-tinted circle with a gentle glow — clean, consistent with the
    // rest of the app's Idea Bank branding, and no custom drawing to get
    // wrong.
    if (type == PulpitEmptyStateType.ideas) {
      return Container(
        width: 120,
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.accent.withValues(alpha: 0.12),
          boxShadow: [
            BoxShadow(
              color: colors.accent.withValues(alpha: 0.18),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(Icons.lightbulb_rounded, size: 52, color: colors.accent),
      );
    }

    return CustomPaint(
      size: const Size(120, 120),
      painter: _IllustrationPainter(type: type, colors: colors),
    );
  }
}

class _IllustrationPainter extends CustomPainter {
  final PulpitEmptyStateType type;
  final PulpitColors colors;

  _IllustrationPainter({required this.type, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final accent = colors.accent;
    final faint = accent.withValues(alpha: 0.12);
    final mid = accent.withValues(alpha: 0.35);

    final bgPaint = Paint()..color = faint;
    final accentPaint = Paint()
      ..color = accent
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = mid
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Background circle
    canvas.drawCircle(Offset(cx, cy), 54, bgPaint);

    switch (type) {
      case PulpitEmptyStateType.sermons:
        // Open book
        _drawBook(canvas, cx, cy, accentPaint, fillPaint);
      case PulpitEmptyStateType.search:
        // Magnifying glass
        _drawSearch(canvas, cx, cy, accentPaint);
      case PulpitEmptyStateType.wordStudy:
        // Greek letters
        _drawLetters(canvas, cx, cy, accentPaint, colors);
      case PulpitEmptyStateType.highlights:
        // Star / highlight
        _drawHighlight(canvas, cx, cy, accentPaint, fillPaint);
      case PulpitEmptyStateType.ideas:
        // Lightbulb
        _drawBulb(canvas, cx, cy, accentPaint, fillPaint);
      case PulpitEmptyStateType.generic:
        _drawBook(canvas, cx, cy, accentPaint, fillPaint);
    }
  }

  void _drawBulb(Canvas canvas, double cx, double cy, Paint stroke, Paint fill) {
    final glassTop = cy - 30;
    final glassBottom = cy + 4;

    // Glass: rounded teardrop shape narrowing toward the base — reads as a
    // bulb silhouette rather than a plain circle.
    final path = Path()
      ..moveTo(cx - 17, glassBottom)
      ..cubicTo(cx - 24, glassBottom - 12, cx - 20, glassTop + 6, cx, glassTop)
      ..cubicTo(
        cx + 20,
        glassTop + 6,
        cx + 24,
        glassBottom - 12,
        cx + 17,
        glassBottom,
      )
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

    // Screw base: 3 short ridge lines, narrower than the glass, sitting
    // directly beneath it.
    final basePaint = Paint()
      ..color = stroke.color.withValues(alpha: 0.55)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = glassBottom + 4 + i * 5.0;
      final inset = 9.0 - i * 1.2;
      canvas.drawLine(Offset(cx - inset, y), Offset(cx + inset, y), basePaint);
    }

    // Base cap
    final capPaint = Paint()
      ..color = stroke.color.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, glassBottom + 23),
          width: 11,
          height: 5,
        ),
        const Radius.circular(2),
      ),
      capPaint,
    );

    // Filament: a small zigzag well inside the glass — a recognizable bulb
    // filament, not a crossing X that reads as a cancel/error glyph.
    final filamentPaint = Paint()
      ..color = stroke.color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final filamentPath = Path()
      ..moveTo(cx - 7, glassTop + 12)
      ..lineTo(cx - 2, glassTop + 20)
      ..lineTo(cx + 2, glassTop + 12)
      ..lineTo(cx + 7, glassTop + 20);
    canvas.drawPath(filamentPath, filamentPaint);
  }

  void _drawBook(Canvas canvas, double cx, double cy, Paint stroke, Paint fill) {
    final path = Path();
    // Left page
    path.moveTo(cx - 28, cy - 20);
    path.lineTo(cx - 28, cy + 22);
    path.lineTo(cx, cy + 22);
    path.lineTo(cx, cy - 20);
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

    // Right page
    final path2 = Path();
    path2.moveTo(cx, cy - 20);
    path2.lineTo(cx, cy + 22);
    path2.lineTo(cx + 28, cy + 22);
    path2.lineTo(cx + 28, cy - 20);
    path2.close();
    canvas.drawPath(path2, fill);
    canvas.drawPath(path2, stroke);

    // Lines on pages
    final linePaint = Paint()
      ..color = stroke.color.withValues(alpha: 0.4)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = cy - 8 + i * 9.0;
      canvas.drawLine(Offset(cx - 22, y), Offset(cx - 4, y), linePaint);
      canvas.drawLine(Offset(cx + 4, y), Offset(cx + 22, y), linePaint);
    }
  }

  void _drawSearch(Canvas canvas, double cx, double cy, Paint stroke) {
    canvas.drawCircle(Offset(cx - 5, cy - 5), 20, stroke);
    canvas.drawLine(
      Offset(cx + 9, cy + 9),
      Offset(cx + 24, cy + 24),
      stroke..strokeWidth = 4,
    );
  }

  void _drawLetters(Canvas canvas, double cx, double cy, Paint stroke, PulpitColors colors) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'αγπ',
        style: TextStyle(
          fontSize: 36,
          color: colors.accent,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  void _drawHighlight(Canvas canvas, double cx, double cy, Paint stroke, Paint fill) {
    // Simple star
    final path = Path();
    const n = 5;
    const outer = 24.0;
    const inner = 11.0;
    for (var i = 0; i < n * 2; i++) {
      final r = i.isEven ? outer : inner;
      final angle = (i * 3.14159 / n) - 3.14159 / 2;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  double cos(double rad) => _cos(rad);
  double sin(double rad) => _sin(rad);

  static double _cos(double x) {
    // Simple inline cos via dart:math avoidance
    double result = 1;
    double term = 1;
    for (var i = 1; i <= 8; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  static double _sin(double x) {
    double result = x;
    double term = x;
    for (var i = 1; i <= 8; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// PULPIT SKELETON LOADER
// ─────────────────────────────────────────────────────────────────────────────

class PulpitSkeleton extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const PulpitSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final c = _PulpitThemeData.of(context);

    return Shimmer.fromColors(
      baseColor: c.border.withValues(alpha: 0.6),
      highlightColor: c.card,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: c.border,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Full skeleton card for a sermon list item.
class PulpitSermonSkeleton extends StatelessWidget {
  const PulpitSermonSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = _PulpitThemeData.of(context);

    return Shimmer.fromColors(
      baseColor: c.border.withValues(alpha: 0.5),
      highlightColor: c.card,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 120,
                  height: 16,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 48,
                  height: 22,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              height: 12,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 180,
              height: 12,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 60,
                  height: 10,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 60,
                  height: 10,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PULPIT DIVIDER
// ─────────────────────────────────────────────────────────────────────────────

class PulpitDivider extends StatelessWidget {
  final double indent;
  const PulpitDivider({super.key, this.indent = 0});

  @override
  Widget build(BuildContext context) {
    final c = _PulpitThemeData.of(context);
    return Divider(
      height: 1,
      indent: indent,
      color: c.border.withValues(alpha: 0.6),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THEME PROPAGATION HELPER
// ─────────────────────────────────────────────────────────────────────────────
// Widgets above need access to PulpitColors. Rather than requiring every
// widget to take a `colors` parameter, we pull from an InheritedWidget.
// Screens wrap their content in PulpitThemeScope.

class PulpitThemeScope extends InheritedWidget {
  final PulpitColors colors;
  const PulpitThemeScope({
    super.key,
    required this.colors,
    required super.child,
  });

  static PulpitThemeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PulpitThemeScope>();

  @override
  bool updateShouldNotify(PulpitThemeScope old) => colors != old.colors;
}

// ─────────────────────────────────────────────────────────────────────────────
// PULPIT FLAME REFRESH
// ─────────────────────────────────────────────────────────────────────────────
//
// PulpitFlow had no pull-to-refresh anywhere in the app at all — not even
// the stock Android spinner. Rather than bolt on the default Material
// circular spinner (which would've been the very "generic Android chrome"
// this whole motion pass is trying to move away from), this draws a small
// flame that grows and brightens as you pull, then flickers gently while
// the refresh is in flight — on brand for a sermon/preaching app in a way
// a spinning circle never could be.
//
// Built on CupertinoSliverRefreshControl (ships with the Flutter SDK, no
// extra dependency) purely for its `builder` slot, which hands back the
// live pull state/distance every frame — the actual drag/release/snap
// gesture physics are Flutter's own well-tested implementation underneath;
// only the visual is custom.
//
// Usage: drop `pulpitFlameRefreshSliver(colors: colors, onRefresh: ...)` as
// the first sliver in a CustomScrollView, followed by the screen's own
// SliverList/SliverToBoxAdapter content.

Widget pulpitFlameRefreshSliver({
  required PulpitColors colors,
  required Future<void> Function() onRefresh,
}) {
  return CupertinoSliverRefreshControl(
    onRefresh: onRefresh,
    builder:
        (
          context,
          refreshState,
          pulledExtent,
          refreshTriggerPullDistance,
          refreshIndicatorExtent,
        ) {
          return _PulpitFlameIndicator(
            colors: colors,
            refreshState: refreshState,
            pulledExtent: pulledExtent,
            refreshTriggerPullDistance: refreshTriggerPullDistance,
          );
        },
  );
}

class _PulpitFlameIndicator extends StatefulWidget {
  final PulpitColors colors;
  final RefreshIndicatorMode refreshState;
  final double pulledExtent;
  final double refreshTriggerPullDistance;

  const _PulpitFlameIndicator({
    required this.colors,
    required this.refreshState,
    required this.pulledExtent,
    required this.refreshTriggerPullDistance,
  });

  @override
  State<_PulpitFlameIndicator> createState() => _PulpitFlameIndicatorState();
}

class _PulpitFlameIndicatorState extends State<_PulpitFlameIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flicker;

  bool get _isActive =>
      widget.refreshState == RefreshIndicatorMode.armed ||
      widget.refreshState == RefreshIndicatorMode.refresh;

  // Solomon's follow-up on the beam: it should pulsate as the user pulls,
  // not just once the refresh is actually armed/triggered. So the flicker
  // ticker now runs for the whole pull gesture (any nonzero pulledExtent),
  // and its amplitude — not its presence — is what scales up as the pull
  // approaches the trigger distance and through the active refresh.
  bool get _isPulling => widget.pulledExtent > 0.5 || _isActive;

  @override
  void initState() {
    super.initState();
    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (_isPulling) _flicker.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulpitFlameIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isPulling && !_flicker.isAnimating) {
      _flicker.repeat(reverse: true);
    } else if (!_isPulling && _flicker.isAnimating) {
      _flicker.stop();
      _flicker.value = 0;
    }
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    // How far through the pull gesture we are, before it's armed/refreshing —
    // used to grow and brighten the flame as the pastor pulls down, so the
    // indicator itself communicates "keep pulling" / "let go now".
    final pullProgress = widget.refreshTriggerPullDistance <= 0
        ? 0.0
        : (widget.pulledExtent / widget.refreshTriggerPullDistance).clamp(
            0.0,
            1.0,
          );

    return SizedBox(
      height: widget.pulledExtent,
      child: Center(
        child: AnimatedBuilder(
          animation: _flicker,
          builder: (context, _) {
            // Idle/dragging: scale+opacity track the pull directly, with a
            // small flicker riding on top whose amplitude grows with the
            // pull — so the flame is visibly alive during the drag, not
            // just once armed/refreshing.
            // Armed/refreshing: the flicker takes over as the dominant read.
            final flickerLift = _isActive
                ? _flicker.value * 0.12
                : _flicker.value * 0.05 * pullProgress;
            // Was 0.4 + pullProgress*0.6 / 0.3 + pullProgress*0.7 — at the
            // start of an ordinary pull this rendered at ~40% size and ~30%
            // opacity inside a container barely taller than the pull
            // distance so far, which reads as "nothing there" rather than
            // "something small". Raising the floor so the flame is clearly
            // visible from the first moment of the pull, not just once
            // you're most of the way to the trigger distance.
            final scale = _isActive
                ? 0.92 + flickerLift
                : 0.7 + (pullProgress * 0.3) + flickerLift;
            final opacity = _isActive ? 1.0 : (0.6 + pullProgress * 0.4);

            // Beam: a soft blurred vertical gradient column standing behind
            // the flame, requested by Solomon after confirming the flame
            // itself was finally visible ("can we make it glow when the
            // refresh is pulled down...like beam"). Follow-up ask: it
            // should visibly pulsate as the user pulls, not only once
            // armed/refreshing — so the pulse amplitude now ramps up with
            // pullProgress during the drag (calm at the very start, clearly
            // breathing near the trigger distance), then holds that same
            // strength through the active refresh, rather than the beam
            // sitting static until the flicker ticker kicked in.
            final beamPulseAmplitude = _isActive
                ? 0.25
                : (pullProgress * 0.22);
            final beamPulse =
                (1 - beamPulseAmplitude) + (_flicker.value * beamPulseAmplitude);
            final beamOpacity =
                (_isActive ? 0.55 : pullProgress * 0.5) * beamPulse;
            final beamHeightPulse = _isActive ? 6.0 : (pullProgress * 5.0);
            final beamHeight = 20 +
                (pullProgress * 34) +
                (_flicker.value - 0.5) * 2 * beamHeightPulse;
            final beamWidth = 10 + (pullProgress * 10);

            return Stack(
              alignment: Alignment.center,
              children: [
                // The beam sits underneath the icon and is blurred so it
                // reads as a glow/light-shaft rather than a hard-edged shape.
                Opacity(
                  opacity: beamOpacity.clamp(0.0, 1.0),
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      width: beamWidth,
                      height: beamHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(beamWidth / 2),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Color.lerp(colors.accent, Colors.amber, 0.5)!,
                            Color.lerp(colors.accent, Colors.amber, 0.5)!
                                .withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          colors.accent,
                          Color.lerp(colors.accent, Colors.amber, 0.6)!,
                        ],
                      ).createShader(bounds),
                      child: const Icon(
                        Icons.local_fire_department_rounded,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PulpitThemeData {
  static PulpitColors of(BuildContext context) {
    final scope = PulpitThemeScope.maybeOf(context);
    if (scope != null) return scope.colors;
    // Fallback — derive from Flutter brightness
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PulpitColors.of(
      isDark ? PulpitTheme.sacredDark : PulpitTheme.sacredLight,
    );
  }

  static PulpitColors? maybeOf(BuildContext context) {
    return PulpitThemeScope.maybeOf(context)?.colors;
  }
}
