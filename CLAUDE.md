# PulpitFlow — Project Context for Claude

## What This App Is
PulpitFlow is a sermon preparation and preaching tool for Android, built for pastors and ministers. It is developed by Solomon Stephen under the company **TAI** (Technology and Innovation). The app is written in Flutter/Dart and targets Android (Play Store release).

---

## Developer
- **Name:** Solomon Stephen
- **Company:** TAI
- **Website:** solomonstephen.com
- **App email:** pulpitflow@gmail.com
- **Personal email:** theasaphmedia@gmail.com

---

## Tech Stack
- **Frontend:** Flutter 3 / Dart 3 (Android primary target)
- **Backend / Auth / DB:** Supabase (`https://irhdanmpcmrowoqobufw.supabase.co`)
- **AI (Word Study):** Anthropic Claude Haiku via Supabase Edge Function (`word-study`)
- **Bible API:** API.Bible (key stored in `.env`, bundled as Flutter asset)
- **State management:** Riverpod
- **Navigation:** GoRouter
- **Fonts:** Google Fonts (Cormorant Garamond + Inter)
- **Theme:** Custom `PulpitColors` system, dark/light toggle

---

## Key Commands
```bash
# Run on Samsung SM-A125F (device ID)
flutter run -d R58R24VF0RM

# Build signed release AAB
flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info

# Analyze for warnings
flutter analyze

# Push Supabase migrations
npx supabase db push --linked

# Deploy Supabase Edge Function
npx supabase functions deploy word-study --project-ref irhdanmpcmrowoqobufw

# Set Supabase secret
npx supabase secrets set ANTHROPIC_API_KEY=sk-ant-... --project-ref irhdanmpcmrowoqobufw
```

---

## Project Structure (Key Files)
```
lib/
  main.dart                         # App entry, Supabase init, dotenv load
  core/
    router/app_router.dart          # GoRouter config + auth guard
    theme/app_theme.dart            # PulpitColors theming system
    constants/scripture_data.dart   # Offline scripture fallback (mock DB)
  data/
    models/                         # Sermon, Profile, Scripture data models
    services/
      bible_api_service.dart        # API.Bible + offline cache + mock fallback
      word_study_service.dart       # Calls Supabase Edge Function (NOT Anthropic directly)
      sermon_sync_service.dart      # Supabase sermons table sync
      profile_service.dart          # Supabase profiles table
      preach_session_service.dart   # Real-time Supabase broadcast (projection)
  features/
    auth/screens/auth_screen.dart
    onboarding/screens/onboarding_screen.dart
    sermons/screens/sermon_list_screen.dart
    editor/screens/sermon_editor_screen.dart
    preaching/screens/preaching_screen.dart
    projection/screens/projectionist_screen.dart
    word_study/screens/word_study_screen.dart
    settings/screens/settings_screen.dart
    library/screens/                # Bible reader, concordance, VOTD, etc.
    ideas/screens/idea_bank_screen.dart
    profile/
    bible/
  shared/
    state/                          # Riverpod providers (theme, auth, sermon, profile)
    widgets/pulpit_ui.dart          # Shared UI components

supabase/
  functions/word-study/index.ts     # Edge Function — calls Anthropic with server-side key
  migrations/
    20260512_profiles.sql           # Profiles table + RLS
    20260518_rls_sermons_highlights.sql  # RLS for sermons + highlights tables

android/
  app/build.gradle.kts              # Signing config, obfuscation, ProGuard
  app/proguard-rules.pro            # ProGuard rules for Flutter + Supabase
  key.properties                    # NEVER COMMIT — keystore credentials
  .gitignore                        # key.properties, *.jks, *.keystore excluded
```

---

## Supabase Tables
| Table | RLS | Notes |
|-------|-----|-------|
| `profiles` | ✅ Enabled | user_id = auth.uid() |
| `sermons` | ✅ Enabled | user_id = auth.uid() |
| `highlights` | ✅ Enabled | user_id = auth.uid() |

---

## Android Signing
- **Keystore location:** `C:\Users\USER\Documents\PROTECT AT ALL COST\pulpitflow-release.jks`
- **Alias:** `pulpitflow`
- **key.properties path:** `android/key.properties` (git-ignored)
- **Password:** stored separately by Solomon — do not ask for it here

---

## Release AAB
- **Location after build:** `build\app\outputs\bundle\release\app-release.aab`
- **Current version:** 1.0.0+1

---

## Privacy Policy
- **Live URL:** `https://docs.google.com/document/d/e/2PACX-1vRSik8p8uKfwcCaqmzSnTJGOz6Espkklu1_peZG2um3IfcBTGxzDq-r93Dqpy1CIOyQh3-uI8Ftp0sf/pub`
- **Source file:** `privacy_policy.html` (in project root)
- **Word doc:** `PulpitFlow_Privacy_Policy.docx` (in project root)

---

## Google Play Console
- **Account:** pulpitflow@gmail.com
- **Developer name:** PulpitFlow
- **Status:** Account setup in progress
- **Target:** Internal testing → Closed beta → Full release

---

## What Is Complete
- All core features built and working (82 tasks completed)
- All mobile overflow issues fixed (keyboard, hero, sheets)
- Onboarding flow polished
- App icon configured
- Word Study moved to Supabase Edge Function (Anthropic key never in app)
- Developer setup screen removed from Word Study UI
- RLS enabled on all Supabase tables
- Code obfuscation + ProGuard enabled for release
- Privacy policy written and hosted
- Release AAB successfully built and signed
- Supabase migrations clean

---

## Pending / In Progress
- [ ] Google Play Console account finalization ($25 fee + setup)
- [ ] Upload AAB to Play Console
- [ ] Set up internal testing track
- [ ] Store listing copy (description, screenshots, category)
- [ ] Content rating questionnaire (in Play Console)
- [ ] Bible API key — still in `.env` (low risk but could move to Edge Function later)
- [ ] Future: iOS build
- [ ] Future: Windows / Web version

---

## Important Rules
- **Never use `Spacer()` in a full-page Column** — always use `SingleChildScrollView` or fixed `SizedBox`
- **Keyboard-safe bottom sheets:** always use `isScrollControlled: true` + `viewInsets.bottom` in padding
- **Never call Anthropic directly from Flutter** — always go through the `word-study` Edge Function
- **Never commit `key.properties` or `.jks` files** — they are in `.gitignore`
- **Bible API key** is in `.env` which is bundled as a Flutter asset — it works in release builds
- **Supabase anon key** in `main.dart` is intentionally public — RLS protects the data

---

## Device for Testing
- **Samsung SM-A125F** — 360dp wide, ~640dp tall (small Android phone, good baseline)
- Run command: `flutter run -d R58R24VF0RM`
