import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';

class ThemeNotifier extends Notifier<PulpitTheme> {
  static const _key = 'pulpitTheme';

  @override
  PulpitTheme build() {
    _loadTheme();
    return PulpitTheme.sacredDark;
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      try {
        state = PulpitTheme.values.byName(saved);
      } catch (_) {
        state = PulpitTheme.sacredDark;
      }
    }
  }

  Future<void> setTheme(PulpitTheme theme) async {
    state = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, theme.name);
  }

  // Legacy toggle — cycles through all themes
  Future<void> toggleTheme() async {
    final next =
        PulpitTheme.values[(state.index + 1) % PulpitTheme.values.length];
    await setTheme(next);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, PulpitTheme>(
  ThemeNotifier.new,
);
