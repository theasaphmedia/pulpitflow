import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

/// Custom URL scheme that the Supabase OAuth flow redirects back to after the
/// user signs in via the system browser, on native platforms only. Must match:
///   - the intent-filter in android/app/src/main/AndroidManifest.xml
///   - the CFBundleURLSchemes entry in ios/Runner/Info.plist
///   - one of the Redirect URLs configured in Supabase → Authentication → URL Configuration
const String _oauthRedirectNative = 'com.tai.pulpitflow://login-callback';

/// On web there's no app scheme to bounce back to — the browser itself IS
/// the app, so the redirect just needs to land back on the page the user
/// started from. `Uri.base.origin` is the deployed origin (e.g. the Vercel
/// URL) at runtime, so this needs no hardcoded domain and no rebuild when
/// the deployment URL changes. That origin (or a custom domain layered on
/// top of it later) still has to be added to Supabase's Redirect URLs
/// allowlist once, same as the native scheme was.
String get _oauthRedirect =>
    kIsWeb ? Uri.base.origin : _oauthRedirectNative;

/// Streams Supabase auth state changes (sign-in, token refresh, sign-out, etc.).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

/// The currently signed-in user, or null when signed out / loading.
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (state) => state.session?.user,
    loading: () => supabase.auth.currentUser,
    error: (_, _) => null,
  );
});

class AuthNotifier extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    // Keep the notifier in sync with Supabase's own auth-state stream so that
    // a successful OAuth deep-link redirect flips us into the signed-in state
    // without any extra plumbing.
    final sub = supabase.auth.onAuthStateChange.listen((data) {
      state = AsyncData(data.session?.user);
    });
    ref.onDispose(sub.cancel);

    return supabase.auth.currentUser;
  }

  /// Launches the Supabase Google OAuth flow in the system browser; the user
  /// is bounced back to the app via [_oauthRedirect] and the auth state stream
  /// (wired in [build]) updates this notifier.
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    try {
      final ok = await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _oauthRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!ok) {
        // Browser couldn't be launched — surface to UI.
        throw const AuthException('Could not launch Google sign-in.');
      }
      // Don't set AsyncData here — we wait for onAuthStateChange to fire.
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      state = AsyncData(response.user);
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
    }
  }

  Future<void> signUpWithEmail(
    String email,
    String password,
    String name,
  ) async {
    state = const AsyncLoading();
    try {
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );
      state = AsyncData(response.user);
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
    }
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
    state = const AsyncData(null);
  }
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, User?>(
  AuthNotifier.new,
);
