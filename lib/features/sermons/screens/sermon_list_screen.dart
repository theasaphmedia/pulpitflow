import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/scripture_data.dart';
import '../../../data/models/sermon_model.dart';
import '../../../shared/state/sermon_provider.dart';
import '../../../shared/state/theme_provider.dart';
import '../../../shared/widgets/pulpit_ui.dart'
    show
        PulpitCard,
        PulpitSermonSkeleton,
        pulpitFlameRefreshSliver,
        PulpitEmptyState,
        PulpitEmptyStateType;

class SermonListScreen extends ConsumerStatefulWidget {
  const SermonListScreen({super.key});

  @override
  ConsumerState<SermonListScreen> createState() => _SermonListScreenState();
}

class _SermonListScreenState extends ConsumerState<SermonListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Sermon> _filterSermons(List<Sermon> sermons) {
    if (_searchQuery.isEmpty) return sermons;
    final q = _searchQuery.toLowerCase();
    return sermons.where((s) {
      if (s.title.toLowerCase().contains(q)) return true;
      if (s.scriptureRefs.any((r) => r.toLowerCase().contains(q))) return true;
      if (s.series?.toLowerCase().contains(q) ?? false) return true;
      for (final block in s.blocks) {
        if (block.content.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final sermonsAsync = ref.watch(sermonProvider);
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, colors, pulpitTheme),
            if (_isSearching) _buildSearchBar(colors),
            Expanded(
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // Pull-to-refresh re-runs SermonNotifier.refresh() (local
                  // reload + cloud re-sync) — the notifier already exposed
                  // this specifically "for pull-to-refresh" but nothing in
                  // the UI ever actually triggered it until now.
                  pulpitFlameRefreshSliver(
                    colors: colors,
                    onRefresh: () =>
                        ref.read(sermonProvider.notifier).refresh(),
                  ),
                  ...sermonsAsync.when(
                    // PulpitSermonSkeleton already existed for exactly this
                    // moment but was never actually wired in — this screen
                    // was showing a bare spinner instead of the shaped
                    // skeleton every other polished list-loading state in
                    // the app uses.
                    loading: () => [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        sliver: SliverList.builder(
                          itemCount: 4,
                          itemBuilder: (_, _) => const PulpitSermonSkeleton(),
                        ),
                      ),
                    ],
                    error: (e, _) => [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            'Something went wrong',
                            style: PulpitFonts.inter(color: colors.accent),
                          ),
                        ),
                      ),
                    ],
                    data: (sermons) {
                      final filtered = _filterSermons(sermons);
                      return filtered.isEmpty && _searchQuery.isNotEmpty
                          ? [
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _buildEmptySearch(colors),
                              ),
                            ]
                          : _buildSermonListSlivers(
                              context,
                              filtered,
                              colors,
                              pulpitTheme,
                              sermons.isEmpty,
                            );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(context, colors),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    PulpitColors colors,
    PulpitTheme pulpitTheme,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PulpitFlow',
                style: PulpitFonts.cormorantGaramond(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'Your sermon library',
                style: PulpitFonts.inter(
                  fontSize: 13,
                  color: colors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          Row(
            children: [
              // Search button
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) {
                      _searchQuery = '';
                      _searchController.clear();
                    }
                  });
                },
                icon: Icon(
                  _isSearching
                      ? Icons.search_off_rounded
                      : Icons.search_rounded,
                  color: _isSearching ? colors.accent : colors.textSecondary,
                  size: 22,
                ),
                tooltip: _isSearching ? 'Close search' : 'Search sermons',
              ),
              // Theme picker
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _showThemePicker(context, colors, pulpitTheme);
                },
                icon: Icon(
                  colors.isDark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  color: colors.textSecondary,
                  size: 22,
                ),
                tooltip: 'Change theme',
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildSearchBar(PulpitColors colors) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: PulpitFonts.inter(fontSize: 15, color: colors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search sermons, scriptures...',
          hintStyle: PulpitFonts.inter(
            color: colors.textSecondary,
            fontSize: 15,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: colors.accent,
            size: 20,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear_rounded,
                    color: colors.textSecondary,
                    size: 18,
                  ),
                  tooltip: 'Clear search',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.2, end: 0);
  }

  List<Widget> _buildSermonListSlivers(
    BuildContext context,
    List<Sermon> sermons,
    PulpitColors colors,
    PulpitTheme pulpitTheme,
    bool isEmpty,
  ) {
    if (sermons.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyState(context, colors),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
        sliver: SliverList.builder(
          itemCount: sermons.length,
          itemBuilder: (context, index) {
            final sermonIndex = index;

            final sermon = sermons[sermonIndex];
            return SermonCard(
              sermon: sermon,
              colors: colors,
              index: sermonIndex,
              onTap: () => context.push('/sermons/${sermon.id}/edit'),
              onPreach: () => context.push('/sermons/${sermon.id}/preach'),
              onDuplicate: () =>
                  ref.read(sermonProvider.notifier).duplicateSermon(sermon),
              onDelete: () => _confirmDelete(context, sermon, colors),
              onStatusChange: (status) => _changeStatus(sermon, status),
            );
          },
        ),
      ),
    ];
  }

  // Was a hand-rolled Column with a plain fadeIn — meanwhile a fully-built
  // PulpitEmptyState widget (illustrated icon + staggered fade/slide-in) sat
  // unused in pulpit_ui.dart. Same "duplicate path, only one half wired up"
  // shape as the backspace bug — wiring the real thing in instead of
  // hand-animating a second copy.
  Widget _buildEmptyState(BuildContext context, PulpitColors colors) {
    return const PulpitEmptyState(type: PulpitEmptyStateType.sermons);
  }

  Widget _buildEmptySearch(PulpitColors colors) {
    return const PulpitEmptyState(type: PulpitEmptyStateType.search);
  }

  Widget _buildFAB(BuildContext context, PulpitColors colors) {
    return FloatingActionButton.extended(
      onPressed: () => _showCreateSermonSheet(context, colors),
      backgroundColor: colors.accent,
      foregroundColor: colors.background,
      elevation: 4,
      icon: const Icon(Icons.add_rounded),
      label: Text(
        'New Sermon',
        style: PulpitFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.5, end: 0);
  }

  void _changeStatus(Sermon sermon, SermonStatus status) async {
    HapticFeedback.selectionClick();
    final updated = sermon.copyWith(status: status);
    await ref.read(sermonProvider.notifier).updateSermon(updated);
  }

  void _showThemePicker(
    BuildContext context,
    PulpitColors colors,
    PulpitTheme current,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Theme',
              style: PulpitFonts.cormorantGaramond(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            ...PulpitTheme.values.map((theme) {
              final tc = PulpitColors.of(theme);
              final isSelected = theme == current;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(themeProvider.notifier).setTheme(theme);
                  Navigator.pop(context);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.accent.withValues(alpha: 0.1)
                        : colors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? colors.accent : colors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: tc.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: tc.accent, width: 2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        theme.displayName,
                        style: PulpitFonts.inter(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isSelected
                              ? colors.accent
                              : colors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (isSelected)
                        Icon(
                          Icons.check_circle_rounded,
                          color: colors.accent,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCreateSermonSheet(BuildContext context, PulpitColors colors) {
    final titleController = TextEditingController();
    String selectedTranslation = 'KJV';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            // autofocus:true below guarantees the keyboard opens the
            // instant this sheet appears — on a small device (SM-A125F,
            // 360x640dp) the keyboard alone can eat close to half the
            // screen, and this sheet's content (title, translation picker,
            // button) doesn't reliably fit in what's left. Without this
            // scroll wrapper it's a silent RenderFlex overflow, not just a
            // cramped layout.
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'New Sermon',
                  style: PulpitFonts.cormorantGaramond(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: titleController,
                  autofocus: true,
                  style: PulpitFonts.inter(color: colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Sermon Title',
                    hintText: 'e.g. The Power of Grace',
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
                      borderSide: BorderSide(color: colors.accent, width: 1.5),
                    ),
                    labelStyle: PulpitFonts.inter(color: colors.textSecondary),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Default Translation',
                  style: PulpitFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: availableTranslations.map((t) {
                    final isSelected = selectedTranslation == t.code;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setModalState(() => selectedTranslation = t.code);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? colors.accent : colors.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? colors.accent : colors.border,
                          ),
                        ),
                        child: Text(
                          t.shortName,
                          style: PulpitFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? colors.background
                                : colors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (titleController.text.trim().isEmpty) return;
                      HapticFeedback.mediumImpact();
                      final sermon = await ref
                          .read(sermonProvider.notifier)
                          .addSermon(
                            titleController.text.trim(),
                            selectedTranslation,
                          );
                      if (context.mounted) {
                        Navigator.pop(context);
                        context.push('/sermons/${sermon.id}/edit');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: colors.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Create Sermon',
                      style: PulpitFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    Sermon sermon,
    PulpitColors colors,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Sermon',
          style: PulpitFonts.cormorantGaramond(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${sermon.title}"? This cannot be undone.',
          style: PulpitFonts.inter(fontSize: 14, color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: PulpitFonts.inter(color: colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              ref.read(sermonProvider.notifier).deleteSermon(sermon.id);
              Navigator.pop(context);
            },
            child: Text(
              'Delete',
              style: PulpitFonts.inter(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sermon Card ─────────────────────────────
class SermonCard extends StatelessWidget {
  final Sermon sermon;
  final PulpitColors colors;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onPreach;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final Function(SermonStatus) onStatusChange;

  const SermonCard({
    super.key,
    required this.sermon,
    required this.colors,
    required this.index,
    required this.onTap,
    required this.onPreach,
    required this.onDuplicate,
    required this.onDelete,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    return PulpitCard(
          colors: colors,
          onTap: onTap,
          child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sermon.title,
                            style: PulpitFonts.cormorantGaramond(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            // Delete itself still lands on the confirm
                            // dialog's own mediumImpact when actually
                            // confirmed — this is just "an option was
                            // picked", same tier as every other menu/chip
                            // selection in the app.
                            HapticFeedback.selectionClick();
                            if (value == 'duplicate') onDuplicate();
                            if (value == 'delete') onDelete();
                            if (value == 'draft') {
                              onStatusChange(SermonStatus.draft);
                            }
                            if (value == 'ready') {
                              onStatusChange(SermonStatus.ready);
                            }
                            if (value == 'preached') {
                              onStatusChange(SermonStatus.preached);
                            }
                          },
                          color: colors.card,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: colors.textSecondary,
                            size: 20,
                          ),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'duplicate',
                              child: _menuItem(
                                Icons.copy_rounded,
                                'Duplicate',
                                colors.accent,
                                colors,
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'draft',
                              child: _menuItem(
                                Icons.edit_outlined,
                                'Mark as Draft',
                                sermon.status == SermonStatus.draft
                                    ? colors.accent
                                    : colors.textSecondary,
                                colors,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'ready',
                              child: _menuItem(
                                Icons.check_circle_outline,
                                'Mark as Ready',
                                sermon.status == SermonStatus.ready
                                    ? Colors.green
                                    : colors.textSecondary,
                                colors,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'preached',
                              child: _menuItem(
                                Icons.mic_rounded,
                                'Mark as Preached',
                                sermon.status == SermonStatus.preached
                                    ? colors.accent
                                    : colors.textSecondary,
                                colors,
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'delete',
                              child: _menuItem(
                                Icons.delete_outline_rounded,
                                'Delete',
                                Colors.red,
                                colors,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Wrap instead of Row: three chips fit comfortably today,
                    // but a longer status label or a double-digit scripture
                    // count on the 360dp test device shouldn't be able to
                    // push this off the edge of the card.
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildChip(
                          sermon.defaultTranslation,
                          colors.accent,
                          colors,
                        ),
                        _buildChip(
                          '${sermon.scriptureCount} scripture${sermon.scriptureCount == 1 ? '' : 's'}',
                          colors.textSecondary,
                          colors,
                        ),
                        _buildStatusChip(sermon.status, colors),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Edited ${_formatDate(sermon.updatedAt)}',
                          style: PulpitFonts.inter(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            onPreach();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colors.accent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.mic_rounded,
                                  size: 13,
                                  color: colors.background,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Preach',
                                  style: PulpitFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: colors.background,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
        )
        .animate()
        .fadeIn(
          duration: 400.ms,
          delay: Duration(milliseconds: index * 60),
        )
        .slideY(begin: 0.08, end: 0);
  }

  Widget _menuItem(
    IconData icon,
    String label,
    Color iconColor,
    PulpitColors colors,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Text(
          label,
          style: PulpitFonts.inter(fontSize: 13, color: colors.textPrimary),
        ),
      ],
    );
  }

  Widget _buildChip(String label, Color color, PulpitColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Text(
        label,
        style: PulpitFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color == colors.accent ? colors.accent : colors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildStatusChip(SermonStatus status, PulpitColors colors) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case SermonStatus.draft:
        color = colors.textSecondary;
        label = 'Draft';
        icon = Icons.edit_rounded;
        break;
      case SermonStatus.ready:
        color = Colors.green;
        label = 'Ready';
        icon = Icons.check_circle_rounded;
        break;
      case SermonStatus.preached:
        color = colors.accent;
        label = 'Preached';
        icon = Icons.mic_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: PulpitFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat('MMM d').format(date);
  }
}
