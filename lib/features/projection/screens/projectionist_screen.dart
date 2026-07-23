import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/services/preach_session_service.dart';
import '../../../shared/state/theme_provider.dart';

class ProjectionistScreen extends ConsumerStatefulWidget {
  const ProjectionistScreen({super.key, this.initialCode});

  /// Pre-fills and auto-connects when arriving via a shared link (e.g.
  /// `/projection?code=7N2RYT` from the preacher's "Share" button) instead
  /// of requiring the code to be typed by hand.
  final String? initialCode;

  @override
  ConsumerState<ProjectionistScreen> createState() =>
      _ProjectionistScreenState();
}

class _ProjectionistScreenState extends ConsumerState<ProjectionistScreen> {
  // ── State machine ─────────────────────────────────────────────────────────
  _Phase _phase = _Phase.enterCode;

  final TextEditingController _codeCtrl = TextEditingController();
  String? _codeError;
  bool _connecting = false;

  RealtimeChannel? _channel;
  PreachPayload?   _payload;
  bool             _connected = false;
  String           _joinedCode = '';

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final code = widget.initialCode?.trim();
    if (code != null && code.length == 6) {
      _codeCtrl.text = code.toUpperCase();
      // Auto-connect on the frame after first build rather than inline here
      // — _join() touches Supabase + setState, both of which want a fully
      // mounted widget tree first.
      WidgetsBinding.instance.addPostFrameCallback((_) => _join());
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _leaveChannel();
    super.dispose();
  }

  Future<void> _leaveChannel() async {
    if (_channel != null) {
      await Supabase.instance.client.removeChannel(_channel!);
      _channel = null;
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _join() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _codeError = 'Enter the 6-character code from the preacher\'s device');
      return;
    }
    setState(() {
      _codeError   = null;
      _connecting  = true;
    });

    await _leaveChannel();
    _channel = preachSessionService.joinSession(code, (payload) {
      if (mounted) {
        setState(() {
          _payload   = payload;
          _connected = true;
          if (_phase != _Phase.display) _phase = _Phase.display;
        });
      }
    });

    _joinedCode = code;

    // Give Supabase 4 seconds to receive first broadcast; if nothing arrives,
    // still switch to display mode (the preacher may not have scrolled yet).
    await Future.delayed(const Duration(seconds: 4));
    if (mounted && _phase != _Phase.display) {
      setState(() {
        _phase      = _Phase.display;
        _connecting = false;
      });
    } else if (mounted) {
      setState(() => _connecting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pulpitTheme = ref.watch(themeProvider);
    final colors      = PulpitColors.of(pulpitTheme);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    return Scaffold(
      backgroundColor: colors.background,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _phase == _Phase.enterCode
            ? _buildCodeEntry(colors)
            : _buildDisplay(colors),
      ),
    );
  }

  // ── Code entry ─────────────────────────────────────────────────────────────

  Widget _buildCodeEntry(PulpitColors colors) {
    final mq = MediaQuery.of(context);
    return Container(
      key: const ValueKey('code_entry'),
      color: colors.background,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(32, mq.padding.top + 24, 32, mq.viewInsets.bottom + 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Back button
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  context.pop();
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios_rounded,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),

          // Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.accent.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.cast_rounded,
              size: 36,
              color: colors.accent,
            ),
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(begin: const Offset(0.8, 0.8)),

          const SizedBox(height: 28),

          Text(
            'Connect a Screen',
            style: PulpitFonts.cormorantGaramond(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

          const SizedBox(height: 8),

          Text(
            'Enter the code from the preacher\'s\ndevice to display it here.',
            style: PulpitFonts.inter(
              fontSize: 14,
              color: colors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(duration: 400.ms, delay: 150.ms),

          const SizedBox(height: 36),

          // Code field
          TextField(
            controller: _codeCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: PulpitFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
              letterSpacing: 6,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'ABCD12',
              hintStyle: PulpitFonts.inter(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: colors.textSecondary.withValues(alpha: 0.3),
                letterSpacing: 6,
              ),
              filled: true,
              fillColor: colors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.accent, width: 2),
              ),
              errorText: _codeError,
              errorStyle: PulpitFonts.inter(
                fontSize: 12,
                color: colors.error,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 20,
              ),
            ),
            onChanged: (_) => setState(() => _codeError = null),
            onSubmitted: (_) => _join(),
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _connecting
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      _join();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.background,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _connecting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colors.background,
                      ),
                    )
                  : Text(
                      'Connect',
                      style: PulpitFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 250.ms),

          const SizedBox(height: 24),
        ],
      ),
    ),
    );
  }

  // ── Live display ───────────────────────────────────────────────────────────

  Widget _buildDisplay(PulpitColors colors) {
    return GestureDetector(
      key: const ValueKey('display'),
      // Tap anywhere to toggle the minimal top bar
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _showBar = !_showBar);
      },
      child: Container(
        color: colors.background,
        child: Stack(
          children: [
            // Main content
            _buildContent(colors),

            // Minimal top bar (session info + disconnect)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              top: _showBar ? 0 : -(80 + MediaQuery.of(context).padding.top),
              left: 0,
              right: 0,
              child: _buildTopBar(colors),
            ),

            // Waiting overlay when no payload yet
            if (_payload == null)
              _buildWaiting(colors),
          ],
        ),
      ),
    );
  }

  bool _showBar = true;

  Widget _buildTopBar(PulpitColors colors) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.of(context).padding.top + 10,
            20,
            10,
          ),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.75),
            border: Border(
              bottom: BorderSide(
                color: colors.border.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // Session code chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colors.accent.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _connected ? Colors.green : colors.textSecondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _joinedCode,
                      style: PulpitFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: colors.accent,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Block progress
              if (_payload != null)
                Text(
                  '${_payload!.blockIndex + 1} / ${_payload!.totalBlocks}',
                  style: PulpitFonts.inter(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              const SizedBox(width: 14),
              // Disconnect
              GestureDetector(
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  await _leaveChannel();
                  if (mounted) {
                    setState(() {
                      _phase     = _Phase.enterCode;
                      _payload   = null;
                      _connected = false;
                      _codeCtrl.clear();
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    'Disconnect',
                    style: PulpitFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaiting(PulpitColors colors) {
    return Container(
      color: colors.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colors.accent),
            const SizedBox(height: 24),
            Text(
              'Waiting for preacher...',
              style: PulpitFonts.cormorantGaramond(
                fontSize: 22,
                color: colors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connected to session $_joinedCode',
              style: PulpitFonts.inter(
                fontSize: 13,
                color: colors.textSecondary.withValues(alpha: 0.6),
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(
          duration: 2200.ms,
          color: colors.accent.withValues(alpha: 0.04),
        );
  }

  Widget _buildContent(PulpitColors colors) {
    final p = _payload;
    if (p == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        40,
        MediaQuery.of(context).padding.top + 80,
        40,
        MediaQuery.of(context).padding.bottom + 40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sermon title + series (small, top)
          if (p.sermonTitle.isNotEmpty) ...[
            Row(
              children: [
                if (p.seriesName != null && p.seriesName!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: colors.accent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      p.seriesName!,
                      style: PulpitFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    p.sermonTitle,
                    style: PulpitFonts.inter(
                      fontSize: 12,
                      color: colors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],

          // Main content block. Wrapped in Expanded + a scroll view instead
          // of relying on a trailing Spacer to fill the remaining space —
          // a long text block at a large projection font size had no bound
          // and no way to scroll, so it would blow past the screen height
          // and throw a RenderFlex overflow (visible as the black/yellow
          // "overflowed" stripes) live on the projection screen mid-sermon.
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.06),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: p.isScripture
                      ? _buildScriptureBlock(p, colors)
                      : _buildTextBlock(p, colors),
                ),
              ),
            ),
          ),

          // Block progress dots at bottom
          const SizedBox(height: 24),
          _buildProgressDots(p, colors),
        ],
      ),
    );
  }

  Widget _buildTextBlock(PreachPayload p, PulpitColors colors) {
    return Container(
      key: ValueKey('block_${p.blockIndex}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Accent rule
          Container(
            width: 48,
            height: 3,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            p.blockText,
            style: PulpitFonts.cormorantGaramond(
              fontSize: p.fontSize,
              color: colors.textPrimary,
              height: 1.8,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptureBlock(PreachPayload p, PulpitColors colors) {
    return Container(
      key: ValueKey('block_${p.blockIndex}'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: colors.chipBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.accent, width: 2),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_rounded, size: 22, color: colors.accent),
          const SizedBox(width: 14),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.scriptureRef ?? '',
                  style: PulpitFonts.inter(
                    fontSize: (p.fontSize - 2).clamp(14.0, 36.0),
                    fontWeight: FontWeight.w800,
                    color: colors.accent,
                    letterSpacing: 0.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (p.translation != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    p.translation!,
                    style: PulpitFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.accent.withValues(alpha: 0.7),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressDots(PreachPayload p, PulpitColors colors) {
    final total = p.totalBlocks.clamp(1, 40);
    final current = p.blockIndex.clamp(0, total - 1);
    // Show at most 20 dots; collapse if longer
    final showDots = total <= 20;

    if (showDots) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final isActive = i == current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isActive ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive
                  ? colors.accent
                  : colors.border.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      );
    }

    // Progress bar for long sermons
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: total > 1 ? current / (total - 1) : 1.0,
            minHeight: 4,
            backgroundColor: colors.border.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Block ${current + 1} of $total',
          style: PulpitFonts.inter(
            fontSize: 11,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

enum _Phase { enterCode, display }
