# PulpitFlow — Context for Claude / Cowork sessions

This file is the single source of truth for what PulpitFlow is, who's
building it, what the surrounding ecosystem looks like, and what's
already shipped vs. still on the board. Any Claude session opened
against `C:\Users\USER\Documents\AI\pulpitflow` should read this first.

---

## 1. Product vision

**Tagline:** The real-time preaching system for the global church.

**Mission:** Replace the chaos of printed sermon notes, WhatsApp
scripture screenshots, and hand signals to projectionists with one
seamless, invisible system — so the preacher can focus entirely on
the Word.

### Product tiers

**Free**
- 10 sermons
- KJV only
- Basic editor and preaching mode

**Pro — $9/month**
- Unlimited sermons
- All 6 translations (KJV, NIV, AMP, ESV, NLT, NKJV)
- Bible Reader in editor and preaching mode
- Cross-references
- Export to PDF / Word
- Offline scripture caching
- Verse of the Day
- Sermon status tracking
- Search

**Church — $29/month**
- Everything in Pro
- Team workspace
- Real-time projectionist dashboard
- Guest preacher invite link
- Role management (preacher, projectionist, worship leader, admin)
- Service scheduler
- Sermon sharing with team before service

**Network — $99/month**
- Everything in Church
- Multi-campus management
- White label
- API access
- Analytics dashboard

---

## 2. Roadmap

### Phase 1 — Core (DONE)
- Splash screen — cinematic
- Sermon list with search, status, Verse of the Day
- Tokenized editor — inline text + scripture chips
- Scripture picker — Book → Chapter → Verse
- Preaching Mode — fullscreen, large typography
- Scripture overlay — verse text, translation swiper
- Bible Reader — 66 books, all chapters, offline cached
- Long press verse → Add to Sermon
- Cross-reference — tap link → related scriptures
- Night/Day auto theme suggestion
- Screen always on during preaching
- Sermon timer
- Reading position memory
- 4 themes — Sacred Dark/Light, Grace Dark/Light
- Supabase auth — Google + email sign in/up
- Offline scripture caching via SharedPreferences

### Phase 2 — Team layer (IN PROGRESS)
- [x] Supabase auth
- [x] Bible Reader in editor (preparation mode) — with PageView swipe across books, cross-refs, long-press verse menu (Copy / View refs / Add to sermon)
- [ ] Cloud sermon sync — Supabase `sermons` table
- [ ] Real-time projectionist dashboard — Supabase Realtime
- [ ] Church workspace — create/join
- [ ] Guest preacher invite link
- [ ] Role management
- [ ] Service scheduler
- [ ] Firebase FCM — service reminders, team alerts

### Phase 3 — Intelligence layer (FUTURE)
- Sermon analytics — books preached most, frequency heatmap
- Scripture frequency map — visual heatmap of Bible usage
- Preaching calendar — yearly overview
- Series planner — multi-week arc builder
- Study Mode — cross-references + personal notes during prep
- Compare translations side by side
- Sermon templates — Expository, Topical, Narrative

### Phase 4 — Growth layer (FUTURE)
- Export to PDF / Word / PowerPoint
- Audio recording — record sermon in-app
- Teleprompter mode
- Congregation size logger
- Multi-language UI — French, Portuguese, Spanish, Yoruba, Igbo
- Sermon podcast publishing — Spotify / Apple Podcasts
- Congregation app — members follow sermon in real time
- Countdown timer — visible only to preacher
- Auto-scroll during preaching

### Distribution (FUTURE)
- App icon
- Play Store listing
- iOS build — fix bundle ID + Google client ID
- RevenueCat monetization
- PostHog analytics

---

## 3. Founder & ecosystem

**Solomon Stephen** — gospel minister, worship leader, music producer,
author, and entrepreneur based in Lagos, Nigeria. Leads The Worship
Nation (TWN) ministry. Operates TWN Studios (Kenny T. Kay Building,
beside Azkol Fuel Station, Langbasa Road, Ajah, Lagos) and TAI Digital
(The Asaph Innovations) — a web design, app development, and graphics
brand.

### Social handles
- **Personal:** @thesolomonsteph (Instagram, YouTube, Facebook, TikTok)
- **TWN:** @theworshipnation_twn (Instagram, Facebook)
- **TWN Studios:** @twnstudiosglobal (Instagram, Facebook)
- **YouTube channel ID:** UCE-vJlarsrIpRFoZcxVMFfA

### Accounts & infrastructure
- **GitHub org:** theasaphmedia
- **Vercel username:** taiglobal
- **Namecheap domain:** solomonstephen.com
- **Supabase projects:**
  - TWN Celebrations Hub — `evtdlywsvbklediwpbpy`
  - PulpitFlow — `nrislgcjcjkplmysutvv`
- **Resend:** contact form for solomonstephen.com → theasaphmedia@gmail.com
- **Anthropic Console:** active

### Music production setup
- DAW: **Studio One**
- Plugins: Waves (complete bundle), FabFilter, iZotope, Oeksound Soothe 2, Plugin Alliance, Soundtoys, Valhalla
- Instruments: Yamaha Motif ES (USB-MIDI), Addictive Drums 2
- Vocal tools: Melodyne (ARA2), Applio/RVC

### Ministry rhythm
- **MDWE** — every Wednesday at noon
- **TSH** — last Saturday before final Sunday
- **Synantesis** — last Sunday of the month

### Books (Selar)
- The Cost of Ignorance
- Sons, Not Slaves: March
- Sons, Not Slaves: April
- Go In This Thy Might (16 chapters — completed)
- The Exploit of His Presence (outlined, 9 chapters)

---

## 4. PulpitFlow — current technical state

- **Project root:** `C:\Users\USER\Documents\AI\pulpitflow`
- **Android package:** `com.tai.pulpitflow`
- **Test device:** Samsung SM A125F (Android 12), device ID `R58R24VF0RM`
- **Stack:** Flutter 3, Riverpod 3, go_router, Supabase, API.Bible, SharedPreferences, WakelockPlus, flutter_animate

### Supabase
- **URL:** `https://nrislgcjcjkplmysutvv.supabase.co`
- **Anon key:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5yaXNsZ2NqY2prcGxteXN1dHZ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgyNzY3MzIsImV4cCI6MjA5Mzg1MjczMn0.VXEzk4kcFLPf8UGuAGkU9lyg_TVsF2bncaJmPRZKFeg`
- **Auth flow:** PKCE; Google OAuth via Supabase provider + custom deep-link `com.tai.pulpitflow://login-callback`
- **Email confirmation:** currently OFF in Supabase for testing — re-enable before production and configure SMTP (Resend or SendGrid)

### Google OAuth
- **Web client ID** (used by Supabase provider): `883107575837-5rmds2n74udp33b1v93sc63ev9jncrhr.apps.googleusercontent.com`
- **Android client ID** (registered with package + SHA-1): `883107575837-cbgmgjit9vbj05ie31hu6qck5ppa6ltt.apps.googleusercontent.com`
- **Redirect URI registered in Google Cloud Console:** `https://nrislgcjcjkplmysutvv.supabase.co/auth/v1/callback`
- **Redirect URL registered in Supabase dashboard:** `com.tai.pulpitflow://login-callback`

### Bible API
- Provider: **API.Bible**
- Key: in `.env` as `BIBLE_API_KEY`
- KJV Bible ID: `de4e12af7f28f599-02` (others mapped in `bible_api_service.dart`)

### Run command
```
flutter run -d R58R24VF0RM
```

### Architectural conventions
- Themes live in `lib/core/theme/app_theme.dart` (4 themes via `PulpitTheme` enum + `PulpitColors`)
- All routes in `lib/core/router/app_router.dart`; router uses `refreshListenable` against `supabase.auth.onAuthStateChange` (do NOT add `ref.watch` inside the router provider — it caused the auth screen to unmount mid-flow earlier)
- Auth state: `lib/shared/state/auth_provider.dart` — `AuthNotifier` subscribes to `onAuthStateChange` via `Future.microtask` (BehaviorSubject sync emit was breaking `AsyncNotifier.build()`)
- Bible feature: `lib/features/bible/` — shared `BibleReaderScreen`, `showScriptureOverlay`, and `cross_references.dart` dataset
- **Preaching mode** still has its own inline Bible Reader / overlay (`lib/features/preaching/screens/preaching_screen.dart`, ~2400 lines) — duplicates what's in `lib/features/bible/`. Migrating preaching to use the shared widgets is a clean follow-up that would delete ~1200 lines.

### Known loose ends
- iOS bundle identifier in `ios/Runner.xcodeproj/project.pbxproj` still `com.example.pulpitflow` — must change in Xcode before any iOS build
- macOS / Linux package IDs likewise still `com.example.pulpitflow`
- iOS Info.plist still has a placeholder `REPLACE_WITH_REVERSED_IOS_CLIENT_ID` (only matters for iOS builds)
- Email SMTP not configured — built-in service has rate limits, not production-grade
- App icon, Play Store listing, RevenueCat monetization, PostHog analytics — all pending

---

## 5. Other active projects

### solomonstephen.com
- Personal brand site — Next.js, custom CSS
- GitHub: `theasaphmedia/SOLOMONSTEPHENONLINE`, subfolder `solomon-stephen-website/`
- Deployed on Vercel (taiglobal)
- Fonts: Cormorant Garamond, Inter
- Palette: Deep Forest Green `#1A2E1A`, Warm Gold `#C9A84C`, Warm Cream `#F5F0E8`
- TAI Digital palette: deep space `#060010`, purple `#7c3aed` → blue `#2563eb`
- Pages: Home, About, Music, Books, Studios, Gallery, Events, Contact, TAI Digital
- Contact form via Resend → theasaphmedia@gmail.com
- **Last known issue:** SEO metadata push caused visual breakage — unresolved

### TWN Celebrations Hub
- Next.js + Supabase birthday celebration platform
- URL: twn-celebrations-hub.vercel.app
- GitHub: `theasaphmedia/twncelebrations`
- Supabase project ID: `evtdlywsvbklediwpbpy`
- Google Sheets pipeline fixed, Canvas API birthday card, RLS enabled

### Floww (Flutter finance app)
- Package: `com.tai.floww`
- Signed release APK ready (53.6 MB)
- Keystore: `android/keystore/tai-floww-release.jks`, alias `tai-floww`
- Phases 1–3 complete — Play Store registration pending ($25 fee)
- Railway backend for AI bank-alert parsing — not yet built

### ComfArd Digital
- Pro-bono agency site — single HTML file
- Deployed: comfard-digital.vercel.app

---

## 6. Working rules for any Claude / Cowork session

- **Always provide complete files** when asked for an edit summary — never partial edits
- **DAW is Studio One** (not Logic, not Ableton)
- **Instagram posts** always use exactly 5 hashtags, one of them `#SolomonStephen`
- **WhatsApp content** always delivered as a downloadable text file
- **TWN Studios address** (when referenced): Kenny T. Kay Building, beside Azkol Fuel Station, Langbasa Road, Ajah, Lagos
- **Test PulpitFlow** on physical device only: `flutter run -d R58R24VF0RM`
- **Incremental shipping** preferred — one feature at a time, verified on device, before stacking the next

---

_Last updated: this session, after auth + Bible Reader phase 2 work._
