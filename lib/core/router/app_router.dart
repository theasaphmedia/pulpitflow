import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/screens/auth_screen.dart';
import '../../features/bible/screens/bible_reader_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/ideas/screens/idea_bank_screen.dart';
import '../../features/library/screens/concordance_screen.dart';
import '../../features/library/screens/votd_history_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/sermons/screens/sermon_list_screen.dart';
import '../../features/editor/screens/sermon_editor_screen.dart';
import '../../features/preaching/screens/preaching_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/projection/screens/projectionist_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/word_study/screens/word_study_screen.dart';
import '../../shared/state/onboarding_provider.dart';
import '../../shared/widgets/app_shell.dart';
import 'transitions.dart';

class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final supabase = Supabase.instance.client;
  final authRefresh = _GoRouterRefreshStream(supabase.auth.onAuthStateChange);
  final onboarding = onboardingNotifierInstance;

  ref.onDispose(authRefresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: false,
    // Refresh on both auth changes AND onboarding completion
    refreshListenable: Listenable.merge([authRefresh, onboarding]),
    redirect: (context, state) {
      final session = supabase.auth.currentSession;
      final isLoggedIn = session != null;
      final loc = state.matchedLocation;
      final isSplash = loc == '/splash';
      final isAuth = loc == '/auth';
      final isOnboarding = loc == '/onboarding';
      final isProjection = loc == '/projection';

      // Always let splash finish its own animation sequence
      if (isSplash) return null;

      // Projection screen is publicly accessible (projectionist may not have an account)
      if (isProjection) return null;

      // Not logged in → auth screen
      if (!isLoggedIn && !isAuth) return '/auth';

      // Logged in but trying to reach auth → go home
      if (isLoggedIn && isAuth) {
        return onboarding.isLoaded && !onboarding.isComplete
            ? '/onboarding'
            : '/';
      }

      // Logged in, onboarding loaded and not complete → onboarding
      if (isLoggedIn &&
          !isOnboarding &&
          onboarding.isLoaded &&
          !onboarding.isComplete) {
        return '/onboarding';
      }

      // Logged in, onboarding complete but still on onboarding screen → home
      if (isLoggedIn && isOnboarding && onboarding.isComplete) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) => fadeScalePage(
          context: context,
          state: state,
          child: const SplashScreen(),
        ),
      ),
      GoRoute(
        path: '/auth',
        pageBuilder: (context, state) => fadeScalePage(
          context: context,
          state: state,
          child: const AuthScreen(),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => fadeScalePage(
          context: context,
          state: state,
          child: const OnboardingScreen(),
        ),
      ),
      // ── Bottom-nav shell ────────────────────────────────────────────────
      // Home / Sermons / Bible / Word Study / Idea Bank / Profile all live
      // as branches here so they're always one tap away. Before this, the
      // app opened straight into Sermons at '/' with no way to see
      // "everywhere else" at a glance — Solomon's ask was for a landing
      // page the reader decides from, so Home now owns '/' and Sermons
      // moved to '/sermons'.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sermons',
                builder: (context, state) => const SermonListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/bible',
                builder: (context, state) => const BibleReaderScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/word-study',
                builder: (context, state) {
                  final word = state.uri.queryParameters['word'];
                  return WordStudyScreen(initialWord: word);
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/idea-bank',
                builder: (context, state) => const IdeaBankScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/sermons/:id/edit',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          final highlightBlock =
              state.uri.queryParameters['highlightBlock'];
          return slideRightPage(
            context: context,
            state: state,
            child: SermonEditorScreen(
              sermonId: id,
              highlightBlockId: highlightBlock,
            ),
          );
        },
      ),
      GoRoute(
        path: '/sermons/:id/preach',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return slideUpPage(
            context: context,
            state: state,
            child: PreachingScreen(sermonId: id),
          );
        },
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => slideRightPage(
          context: context,
          state: state,
          child: const SettingsScreen(),
        ),
      ),
      GoRoute(
        path: '/projection',
        pageBuilder: (context, state) => slideUpPage(
          context: context,
          state: state,
          // ?code= lets a shared link (see the preacher-side "Share" button
          // on the session code card) pre-fill and auto-connect instead of
          // requiring the projectionist to type the 6 characters by hand.
          child: ProjectionistScreen(
            initialCode: state.uri.queryParameters['code'],
          ),
        ),
      ),
      GoRoute(
        path: '/concordance',
        pageBuilder: (context, state) => slideRightPage(
          context: context,
          state: state,
          child: const ConcordanceScreen(),
        ),
      ),
      GoRoute(
        path: '/votd-history',
        pageBuilder: (context, state) => slideRightPage(
          context: context,
          state: state,
          child: const VotdHistoryScreen(),
        ),
      ),
    ],
  );
});
