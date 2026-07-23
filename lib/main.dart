import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app.dart';

// Project ref in the URL must match the `ref` claim inside the anon JWT,
// otherwise Supabase rejects every request.
const _supabaseUrl = 'https://irhdanmpcmrowoqobufw.supabase.co';
const _supabaseAnonKey = 'sb_publishable_ctZlqFUdLfvdMq9di2uveA_qspoKk6O';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // GoogleFonts.xxx() calls fetch the font file over the network the first
  // time each weight is used per device, and only fall back to the system
  // font if that fetch fails — typography silently gated on network
  // quality, which matters for a pastor prepping somewhere with no signal.
  // All six typefaces the app uses (Cormorant Garamond, Open Sans/Inter,
  // Lora, Merriweather, Playfair Display, Literata) are now bundled locally
  // as real assets (see PulpitFonts in core/theme/app_theme.dart), so every
  // call site is fully offline and instant. This flag is kept as a
  // belt-and-suspenders guard: if a future call site ever calls raw
  // GoogleFonts.xxx() directly instead of going through PulpitFonts, it
  // will fail loud (system font fallback) instead of silently depending on
  // the network.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Local sermon storage — see lib/data/local/sermon_storage.dart for why
  // this replaced a single-blob SharedPreferences store.
  await Hive.initFlutter();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Load env (best-effort — auth doesn't depend on it any more, but the
  // Bible API does).
  try {
    await dotenv.load(fileName: '.env');
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('dotenv.load failed: $e\n$st');
    }
  }

  // Initialize Supabase. If this throws we want the real error in logs
  // instead of swallowing it into a downstream "Something went wrong".
  try {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
      // Picks up the OAuth deep-link callback when the OS hands it to us.
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('Supabase.initialize failed: $e\n$st');
    }
    rethrow;
  }

  // Keep screen on during preaching (default off, enabled per screen)
  await WakelockPlus.disable();

  runApp(const ProviderScope(child: PulpitFlowApp()));
}
