import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/state/profile_provider.dart';
import '../../../shared/state/theme_provider.dart';
import '../../../shared/state/onboarding_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _saving = false;

  // Step 1
  final _nameCtrl = TextEditingController();
  String _ministryTitle = 'Pastor';

  // Step 2
  final _churchCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  String _denomination = 'Non-denominational';

  // Step 3
  String _translation = 'KJV';

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _churchCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  void _nextPage() {
    HapticFeedback.lightImpact();
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _prevPage() {
    HapticFeedback.lightImpact();
    if (_currentPage > 1) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finish({bool skip = false}) async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();

    try {
      if (!skip) {
        final profileAsync = ref.read(profileProvider);
        final current = profileAsync.value;
        if (current != null) {
          final updated = current.copyWith(
            fullName: _nameCtrl.text.trim().isEmpty
                ? null
                : _nameCtrl.text.trim(),
            ministryTitle: _ministryTitle,
            churchName: _churchCtrl.text.trim().isEmpty
                ? null
                : _churchCtrl.text.trim(),
            denomination: _denomination,
            city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
            country: _countryCtrl.text.trim().isEmpty
                ? null
                : _countryCtrl.text.trim(),
            defaultTranslation: _translation,
          );
          final synced = await ref
              .read(profileProvider.notifier)
              .updateProfile(updated);
          if (!synced && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Saved on this device, but couldn\'t reach the server — it will sync next time you\'re online.',
                ),
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      }

      // Mark onboarding done — router will redirect to '/'
      await ref.read(onboardingNotifierProvider).complete();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          // Background radial glow
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.4),
                  radius: 1.2,
                  colors: [
                    colors.accent.withValues(alpha: 0.10),
                    colors.background,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ── Top bar ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      // Logo mark
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.accent.withValues(alpha: 0.12),
                          border: Border.all(
                            color: colors.accent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(
                          Icons.menu_book_rounded,
                          size: 18,
                          color: colors.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'PulpitFlow',
                        style: PulpitFonts.cormorantGaramond(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (_currentPage > 0)
                        TextButton(
                          onPressed: _saving ? null : () => _finish(skip: true),
                          child: Text(
                            'Skip',
                            style: PulpitFonts.inter(
                              fontSize: 13,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Step indicators (hidden on hero page 0) ──────────
                AnimatedOpacity(
                  opacity: _currentPage > 0 ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (i) {
                        // page 0 = hero, pages 1-3 = form steps
                        final formPage = _currentPage - 1;
                        final active = i == formPage;
                        final done = i < formPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: active || done
                                ? colors.accent
                                : colors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                  ),
                ),

                // ── Pages ────────────────────────────────────────────
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    children: [
                      // Page 0: Hero welcome
                      _StepHero(
                        colors: colors,
                        onGetStarted: _nextPage,
                        onSkip: () => _finish(skip: true),
                      ),
                      // Page 1: Name & Title
                      _StepOne(
                        colors: colors,
                        nameCtrl: _nameCtrl,
                        ministryTitle: _ministryTitle,
                        onTitleChanged: (v) =>
                            setState(() => _ministryTitle = v),
                        onNext: _nextPage,
                      ),
                      // Page 2: Church & Location
                      _StepTwo(
                        colors: colors,
                        churchCtrl: _churchCtrl,
                        cityCtrl: _cityCtrl,
                        countryCtrl: _countryCtrl,
                        denomination: _denomination,
                        onDenominationChanged: (v) =>
                            setState(() => _denomination = v),
                        onNext: _nextPage,
                        onBack: _prevPage,
                      ),
                      // Page 3: Bible Translation + Finish
                      _StepThree(
                        colors: colors,
                        translation: _translation,
                        onTranslationChanged: (v) =>
                            setState(() => _translation = v),
                        saving: _saving,
                        onFinish: () => _finish(),
                        onBack: _prevPage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 0: Hero Welcome ──────────────────────────────────────────────────────

class _StepHero extends StatelessWidget {
  final PulpitColors colors;
  final VoidCallback onGetStarted;
  final VoidCallback onSkip;

  const _StepHero({
    required this.colors,
    required this.onGetStarted,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
      child: Column(
        children: [
          const SizedBox(height: 24),

          // Logo mark
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.card,
              border: Border.all(
                color: colors.accent.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.accent.withValues(alpha: 0.18),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Icon(
              Icons.menu_book_rounded,
              size: 40,
              color: colors.accent,
            ),
          )
              .animate()
              .fadeIn(duration: 600.ms)
              .scale(begin: const Offset(0.7, 0.7), curve: Curves.elasticOut),

          const SizedBox(height: 20),

          // Title
          Text(
            'Welcome to\nPulpitFlow',
            textAlign: TextAlign.center,
            style: PulpitFonts.cormorantGaramond(
              fontSize: 38,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              height: 1.1,
            ),
          )
              .animate()
              .fadeIn(delay: 200.ms, duration: 500.ms)
              .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),

          const SizedBox(height: 12),

          // Tagline
          Text(
            'The Word. Delivered.',
            textAlign: TextAlign.center,
            style: PulpitFonts.inter(
              fontSize: 14,
              color: colors.textSecondary,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w400,
            ),
          )
              .animate()
              .fadeIn(delay: 350.ms, duration: 500.ms),

          const SizedBox(height: 28),

          // Value props
          ...[
            (Icons.edit_note_rounded, 'Prepare sermons',
                'Write, structure, and organise your messages with ease'),
            (Icons.cast_rounded, 'Preach with confidence',
                'Live projection, timer, and scripture display in one place'),
            (Icons.auto_stories_rounded, 'Grow your ministry',
                'Track streaks, reflect on sermons, and study the Word deeper'),
          ].asMap().entries.map((entry) {
            final i = entry.key;
            final (icon, title, subtitle) = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 20, color: colors.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: PulpitFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: PulpitFonts.inter(
                            fontSize: 12,
                            color: colors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 450 + i * 100), duration: 400.ms)
                  .slideX(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
            );
          }),

          const SizedBox(height: 24),

          // Get Started button
          _continueBtn(colors, label: 'Get Started', onTap: onGetStarted)
              .animate()
              .fadeIn(delay: 800.ms, duration: 400.ms)
              .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),

          const SizedBox(height: 16),

          // Skip setup
          GestureDetector(
            onTap: onSkip,
            child: Text(
              'Skip setup',
              style: PulpitFonts.inter(
                fontSize: 13,
                color: colors.textSecondary,
                decoration: TextDecoration.underline,
                decorationColor: colors.textSecondary,
              ),
            ),
          ).animate().fadeIn(delay: 900.ms, duration: 400.ms),
        ],
      ),
    );
  }
}

// ── Step 1: Name & Title ──────────────────────────────────────────────────────

class _StepOne extends StatelessWidget {
  final PulpitColors colors;
  final TextEditingController nameCtrl;
  final String ministryTitle;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onNext;

  const _StepOne({
    required this.colors,
    required this.nameCtrl,
    required this.ministryTitle,
    required this.onTitleChanged,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Heading
          Text(
            'Welcome to\nPulpitFlow',
            style: PulpitFonts.cormorantGaramond(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              height: 1.1,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 10),
          Text(
            "Let's set up your ministry profile.",
            style: PulpitFonts.inter(
              fontSize: 15,
              color: colors.textSecondary,
              height: 1.5,
            ),
          )
              .animate()
              .fadeIn(delay: 100.ms, duration: 500.ms)
              .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 36),

          // Name field
          _label(colors, 'Your Name'),
          const SizedBox(height: 8),
          _textField(
            colors,
            controller: nameCtrl,
            hint: 'e.g. Solomon Stephen',
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: 20),

          // Ministry Title
          _label(colors, 'Ministry Title'),
          const SizedBox(height: 8),
          _dropdown<String>(
            colors,
            value: ministryTitle,
            items: kMinistryTitles,
            icon: Icons.badge_rounded,
            onChanged: (v) => onTitleChanged(v!),
          ),
          const SizedBox(height: 40),

          // Continue button
          _continueBtn(colors, label: 'Continue', onTap: onNext),
        ],
      ),
    );
  }
}

// ── Step 2: Church & Location ────────────────────────────────────────────────

class _StepTwo extends StatelessWidget {
  final PulpitColors colors;
  final TextEditingController churchCtrl;
  final TextEditingController cityCtrl;
  final TextEditingController countryCtrl;
  final String denomination;
  final ValueChanged<String> onDenominationChanged;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _StepTwo({
    required this.colors,
    required this.churchCtrl,
    required this.cityCtrl,
    required this.countryCtrl,
    required this.denomination,
    required this.onDenominationChanged,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Church',
            style: PulpitFonts.cormorantGaramond(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              height: 1.1,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 10),
          Text(
            'Tell us about your ministry home.',
            style: PulpitFonts.inter(
              fontSize: 15,
              color: colors.textSecondary,
              height: 1.5,
            ),
          )
              .animate()
              .fadeIn(delay: 100.ms, duration: 500.ms)
              .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 36),

          _label(colors, 'Church Name'),
          const SizedBox(height: 8),
          _textField(
            colors,
            controller: churchCtrl,
            hint: 'e.g. Grace Chapel',
            icon: Icons.church_rounded,
          ),
          const SizedBox(height: 20),

          _label(colors, 'Denomination'),
          const SizedBox(height: 8),
          _dropdown<String>(
            colors,
            value: denomination,
            items: kDenominations,
            icon: Icons.account_balance_rounded,
            onChanged: (v) => onDenominationChanged(v!),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(colors, 'City'),
                    const SizedBox(height: 8),
                    _textField(
                      colors,
                      controller: cityCtrl,
                      hint: 'Lagos',
                      icon: Icons.location_city_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(colors, 'Country'),
                    const SizedBox(height: 8),
                    _textField(
                      colors,
                      controller: countryCtrl,
                      hint: 'Nigeria',
                      icon: Icons.flag_rounded,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),

          Row(
            children: [
              _backBtn(colors, onTap: onBack),
              const SizedBox(width: 12),
              Expanded(child: _continueBtn(colors, label: 'Continue', onTap: onNext)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Step 3: Translation ──────────────────────────────────────────────────────

class _StepThree extends StatelessWidget {
  final PulpitColors colors;
  final String translation;
  final ValueChanged<String> onTranslationChanged;
  final bool saving;
  final VoidCallback onFinish;
  final VoidCallback onBack;

  const _StepThree({
    required this.colors,
    required this.translation,
    required this.onTranslationChanged,
    required this.saving,
    required this.onFinish,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    const translations = [
      ('KJV', 'King James Version', 'The timeless classic'),
      ('NIV', 'New Int\'l Version', 'Clear & contemporary'),
      ('ESV', 'Eng. Standard Version', 'Literal accuracy'),
      ('NLT', 'New Living Translation', 'Easy to read'),
      ('AMP', 'Amplified Bible', 'Expanded meaning'),
      ('NKJV', 'New King James', 'Modern KJV'),
    ];

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Bible',
            style: PulpitFonts.cormorantGaramond(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              height: 1.1,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms)
              .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 10),
          Text(
            'Choose your default Bible translation.',
            style: PulpitFonts.inter(
              fontSize: 15,
              color: colors.textSecondary,
              height: 1.5,
            ),
          )
              .animate()
              .fadeIn(delay: 100.ms, duration: 500.ms)
              .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 28),

          // Translation cards
          ...translations.asMap().entries.map((entry) {
            final i = entry.key;
            final t = entry.value;
            final selected = t.$1 == translation;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTranslationChanged(t.$1);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.accent.withValues(alpha: 0.10)
                        : colors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? colors.accent : colors.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: selected
                              ? colors.accent.withValues(alpha: 0.15)
                              : colors.background,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            t.$1,
                            style: PulpitFonts.cormorantGaramond(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? colors.accent
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.$2,
                              style: PulpitFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? colors.textPrimary
                                    : colors.textPrimary,
                              ),
                            ),
                            Text(
                              t.$3,
                              style: PulpitFonts.inter(
                                fontSize: 11,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: colors.accent,
                        ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(
                      delay: Duration(milliseconds: 50 + i * 60),
                      duration: 400.ms,
                    )
                    .slideX(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
            ));
          }),

          const SizedBox(height: 32),

          // Back + Finish buttons
          Row(
            children: [
              _backBtn(colors, onTap: onBack),
              const SizedBox(width: 12),
              Expanded(
                child: _finishBtn(colors, saving: saving, onTap: onFinish),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

const kMinistryTitles = [
  'Pastor', 'Bishop', 'Reverend', 'Elder', 'Evangelist',
  'Apostle', 'Prophet', 'Deacon', 'Minister', 'Chaplain',
];

const kDenominations = [
  'Non-denominational', 'Baptist', 'Pentecostal', 'Methodist',
  'Presbyterian', 'Anglican', 'Catholic', 'Lutheran', 'Reformed',
  'Assemblies of God', 'Church of God', 'Seventh-day Adventist', 'Other',
];

Widget _label(PulpitColors colors, String text) {
  return Text(
    text,
    style: PulpitFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: colors.textSecondary,
      letterSpacing: 0.5,
    ),
  );
}

Widget _textField(
  PulpitColors colors, {
  required TextEditingController controller,
  required String hint,
  required IconData icon,
  TextInputType? keyboardType,
}) {
  return TextField(
    controller: controller,
    keyboardType: keyboardType,
    style: PulpitFonts.inter(fontSize: 15, color: colors.textPrimary),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: PulpitFonts.inter(
        fontSize: 14,
        color: colors.textSecondary.withValues(alpha: 0.5),
      ),
      prefixIcon: Icon(icon, size: 18, color: colors.textSecondary),
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
        borderSide: BorderSide(color: colors.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}

Widget _dropdown<T>(
  PulpitColors colors, {
  required T value,
  required List<T> items,
  required IconData icon,
  required ValueChanged<T?> onChanged,
}) {
  return DropdownButtonFormField<T>(
    initialValue: value,
    decoration: InputDecoration(
      prefixIcon: Icon(icon, size: 18, color: colors.textSecondary),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    dropdownColor: colors.surface,
    style: PulpitFonts.inter(fontSize: 15, color: colors.textPrimary),
    icon: Icon(Icons.keyboard_arrow_down_rounded, color: colors.textSecondary),
    items: items
        .map((item) => DropdownMenuItem<T>(
              value: item,
              child: Text(
                '$item',
                style: PulpitFonts.inter(fontSize: 14, color: colors.textPrimary),
              ),
            ))
        .toList(),
    onChanged: onChanged,
  );
}

Color _onAccent(Color bg) =>
    bg.computeLuminance() > 0.4 ? const Color(0xFF1A1A1A) : Colors.white;

Widget _continueBtn(PulpitColors colors,
    {required String label, required VoidCallback onTap}) {
  final textColor = _onAccent(colors.accent);
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: 54,
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: colors.accent.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: PulpitFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textColor)),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 18, color: textColor),
          ],
        ),
      ),
    ),
  );
}

Widget _finishBtn(PulpitColors colors,
    {required bool saving, required VoidCallback onTap}) {
  final textColor = _onAccent(colors.accent);
  return GestureDetector(
    onTap: saving ? null : onTap,
    child: Container(
      height: 54,
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: colors.accent.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Center(
        child: saving
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: textColor))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Let's Go",
                      style: PulpitFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textColor)),
                  const SizedBox(width: 8),
                  Icon(Icons.rocket_launch_rounded, size: 18, color: textColor),
                ],
              ),
      ),
    ),
  );
}

Widget _backBtn(PulpitColors colors, {required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Icon(Icons.arrow_back_rounded,
          color: colors.textSecondary, size: 20),
    ),
  );
}
