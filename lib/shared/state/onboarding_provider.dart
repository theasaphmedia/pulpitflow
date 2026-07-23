import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingKey = 'onboarding_complete';

/// Simple ChangeNotifier so GoRouter's refreshListenable can react to
/// the onboarding-complete flag being flipped after the user finishes setup.
class OnboardingNotifier extends ChangeNotifier {
  bool? _isComplete; // null = SharedPreferences not yet loaded

  bool get isLoaded => _isComplete != null;

  /// Returns true once the user has completed (or skipped) onboarding.
  /// Defaults to true while still loading so the router doesn't flash
  /// the onboarding screen on cold start for existing users.
  bool get isComplete => _isComplete ?? true;

  OnboardingNotifier() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _isComplete = prefs.getBool(_kOnboardingKey) ?? false;
    notifyListeners();
  }

  /// Call after the user taps "Get Started" or "Skip for now".
  Future<void> complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingKey, true);
    _isComplete = true;
    notifyListeners();
  }

  /// For testing — resets the flag so onboarding shows again.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kOnboardingKey);
    _isComplete = false;
    notifyListeners();
  }
}

/// Global instance used by both the router and Riverpod provider.
final onboardingNotifierInstance = OnboardingNotifier();

/// Riverpod provider — screens use this to call .complete() or .reset().
/// We use a plain Provider because the router already listens to the
/// ChangeNotifier directly via Listenable.merge; Riverpod 3 dropped
/// ChangeNotifierProvider.
final onboardingNotifierProvider = Provider<OnboardingNotifier>((ref) {
  return onboardingNotifierInstance;
});
