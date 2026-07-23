import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/profile_model.dart';
import '../../../data/models/sermon_model.dart';
import '../../../shared/state/auth_provider.dart';
import '../../../shared/state/profile_provider.dart';
import '../../../shared/state/sermon_provider.dart';
import '../../../shared/state/theme_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _editing = false;

  // Controllers for all editable fields
  late final TextEditingController _nameCtrl;
  late final TextEditingController _churchCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _countryCtrl;
  late final TextEditingController _bioCtrl;

  String _ministryTitle = 'Pastor';
  String _denomination = 'Non-denominational';
  String _defaultTranslation = 'KJV';

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _churchCtrl = TextEditingController();
    _cityCtrl = TextEditingController();
    _countryCtrl = TextEditingController();
    _bioCtrl = TextEditingController();
  }

  void _populateFields(UserProfile profile) {
    _nameCtrl.text = profile.fullName ?? '';
    _churchCtrl.text = profile.churchName ?? '';
    _cityCtrl.text = profile.city ?? '';
    _countryCtrl.text = profile.country ?? '';
    _bioCtrl.text = profile.bio ?? '';
    _ministryTitle = profile.ministryTitle;
    _denomination = profile.denomination ?? 'Non-denominational';
    _defaultTranslation = profile.defaultTranslation;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _churchCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(UserProfile current) async {
    setState(() => _saving = true);
    final updated = current.copyWith(
      fullName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      ministryTitle: _ministryTitle,
      churchName:
          _churchCtrl.text.trim().isEmpty ? null : _churchCtrl.text.trim(),
      denomination: _denomination,
      city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
      country:
          _countryCtrl.text.trim().isEmpty ? null : _countryCtrl.text.trim(),
      defaultTranslation: _defaultTranslation,
      bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
    );
    final synced = await ref.read(profileProvider.notifier).updateProfile(updated);
    if (mounted) {
      setState(() {
        _saving = false;
        _editing = false;
      });
      HapticFeedback.lightImpact();
      if (!synced) {
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

  @override
  Widget build(BuildContext context) {
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);
    final profileAsync = ref.watch(profileProvider);
    final sermonsAsync = ref.watch(sermonProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: profileAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: colors.accent),
        ),
        error: (e, _) => Center(
          child: Text(
            'Could not load profile',
            style: PulpitFonts.inter(color: colors.textSecondary),
          ),
        ),
        data: (profile) {
          if (profile == null) {
            return Center(
              child: CircularProgressIndicator(color: colors.accent),
            );
          }

          // Populate controllers once when entering edit mode
          if (_editing && _nameCtrl.text.isEmpty && profile.fullName != null) {
            _populateFields(profile);
          }

          // Stats
          final sermons = sermonsAsync.value ?? [];
          final totalSermons = sermons.length;
          final preachedCount =
              sermons.where((s) => s.status == SermonStatus.preached).length;
          final draftCount =
              sermons.where((s) => s.status == SermonStatus.draft).length;
          final readyCount =
              sermons.where((s) => s.status == SermonStatus.ready).length;
          final totalScriptures = sermons.fold<int>(
            0,
            (sum, s) =>
                sum + s.blocks.where((b) => b.type == BlockType.scripture).length,
          );
          final seriesCount = sermons
              .where((s) => s.series != null && s.series!.isNotEmpty)
              .map((s) => s.series!)
              .toSet()
              .length;
          final preachedSermons = sermons
              .where((s) => s.status == SermonStatus.preached)
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          final lastPreached =
              preachedSermons.isNotEmpty ? preachedSermons.first.updatedAt : null;

          // Streak: consecutive ISO weeks where at least one sermon was preached
          final streak = _computeStreak(preachedSermons);
          final bestStreak = _computeBestStreak(preachedSermons);

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              _buildAppBar(context, colors, profile),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildHeader(colors, profile),
                    const SizedBox(height: 8),
                    if (_editing)
                      _buildEditForm(colors, profile)
                    else ...[
                      _buildStatsPanel(
                        colors,
                        totalSermons: totalSermons,
                        preachedCount: preachedCount,
                        draftCount: draftCount,
                        readyCount: readyCount,
                        totalScriptures: totalScriptures,
                        seriesCount: seriesCount,
                        lastPreached: lastPreached,
                        streak: streak,
                        bestStreak: bestStreak,
                      ),
                      if (preachedSermons.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildRecentlyPreached(
                          context,
                          colors,
                          preachedSermons.take(8).toList(),
                        ),
                      ],
                      if (sermons.length >= 2) ...[
                        const SizedBox(height: 8),
                        _buildActivityChart(colors, sermons),
                      ],
                      const SizedBox(height: 8),
                      _buildInfoSection(colors, profile),
                    ],
                    const SizedBox(height: 8),
                    _buildAccountSection(colors, user?.email, profile),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── App bar ──────────────────────────────────────────────────────────────

  Widget _buildAppBar(
    BuildContext context,
    PulpitColors colors,
    UserProfile profile,
  ) {
    return SliverAppBar(
      backgroundColor: colors.background,
      elevation: 0,
      pinned: true,
      // Profile is a bottom-nav tab root now (no screen underneath it to
      // pop back to), so the back arrow only makes sense while editing
      // (where it means "cancel edit") or if this got pushed on top of
      // something else. Otherwise there's no leading icon at all, rather
      // than a back arrow that silently does nothing when tapped.
      leading: _editing
          ? IconButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _editing = false;
                  _populateFields(profile);
                });
              },
              icon: Icon(
                Icons.close_rounded,
                color: colors.textSecondary,
                size: 20,
              ),
              tooltip: 'Cancel editing',
            )
          : (context.canPop()
              ? IconButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    context.pop();
                  },
                  icon: Icon(
                    Icons.arrow_back_ios_rounded,
                    color: colors.textSecondary,
                    size: 20,
                  ),
                  tooltip: 'Back',
                )
              : null),
      title: Text(
        _editing ? 'Edit Profile' : 'Profile',
        style: PulpitFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
      actions: [
        if (_editing)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _saving
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.accent,
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: () => _save(
                      ref.read(profileProvider).value!,
                    ),
                    child: Text(
                      'Save',
                      style: PulpitFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                      ),
                    ),
                  ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                _populateFields(ref.read(profileProvider).value!);
                setState(() => _editing = true);
              },
              icon: Icon(Icons.edit_rounded, size: 14, color: colors.accent),
              label: Text(
                'Edit',
                style: PulpitFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.accent,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Avatar + name header ─────────────────────────────────────────────────

  Widget _buildHeader(PulpitColors colors, UserProfile profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.accent.withValues(alpha: 0.12),
            colors.accent.withValues(alpha: 0.04),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.4)),
        ),
      ),
      child: Column(
        children: [
          // Avatar circle
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.accent.withValues(alpha: 0.18),
              border: Border.all(
                color: colors.accent.withValues(alpha: 0.4),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.accent.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Text(
                profile.initial,
                style: PulpitFonts.cormorantGaramond(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            profile.displayName,
            style: PulpitFonts.cormorantGaramond(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              profile.ministryTitle,
              style: PulpitFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.accent,
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (profile.churchName != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.church_rounded,
                  size: 13,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    profile.churchName!,
                    style: PulpitFonts.inter(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (profile.city != null || profile.country != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.location_on_rounded,
                  size: 12,
                  color: colors.textSecondary.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    [
                      profile.city,
                      profile.country,
                    ].where((v) => v != null).join(', '),
                    style: PulpitFonts.inter(
                      fontSize: 12,
                      color: colors.textSecondary.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              profile.bio!,
              style: PulpitFonts.cormorantGaramond(
                fontSize: 15,
                color: colors.textSecondary,
                height: 1.6,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  // ── Stats panel ──────────────────────────────────────────────────────────

  Widget _buildStatsPanel(
    PulpitColors colors, {
    required int totalSermons,
    required int preachedCount,
    required int draftCount,
    required int readyCount,
    required int totalScriptures,
    required int seriesCount,
    required DateTime? lastPreached,
    required int streak,
    required int bestStreak,
  }) {
    final lastPreachedLabel = lastPreached != null
        ? _formatLastPreached(lastPreached)
        : '—';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          // Row 1: Total | Preached | Series
          Row(
            children: [
              _statCard(
                colors,
                '$totalSermons',
                'Total',
                Icons.library_books_rounded,
                highlight: true,
              ),
              const SizedBox(width: 10),
              _statCard(
                colors,
                '$preachedCount',
                'Preached',
                Icons.record_voice_over_rounded,
              ),
              const SizedBox(width: 10),
              _statCard(
                colors,
                '$seriesCount',
                'Series',
                Icons.collections_bookmark_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Row 2: Draft | Ready | Scriptures
          Row(
            children: [
              _statCard(
                colors,
                '$draftCount',
                'Draft',
                Icons.edit_outlined,
              ),
              const SizedBox(width: 10),
              _statCard(
                colors,
                '$readyCount',
                'Ready',
                Icons.check_circle_outline,
              ),
              const SizedBox(width: 10),
              _statCard(
                colors,
                '$totalScriptures',
                'Scriptures',
                Icons.menu_book_rounded,
              ),
            ],
          ),
          // Streak row
          if (streak > 0 || bestStreak > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: streak >= 4
                    ? Colors.orange.withValues(alpha: 0.08)
                    : colors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: streak >= 4
                      ? Colors.orange.withValues(alpha: 0.35)
                      : colors.border,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    streak >= 4
                        ? '🔥'
                        : streak >= 2
                        ? '⚡'
                        : '✦',
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          streak == 0
                              ? 'No active streak'
                              : '$streak week${streak == 1 ? '' : 's'} streak',
                          style: PulpitFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: streak >= 4
                                ? Colors.orange.shade700
                                : colors.textPrimary,
                          ),
                        ),
                        if (bestStreak > 0)
                          Text(
                            'Best: $bestStreak week${bestStreak == 1 ? '' : 's'}',
                            style: PulpitFonts.inter(
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (streak > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: streak >= 4
                            ? Colors.orange
                            : colors.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${streak}w',
                        style: PulpitFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          // Last preached info line
          if (lastPreached != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 14,
                    color: colors.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Last preached: ',
                    style: PulpitFonts.inter(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                  Text(
                    lastPreachedLabel,
                    style: PulpitFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Returns the ISO year+week key for a date, e.g. "2026-W20"
  static String _isoWeekKey(DateTime date) {
    // ISO week starts Monday; use Thursday to determine year (ISO rule)
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final jan1 = DateTime(thursday.year, 1, 1);
    final week = ((thursday.difference(jan1).inDays) / 7).ceil();
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  /// Current streak: consecutive weeks ending this week (or last if no preaching
  /// this week) that have at least one preached sermon.
  int _computeStreak(List<Sermon> preachedSermons) {
    if (preachedSermons.isEmpty) return 0;
    final preachedWeeks = preachedSermons.map((s) => _isoWeekKey(s.updatedAt)).toSet();

    final now = DateTime.now();
    int streak = 0;
    // Walk backwards week by week
    for (int i = 0; i <= 260; i++) {
      final weekDate = now.subtract(Duration(days: 7 * i));
      final key = _isoWeekKey(weekDate);
      if (preachedWeeks.contains(key)) {
        streak++;
      } else if (streak == 0) {
        // Allow gap for current week if it hasn't started yet
        continue;
      } else {
        break;
      }
    }
    return streak;
  }

  /// Best streak ever: the longest unbroken run of consecutive weeks.
  int _computeBestStreak(List<Sermon> preachedSermons) {
    if (preachedSermons.isEmpty) return 0;
    final preachedWeeks = preachedSermons.map((s) => _isoWeekKey(s.updatedAt)).toSet().toList()
      ..sort();
    if (preachedWeeks.isEmpty) return 0;

    // Convert week keys to a comparable integer: year*100 + week
    int weekKeyToInt(String key) {
      final parts = key.split('-W');
      return int.parse(parts[0]) * 100 + int.parse(parts[1]);
    }

    final weekInts = preachedWeeks.map(weekKeyToInt).toList()..sort();

    int best = 1;
    int current = 1;
    for (int i = 1; i < weekInts.length; i++) {
      final prev = weekInts[i - 1];
      final curr = weekInts[i];
      // Consecutive if diff == 1 (same year) or if crossing year boundary
      // e.g. 202652 → 202701 (approx — simplified: diff ≤ 2 accounts for 52/53-week years)
      final diff = curr - prev;
      if (diff == 1 || diff == 48 || diff == 49) {
        // diff == 48/49 handles year crossing (100 - 52 = 48, 100 - 53 = 47)
        current++;
        if (current > best) best = current;
      } else {
        current = 1;
      }
    }
    return best;
  }

  String _formatLastPreached(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} week${(diff.inDays / 7).floor() == 1 ? '' : 's'} ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} month${(diff.inDays / 30).floor() == 1 ? '' : 's'} ago';
    return '${(diff.inDays / 365).floor()} year${(diff.inDays / 365).floor() == 1 ? '' : 's'} ago';
  }

  Widget _statCard(
    PulpitColors colors,
    String value,
    String label,
    IconData icon, {
    bool highlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: highlight
              ? colors.accent.withValues(alpha: 0.08)
              : colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlight
                ? colors.accent.withValues(alpha: 0.3)
                : colors.border,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 18,
              color: highlight ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: PulpitFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: highlight ? colors.accent : colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: PulpitFonts.inter(
                fontSize: 10,
                color: colors.textSecondary,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Monthly Activity Chart ───────────────────────────────────────────────

  Widget _buildActivityChart(PulpitColors colors, List<Sermon> sermons) {
    // Build last 6 months
    final now = DateTime.now();
    final months = <DateTime>[];
    for (int i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      months.add(m);
    }

    // Count sermons created per month, breakdown by status
    final monthNames = ['Jan','Feb','Mar','Apr','May','Jun',
                         'Jul','Aug','Sep','Oct','Nov','Dec'];

    final bars = months.map((m) {
      final inMonth = sermons.where((s) =>
          s.createdAt.year == m.year && s.createdAt.month == m.month).toList();
      return _MonthBar(
        label: monthNames[m.month - 1],
        draft: inMonth.where((s) => s.status == SermonStatus.draft).length,
        ready: inMonth.where((s) => s.status == SermonStatus.ready).length,
        preached: inMonth.where((s) => s.status == SermonStatus.preached).length,
      );
    }).toList();

    final maxCount = bars.map((b) => b.total).reduce((a, b) => a > b ? a : b);
    if (maxCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, size: 15, color: colors.accent),
              const SizedBox(width: 6),
              Text(
                'Monthly Activity',
                style: PulpitFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              // Legend
              _legendDot(colors, const Color(0xFF22C55E), 'Preached'),
              const SizedBox(width: 8),
              _legendDot(colors, Color(0xFF3B82F6), 'Ready'),
              const SizedBox(width: 8),
              _legendDot(colors, colors.border, 'Draft'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: bars.map((bar) {
                final pct = maxCount == 0 ? 0.0 : bar.total / maxCount;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Stacked bar
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (bar.total > 0)
                                Flexible(
                                  flex: (pct * 100).round(),
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          colors.accent.withValues(alpha: 0.7),
                                          const Color(0xFF22C55E),
                                        ],
                                        stops: bar.preached > 0
                                            ? [
                                                0.0,
                                                bar.preached / bar.total,
                                              ]
                                            : [0.0, 1.0],
                                      ),
                                    ),
                                    child: bar.total >= 2
                                        ? Center(
                                            child: Text(
                                              '${bar.total}',
                                              style: PulpitFonts.inter(
                                                fontSize: 8,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                )
                              else
                                Flexible(
                                  flex: 4,
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: colors.border.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bar.label,
                          style: PulpitFonts.inter(
                            fontSize: 9,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(PulpitColors colors, Color dotColor, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: PulpitFonts.inter(
            fontSize: 9,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ── Recently Preached ────────────────────────────────────────────────────

  Widget _buildRecentlyPreached(
    BuildContext context,
    PulpitColors colors,
    List<Sermon> sermons,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 10),
            child: Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 15,
                  color: colors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  'Recently Preached',
                  style: PulpitFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 110,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              scrollDirection: Axis.horizontal,
              itemCount: sermons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              padding: const EdgeInsets.only(right: 16),
              itemBuilder: (context, i) {
                final sermon = sermons[i];
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    context.push('/sermons/${sermon.id}/edit');
                  },
                  child: Container(
                    width: 140,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: colors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.mic_rounded,
                            size: 14,
                            color: colors.accent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          sermon.title,
                          style: PulpitFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Text(
                          _shortDate(sermon.updatedAt),
                          style: PulpitFonts.inter(
                            fontSize: 10,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _shortDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  // ── Read-only info section ───────────────────────────────────────────────

  Widget _buildInfoSection(PulpitColors colors, UserProfile profile) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(colors, 'Ministry Info'),
            _infoRow(
              colors,
              Icons.badge_rounded,
              'Title',
              profile.ministryTitle,
            ),
            if (profile.churchName != null)
              _infoRow(
                colors,
                Icons.church_rounded,
                'Church',
                profile.churchName!,
              ),
            if (profile.denomination != null)
              _infoRow(
                colors,
                Icons.account_balance_rounded,
                'Denomination',
                profile.denomination!,
              ),
            if (profile.city != null || profile.country != null)
              _infoRow(
                colors,
                Icons.location_on_rounded,
                'Location',
                [
                  profile.city,
                  profile.country,
                ].where((v) => v != null).join(', '),
              ),
            _infoRow(
              colors,
              Icons.translate_rounded,
              'Default Translation',
              profile.defaultTranslation,
              last: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(PulpitColors colors, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: PulpitFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: colors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _infoRow(
    PulpitColors colors,
    IconData icon,
    String label,
    String value, {
    bool last = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 16, color: colors.accent),
              const SizedBox(width: 12),
              Text(
                label,
                style: PulpitFonts.inter(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: PulpitFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (!last)
          Divider(
            height: 1,
            indent: 44,
            color: colors.border.withValues(alpha: 0.6),
          ),
      ],
    );
  }

  // ── Account section ──────────────────────────────────────────────────────

  Widget _buildAccountSection(
    PulpitColors colors,
    String? email,
    UserProfile profile,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(colors, 'Account'),
            if (email != null)
              _infoRow(colors, Icons.email_rounded, 'Email', email),
            Divider(
              height: 1,
              indent: 44,
              color: colors.border.withValues(alpha: 0.6),
            ),
            // Settings
            InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                context.push('/settings');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.settings_rounded,
                      size: 16,
                      color: colors.accent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Settings',
                        style: PulpitFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colors.textSecondary.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),
            Divider(
              height: 1,
              indent: 44,
              color: colors.border.withValues(alpha: 0.6),
            ),
            // Sign out
            InkWell(
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: Text(
                      'Sign out?',
                      style: PulpitFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    content: Text(
                      'You can sign back in anytime. Your sermons are saved to the cloud.',
                      style: PulpitFonts.inter(
                        color: colors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(
                          'Cancel',
                          style: PulpitFonts.inter(color: colors.textSecondary),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          Navigator.pop(ctx, true);
                        },
                        child: Text(
                          'Sign out',
                          style: PulpitFonts.inter(color: colors.error),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await ref.read(authNotifierProvider.notifier).signOut();
                }
              },
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 16,
                      color: colors.error,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Sign out',
                      style: PulpitFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit form ────────────────────────────────────────────────────────────

  Widget _buildEditForm(PulpitColors colors, UserProfile profile) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Personal ─────────────────────────────────────────────────
          _formSectionLabel(colors, 'Personal'),
          _formField(
            colors,
            controller: _nameCtrl,
            label: 'Full Name',
            hint: 'Your name',
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: 10),
          _formDropdown<String>(
            colors,
            label: 'Ministry Title',
            icon: Icons.badge_rounded,
            value: _ministryTitle,
            items: kMinistryTitles,
            onChanged: (v) => setState(() => _ministryTitle = v!),
          ),
          const SizedBox(height: 10),
          _formField(
            colors,
            controller: _bioCtrl,
            label: 'Short Bio',
            hint: 'e.g. Preaching grace since 2005...',
            icon: Icons.edit_note_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: 20),

          // ── Church ───────────────────────────────────────────────────
          _formSectionLabel(colors, 'Church'),
          _formField(
            colors,
            controller: _churchCtrl,
            label: 'Church Name',
            hint: 'e.g. Grace Chapel',
            icon: Icons.church_rounded,
          ),
          const SizedBox(height: 10),
          _formDropdown<String>(
            colors,
            label: 'Denomination',
            icon: Icons.account_balance_rounded,
            value: _denomination,
            items: kDenominations,
            onChanged: (v) => setState(() => _denomination = v!),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _formField(
                  colors,
                  controller: _cityCtrl,
                  label: 'City',
                  hint: 'Lagos',
                  icon: Icons.location_city_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _formField(
                  colors,
                  controller: _countryCtrl,
                  label: 'Country',
                  hint: 'Nigeria',
                  icon: Icons.flag_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Preferences ──────────────────────────────────────────────
          _formSectionLabel(colors, 'Preferences'),
          _formDropdown<String>(
            colors,
            label: 'Default Translation',
            icon: Icons.translate_rounded,
            value: _defaultTranslation,
            items: const ['KJV', 'NIV', 'ESV', 'NLT', 'AMP', 'NKJV'],
            onChanged: (v) => setState(() => _defaultTranslation = v!),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _formSectionLabel(PulpitColors colors, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: PulpitFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: colors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _formField(
    PulpitColors colors, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: PulpitFonts.inter(
        fontSize: 14,
        color: colors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: colors.accent),
        labelStyle: PulpitFonts.inter(
          fontSize: 13,
          color: colors.textSecondary,
        ),
        hintStyle: PulpitFonts.inter(
          fontSize: 13,
          color: colors.textSecondary.withValues(alpha: 0.5),
        ),
        filled: true,
        fillColor: colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.accent, width: 2),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: maxLines > 1 ? 14 : 0,
        ),
      ),
    );
  }

  Widget _formDropdown<T>(
    PulpitColors colors, {
    required String label,
    required IconData icon,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: colors.accent),
        labelStyle: PulpitFonts.inter(
          fontSize: 13,
          color: colors.textSecondary,
        ),
        filled: true,
        fillColor: colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      dropdownColor: colors.surface,
      style: PulpitFonts.inter(fontSize: 14, color: colors.textPrimary),
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: colors.textSecondary,
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(
                '$item',
                style: PulpitFonts.inter(
                  fontSize: 14,
                  color: colors.textPrimary,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ── Data class for activity chart bars ────────────────────────────────────────

class _MonthBar {
  final String label;
  final int draft;
  final int ready;
  final int preached;

  const _MonthBar({
    required this.label,
    required this.draft,
    required this.ready,
    required this.preached,
  });

  int get total => draft + ready + preached;
}
