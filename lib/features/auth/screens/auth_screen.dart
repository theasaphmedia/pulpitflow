import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/state/theme_provider.dart';
import '../../../shared/state/auth_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _emailConfirmationSent = false;
  bool _resetSent = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);
    final authState = ref.watch(authNotifierProvider);

    // Listen for auth success/failure. Navigation is gated on the presence
    // of an actual session — sign-up with email-confirmation enabled returns
    // a User object but no session, and we don't want to bounce the user to
    // '/' just to have the router throw them back here.
    ref.listen(authNotifierProvider, (prev, next) {
      if (prev == null) return;
      next.whenOrNull(
        data: (user) {
          final hasSession = supabase.auth.currentSession != null;
          if (user != null && hasSession && mounted) {
            context.go('/');
          }
        },
        error: (e, _) {
          if (prev is! AsyncLoading) return;
          setState(() => _errorMessage = _parseError(e));
        },
      );
    });

    // Sign-up confirmation screen takes priority over the form.
    if (_emailConfirmationSent) {
      return _buildConfirmationScreen(colors);
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.mic_rounded,
                      color: colors.accent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'PulpitFlow',
                    style: PulpitFonts.cormorantGaramond(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: colors.accent,
                    ),
                  ),
                ],
              ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.1, end: 0),

              const SizedBox(height: 48),

              // Title
              Text(
                _isSignUp ? 'Create account' : 'Welcome back',
                style: PulpitFonts.cormorantGaramond(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
              const SizedBox(height: 6),
              Text(
                _isSignUp
                    ? 'Start your preaching journey'
                    : 'Sign in to your sermons',
                style: PulpitFonts.inter(
                  fontSize: 15,
                  color: colors.textSecondary,
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 150.ms),

              const SizedBox(height: 36),

              // Error message
              if (_errorMessage != null)
                Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: colors.error,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: PulpitFonts.inter(
                                fontSize: 13,
                                color: colors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .slideY(begin: -0.1, end: 0),

              // Name field (sign up only)
              if (_isSignUp) ...[
                _buildTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'Solomon Stephen',
                  icon: Icons.person_outline_rounded,
                  colors: colors,
                ).animate().fadeIn(duration: 300.ms),
                const SizedBox(height: 14),
              ],

              // Email field
              _buildTextField(
                controller: _emailController,
                label: 'Email',
                hint: 'you@example.com',
                icon: Icons.email_outlined,
                colors: colors,
                keyboardType: TextInputType.emailAddress,
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
              const SizedBox(height: 14),

              // Password field
              _buildTextField(
                controller: _passwordController,
                label: 'Password',
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                colors: colors,
                obscureText: _obscurePassword,
                suffix: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  child: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: colors.textSecondary,
                    size: 18,
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 250.ms),

              // Forgot password — only on sign-in tab
              if (!_isSignUp)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _showForgotPassword(colors);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      'Forgot password?',
                      style: PulpitFonts.inter(
                        fontSize: 13,
                        color: colors.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: 275.ms)
              else
                const SizedBox(height: 28),

              if (_isSignUp) const SizedBox(height: 0),

              // Sign in / Sign up button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: authState.isLoading ? null : _handleEmailAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.background,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: authState.isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: colors.background,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _isSignUp ? 'Create Account' : 'Sign In',
                          style: PulpitFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 300.ms),

              const SizedBox(height: 20),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: colors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or',
                      style: PulpitFonts.inter(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: colors.border)),
                ],
              ).animate().fadeIn(duration: 400.ms, delay: 350.ms),

              const SizedBox(height: 20),

              // Google sign in button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: authState.isLoading ? null : _handleGoogleSignIn,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: colors.border, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/google_logo.png',
                        height: 20,
                        width: 20,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.g_mobiledata_rounded,
                          color: colors.accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Continue with Google',
                        style: PulpitFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 400.ms),

              const SizedBox(height: 32),

              // Toggle sign in / sign up
              Center(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _isSignUp = !_isSignUp;
                      _errorMessage = null;
                    });
                  },
                  child: RichText(
                    text: TextSpan(
                      style: PulpitFonts.inter(
                        fontSize: 14,
                        color: colors.textSecondary,
                      ),
                      children: [
                        TextSpan(
                          text: _isSignUp
                              ? 'Already have an account? '
                              : "Don't have an account? ",
                        ),
                        TextSpan(
                          text: _isSignUp ? 'Sign In' : 'Sign Up',
                          style: PulpitFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 450.ms),

              const SizedBox(height: 16),

              // Projection was a fully built, fully working feature
              // (Supabase Realtime broadcast/join, code generation, the
              // whole path) with zero way to actually reach it — '/projection'
              // is intentionally public (no-account) in the router redirect
              // logic, per the comment there ("projectionist may not have an
              // account"), but nothing in the UI ever linked to it. Same
              // dead-route shape as VOTD history and PulpitEmptyState before
              // they were wired in. This is the natural home for it: a
              // projectionist opening the app with no account at all lands
              // here first.
              Center(
                child: TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    context.push('/projection');
                  },
                  child: Text(
                    'Connecting a screen? Enter the code here',
                    style: PulpitFonts.inter(
                      fontSize: 13,
                      color: colors.textSecondary,
                      decoration: TextDecoration.underline,
                      decorationColor: colors.textSecondary,
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 500.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required PulpitColors colors,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: PulpitFonts.inter(color: colors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: colors.textSecondary, size: 20),
        suffixIcon: suffix != null
            ? Padding(padding: const EdgeInsets.only(right: 12), child: suffix)
            : null,
        filled: true,
        fillColor: colors.card,
        labelStyle: PulpitFonts.inter(
          color: colors.textSecondary,
          fontSize: 14,
        ),
        hintStyle: PulpitFonts.inter(
          color: colors.textSecondary.withValues(alpha: 0.5),
        ),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      onChanged: (_) => setState(() => _errorMessage = null),
    );
  }

  Future<void> _handleEmailAuth() async {
    // This is the primary conversion action on the whole screen (sign in or
    // create account) and, unlike almost every other screen in the app, this
    // entire file had zero haptic feedback before this pass.
    HapticFeedback.mediumImpact();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields');
      return;
    }

    setState(() => _errorMessage = null);

    if (_isSignUp) {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        setState(() => _errorMessage = 'Please enter your name');
        return;
      }
      await ref
          .read(authNotifierProvider.notifier)
          .signUpWithEmail(email, password, name);
    } else {
      await ref
          .read(authNotifierProvider.notifier)
          .signInWithEmail(email, password);
    }

    if (!mounted) return;

    // If the call surfaced an error, _errorMessage is already set by the
    // ref.listen above — bail out without navigating or flipping screens.
    final state = ref.read(authNotifierProvider);
    if (state.hasError) return;

    // Decide what to do based on whether a session was actually created.
    //   • Session exists → user is fully signed in, go to '/'.
    //   • No session after sign-up → email confirmation is required by
    //     Supabase; show the "check your email" screen.
    //   • No session after sign-in (rare) → likely the account exists but
    //     hasn't been confirmed; surface a clear error.
    final session = supabase.auth.currentSession;
    if (session != null) {
      context.go('/');
      return;
    }

    if (_isSignUp) {
      setState(() => _emailConfirmationSent = true);
    } else {
      setState(() {
        _errorMessage =
            'Please check your email to confirm your account before signing in.';
      });
    }
  }

  Future<void> _handleGoogleSignIn() async {
    HapticFeedback.mediumImpact();
    setState(() => _errorMessage = null);
    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
  }

  Widget _buildConfirmationScreen(PulpitColors colors) {
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mark_email_unread_rounded,
                  size: 56,
                  color: colors.accent,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Check your email',
                style: PulpitFonts.cormorantGaramond(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'We sent a confirmation link to\n${_emailController.text.trim()}\n\nClick the link to activate your account, then come back to sign in.',
                style: PulpitFonts.inter(
                  fontSize: 15,
                  color: colors.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _emailConfirmationSent = false;
                      _isSignUp = false;
                      _errorMessage = null;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.background,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Go to Sign In',
                    style: PulpitFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await ref
                      .read(authNotifierProvider.notifier)
                      .signUpWithEmail(
                        _emailController.text.trim(),
                        _passwordController.text.trim(),
                        _nameController.text.trim(),
                      );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Confirmation email resent',
                        style: PulpitFonts.inter(color: colors.background),
                      ),
                      backgroundColor: colors.accent,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                },
                child: Text(
                  'Resend confirmation email',
                  style: PulpitFonts.inter(
                    fontSize: 14,
                    color: colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showForgotPassword(PulpitColors colors) {
    final resetEmailCtrl = TextEditingController(
      text: _emailController.text.trim(),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              // Same overflow class as the "New Sermon" sheet: autofocus
              // below opens the keyboard immediately, and on a small
              // device this content doesn't reliably fit in what's left.
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Reset Password',
                  style: PulpitFonts.cormorantGaramond(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Enter your email and we'll send you a reset link.",
                  style: PulpitFonts.inter(
                    fontSize: 14,
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                if (_resetSent)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colors.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: colors.success,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Reset link sent! Check your inbox.',
                            style: PulpitFonts.inter(
                              fontSize: 14,
                              color: colors.success,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  TextField(
                    controller: resetEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    style: PulpitFonts.inter(
                      fontSize: 15,
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'your@email.com',
                      prefixIcon: Icon(
                        Icons.email_outlined,
                        size: 18,
                        color: colors.accent,
                      ),
                      hintStyle: PulpitFonts.inter(
                        fontSize: 14,
                        color: colors.textSecondary.withValues(alpha: 0.5),
                      ),
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
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () async {
                        final email = resetEmailCtrl.text.trim();
                        if (email.isEmpty) return;
                        HapticFeedback.mediumImpact();
                        try {
                          await Supabase.instance.client.auth
                              .resetPasswordForEmail(email);
                          setSheet(() {});
                          setState(() => _resetSent = true);
                        } catch (e) {
                          // Still show success — don't reveal if email exists
                          setSheet(() {});
                          setState(() => _resetSent = true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: colors.accent.computeLuminance() > 0.4
                            ? const Color(0xFF1A1A1A)
                            : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Send Reset Link',
                        style: PulpitFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() => setState(() => _resetSent = false));
  }

  String _parseError(Object error) {
    // Prefer the Supabase exception's own message — much more useful than
    // the previous generic fallback for debugging on-device.
    final msg = switch (error) {
      AuthException e => e.message,
      _ => error.toString(),
    };

    if (msg.contains('Invalid login credentials')) {
      return 'Incorrect email or password';
    } else if (msg.contains('User already registered')) {
      return 'An account with this email already exists';
    } else if (msg.contains('Email not confirmed')) {
      return 'Please check your email to confirm your account';
    } else if (msg.toLowerCase().contains('network') ||
        msg.contains('SocketException') ||
        msg.contains('Failed host lookup')) {
      return 'No internet connection';
    } else if (msg.contains('Password should be')) {
      // Supabase password-policy error, e.g. "Password should be at least 6
      // characters" — pass it straight through.
      return msg;
    }
    // Show the actual error rather than a generic toast so we can debug.
    return msg.isEmpty ? 'Sign-in failed. Please try again.' : msg;
  }
}
