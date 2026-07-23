import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/state/theme_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _pulseController;
  late AnimationController _exitController;
  late AnimationController _screenFadeController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _taglineSlide;
  late Animation<double> _pulseAnim;
  late Animation<double> _exitScale;
  late Animation<double> _exitOpacity;
  late Animation<double> _screenFadeOpacity;

  @override
  void initState() {
    super.initState();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Logo animation
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
      ),
    );

    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    // Text animation
    _textController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _textOpacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeOut));

    _taglineSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic),
        );

    // Pulse animation
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Exit animation
    _exitController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _exitScale = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeIn));

    _exitOpacity = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeIn));

    // Screen-level fade-in: everything above (_logoController, etc.) only
    // animates the logo/text *within* an already-fully-opaque screen — the
    // Scaffold itself pops in at full opacity on the very first frame,
    // which reads as an abrupt cut from the native launch screen straight
    // to this one. This controller fades the whole screen in from black
    // over its first 350ms so the handoff from native splash to Flutter
    // reads as one continuous fade rather than two separate transitions.
    _screenFadeController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _screenFadeOpacity = CurvedAnimation(
      parent: _screenFadeController,
      curve: Curves.easeOut,
    );
    _screenFadeController.forward();

    _startSequence();
  }

  void _startSequence() async {
    // Brief pause then logo appears
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _logoController.forward();

    // Text appears after logo
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    _textController.forward();

    // Pulse starts
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _pulseController.repeat(reverse: true);

    // Hold then exit
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    _pulseController.stop();
    _exitController.forward();

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) context.go('/');
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _pulseController.dispose();
    _exitController.dispose();
    _screenFadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);

    return Scaffold(
      backgroundColor: colors.background,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _logoController,
          _textController,
          _pulseController,
          _exitController,
          _screenFadeController,
        ]),
        builder: (context, child) {
          return FadeTransition(
            opacity: _screenFadeOpacity,
            child: FadeTransition(
              opacity: _exitOpacity,
              child: ScaleTransition(
                scale: _exitScale,
                child: Stack(
                  children: [
                  // Background radial glow
                  Positioned.fill(child: _buildBackground(colors)),

                  // Particle dots
                  ..._buildParticles(colors),

                  // Center content
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo mark
                        ScaleTransition(
                          scale: _logoScale,
                          child: FadeTransition(
                            opacity: _logoOpacity,
                            child: ScaleTransition(
                              scale: _pulseAnim,
                              child: _buildLogoMark(colors),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Wordmark
                        FadeTransition(
                          opacity: _textOpacity,
                          child: SlideTransition(
                            position: _taglineSlide,
                            child: _buildWordmark(colors),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom tagline
                  Positioned(
                    bottom: 60,
                    left: 0,
                    right: 0,
                    child: FadeTransition(
                      opacity: _textOpacity,
                      child: _buildBottomText(colors),
                    ),
                  ),
                ],
              ),
            ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBackground(PulpitColors colors) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.5,
          colors: [
            colors.accent.withValues(alpha: 0.12),
            colors.background,
            colors.background,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  List<Widget> _buildParticles(PulpitColors colors) {
    final positions = [
      const Offset(0.1, 0.15),
      const Offset(0.85, 0.12),
      const Offset(0.92, 0.45),
      const Offset(0.08, 0.55),
      const Offset(0.15, 0.82),
      const Offset(0.78, 0.78),
      const Offset(0.5, 0.08),
      const Offset(0.45, 0.92),
    ];

    final sizes = [3.0, 2.0, 4.0, 2.5, 3.0, 2.0, 3.5, 2.0];

    return List.generate(positions.length, (i) {
      return Positioned(
        left: MediaQuery.of(context).size.width * positions[i].dx,
        top: MediaQuery.of(context).size.height * positions[i].dy,
        child: FadeTransition(
          opacity: _textOpacity,
          child:
              Container(
                    width: sizes[i],
                    height: sizes[i],
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                  )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fadeIn(
                    duration: Duration(milliseconds: 800 + i * 200),
                    delay: Duration(milliseconds: i * 150),
                  )
                  .scale(
                    begin: const Offset(0.5, 0.5),
                    end: const Offset(1.5, 1.5),
                    duration: Duration(milliseconds: 1500 + i * 300),
                    curve: Curves.easeInOut,
                  ),
        ),
      );
    });
  }

  Widget _buildLogoMark(PulpitColors colors) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.card,
        border: Border.all(
          color: colors.accent.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.2),
            blurRadius: 40,
            spreadRadius: 10,
          ),
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.1),
            blurRadius: 80,
            spreadRadius: 20,
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_rounded, size: 36, color: colors.accent),
            const SizedBox(height: 2),
            Container(
              width: 20,
              height: 2,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWordmark(PulpitColors colors) {
    return Column(
      children: [
        Text(
          'PulpitFlow',
          style: PulpitFonts.cormorantGaramond(
            fontSize: 42,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            letterSpacing: 1.0,
            height: 1,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 48,
          height: 1.5,
          decoration: BoxDecoration(
            color: colors.accent,
            borderRadius: BorderRadius.circular(1),
            boxShadow: [
              BoxShadow(
                color: colors.accent.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Preach with clarity',
          style: PulpitFonts.inter(
            fontSize: 14,
            color: colors.textSecondary,
            letterSpacing: 2.5,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomText(PulpitColors colors) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 20, height: 1, color: colors.border),
            const SizedBox(width: 12),
            Text(
              'The Word. Delivered.',
              style: PulpitFonts.cormorantGaramond(
                fontSize: 13,
                color: colors.textSecondary,
                letterSpacing: 1.5,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(width: 12),
            Container(width: 20, height: 1, color: colors.border),
          ],
        ),
      ],
    );
  }
}
