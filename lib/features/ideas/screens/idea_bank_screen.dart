import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/idea_model.dart';
import '../../../shared/state/idea_provider.dart';
import '../../../shared/state/theme_provider.dart';
import '../../../shared/widgets/pulpit_ui.dart'
    show PulpitCard, PulpitEmptyState, PulpitEmptyStateType;

class IdeaBankScreen extends ConsumerStatefulWidget {
  const IdeaBankScreen({super.key});

  @override
  ConsumerState<IdeaBankScreen> createState() => _IdeaBankScreenState();
}

class _IdeaBankScreenState extends ConsumerState<IdeaBankScreen> {
  String _search = '';
  IdeaTag? _filterTag;

  // ── Tag metadata ───────────────────────────────────────────────────────────────

  static const _tagLabels = {
    IdeaTag.sermon: 'Sermon',
    IdeaTag.illustration: 'Illustration',
    IdeaTag.scripture: 'Scripture',
    IdeaTag.story: 'Story',
    IdeaTag.quote: 'Quote',
    IdeaTag.outline: 'Outline',
    IdeaTag.other: 'Other',
  };

  static const _tagIcons = {
    IdeaTag.sermon: Icons.mic_rounded,
    IdeaTag.illustration: Icons.lightbulb_rounded,
    IdeaTag.scripture: Icons.menu_book_rounded,
    IdeaTag.story: Icons.auto_stories_rounded,
    IdeaTag.quote: Icons.format_quote_rounded,
    IdeaTag.outline: Icons.format_list_bulleted_rounded,
    IdeaTag.other: Icons.label_outline_rounded,
  };

  List<SermonIdea> _filtered(List<SermonIdea> all) {
    var result = all;
    if (_filterTag != null) {
      result = result.where((i) => i.tag == _filterTag).toList();
    }
    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase();
      result = result.where((i) => i.content.toLowerCase().contains(q)).toList();
    }
    // Pinned first
    result.sort((a, b) {
      if (a.isPinned == b.isPinned) return b.createdAt.compareTo(a.createdAt);
      return a.isPinned ? -1 : 1;
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final pulpitTheme = ref.watch(themeProvider);
    final colors = PulpitColors.of(pulpitTheme);
    final ideas = ref.watch(ideaProvider);
    final filtered = _filtered(ideas);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, colors, ideas.length),
            _buildSearchBar(colors),
            _buildTagFilter(colors),
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmptyState(colors)
                  : _buildIdeaList(filtered, colors),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildCaptureFAB(context, colors),
    );
  }

  Widget _buildHeader(BuildContext context, PulpitColors colors, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          // Idea Bank is a bottom-nav tab root now — only show a back
          // arrow when actually pushed on top of something else.
          if (Navigator.of(context).canPop()) ...[
            IconButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
              },
              icon: Icon(
                Icons.arrow_back_ios_rounded,
                color: colors.textPrimary,
                size: 20,
              ),
              tooltip: 'Back',
            ),
            const SizedBox(width: 4),
          ],
          Icon(Icons.lightbulb_rounded, size: 20, color: colors.accent),
          const SizedBox(width: 8),
          Text(
            'Idea Bank',
            style: PulpitFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          if (total > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$total ideas',
                style: PulpitFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(PulpitColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        style: PulpitFonts.inter(
          color: colors.textPrimary,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: 'Search your ideas…',
          hintStyle: PulpitFonts.inter(
            color: colors.textSecondary,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: colors.textSecondary,
            size: 18,
          ),
          filled: true,
          fillColor: colors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colors.accent, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
        onChanged: (v) => setState(() => _search = v),
      ),
    );
  }

  Widget _buildTagFilter(PulpitColors colors) {
    return SizedBox(
      height: 40,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        children: [
          // "All" chip
          _FilterChip(
            label: 'All',
            icon: Icons.grid_view_rounded,
            selected: _filterTag == null,
            colors: colors,
            onTap: () => setState(() => _filterTag = null),
          ),
          ...IdeaTag.values.map((tag) => _FilterChip(
                label: _tagLabels[tag]!,
                icon: _tagIcons[tag]!,
                selected: _filterTag == tag,
                colors: colors,
                onTap: () => setState(
                  () => _filterTag = _filterTag == tag ? null : tag,
                ),
              )),
        ],
      ),
    );
  }

  // Was a bare Column, zero animation — swapped for the shared illustrated
  // PulpitEmptyState (same fix as sermons/highlights: a polished widget
  // existed in pulpit_ui.dart but nothing actually used it). Added a
  // dedicated `ideas` illustration type (lightbulb) instead of reusing the
  // generic book icon, so this doesn't look like a re-skinned sermons card.
  Widget _buildEmptyState(PulpitColors colors) {
    final filtering = _search.isNotEmpty || _filterTag != null;
    return PulpitEmptyState(
      type: PulpitEmptyStateType.ideas,
      customTitle: filtering ? 'No matching ideas' : null,
      customSubtitle: filtering ? 'Try a different search or tag.' : null,
    );
  }

  Widget _buildIdeaList(List<SermonIdea> ideas, PulpitColors colors) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: ideas.length,
      itemBuilder: (context, i) {
        return _IdeaCard(
          key: ValueKey(ideas[i].id),
          idea: ideas[i],
          colors: colors,
          tagLabels: _tagLabels,
          tagIcons: _tagIcons,
          onPin: () =>
              ref.read(ideaProvider.notifier).togglePin(ideas[i].id),
          onDelete: () =>
              ref.read(ideaProvider.notifier).deleteIdea(ideas[i].id),
          onEdit: () => _showCaptureSheet(context, colors, existing: ideas[i]),
          onCopy: () {
            Clipboard.setData(ClipboardData(text: ideas[i].content));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Idea copied to clipboard',
                  style: PulpitFonts.inter(fontSize: 13),
                ),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ).animate().fadeIn(delay: (i * 30).ms).slideY(begin: 0.04, end: 0);
      },
    );
  }

  Widget _buildCaptureFAB(BuildContext context, PulpitColors colors) {
    return FloatingActionButton.extended(
      onPressed: () {
        HapticFeedback.lightImpact();
        _showCaptureSheet(context, colors);
      },
      backgroundColor: colors.accent,
      foregroundColor: colors.background,
      elevation: 6,
      icon: const Icon(Icons.add_rounded),
      label: Text(
        'Capture Idea',
        style: PulpitFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );
  }

  void _showCaptureSheet(
    BuildContext context,
    PulpitColors colors, {
    SermonIdea? existing,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CaptureSheet(
        colors: colors,
        existing: existing,
        tagLabels: _tagLabels,
        tagIcons: _tagIcons,
        onSave: (content, tag) {
          if (existing != null) {
            ref.read(ideaProvider.notifier).updateIdea(
                  existing.copyWith(content: content, tag: tag),
                );
          } else {
            ref.read(ideaProvider.notifier).addIdea(content, tag);
          }
        },
      ),
    );
  }
}

// ── Filter Chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final PulpitColors colors;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent
              : colors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? colors.accent
                : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? colors.background : colors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: PulpitFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? colors.background : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Idea Card ─────────────────────────────────────────────────────────────────

class _IdeaCard extends StatelessWidget {
  final SermonIdea idea;
  final PulpitColors colors;
  final Map<IdeaTag, String> tagLabels;
  final Map<IdeaTag, IconData> tagIcons;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onCopy;

  const _IdeaCard({
    super.key,
    required this.idea,
    required this.colors,
    required this.tagLabels,
    required this.tagIcons,
    required this.onPin,
    required this.onDelete,
    required this.onEdit,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final age = DateTime.now().difference(idea.createdAt);
    final ageLabel = age.inDays >= 1
        ? '${age.inDays}d ago'
        : age.inHours >= 1
            ? '${age.inHours}h ago'
            : 'Just now';

    return PulpitCard(
      colors: colors,
      margin: const EdgeInsets.only(bottom: 10),
      onTap: onEdit,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showActions(context);
      },
      border: Border.all(
        color: idea.isPinned
            ? colors.accent.withValues(alpha: 0.4)
            : colors.border,
        width: idea.isPinned ? 1.5 : 1,
      ),
      boxShadowOverride: idea.isPinned
          ? [
              BoxShadow(
                color: colors.accent.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ]
          : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tag + pin row
            Row(
              children: [
                Icon(
                  tagIcons[idea.tag]!,
                  size: 13,
                  color: colors.accent.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 5),
                Text(
                  tagLabels[idea.tag]!,
                  style: PulpitFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.accent.withValues(alpha: 0.8),
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                if (idea.isPinned)
                  Icon(
                    Icons.push_pin_rounded,
                    size: 13,
                    color: colors.accent,
                  ),
                const SizedBox(width: 4),
                Text(
                  ageLabel,
                  style: PulpitFonts.inter(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Content
            Text(
              idea.content,
              style: PulpitFonts.inter(
                fontSize: 14,
                height: 1.6,
                color: colors.textPrimary,
              ),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.edit_rounded,
              label: 'Edit idea',
              colors: colors,
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
            _ActionTile(
              icon: idea.isPinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin_rounded,
              label: idea.isPinned ? 'Unpin' : 'Pin to top',
              colors: colors,
              onTap: () {
                Navigator.pop(ctx);
                onPin();
              },
            ),
            _ActionTile(
              icon: Icons.copy_rounded,
              label: 'Copy text',
              colors: colors,
              onTap: () {
                Navigator.pop(ctx);
                onCopy();
              },
            ),
            _ActionTile(
              icon: Icons.delete_rounded,
              label: 'Delete',
              colors: colors,
              destructive: true,
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final PulpitColors colors;
  final bool destructive;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFEF4444) : colors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        label,
        style: PulpitFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
      onTap: () {
        // Generalized here so Edit/Pin/Copy/Delete all get consistent
        // haptics in one place — destructive (Delete) gets the heavier
        // tier, everything else gets the standard confirm tier.
        HapticFeedback.lightImpact();
        if (destructive) HapticFeedback.mediumImpact();
        onTap();
      },
    );
  }
}

// ── Capture / Edit Sheet ──────────────────────────────────────────────────────

class _CaptureSheet extends StatefulWidget {
  final PulpitColors colors;
  final SermonIdea? existing;
  final Map<IdeaTag, String> tagLabels;
  final Map<IdeaTag, IconData> tagIcons;
  final void Function(String content, IdeaTag tag) onSave;

  const _CaptureSheet({
    required this.colors,
    required this.tagLabels,
    required this.tagIcons,
    required this.onSave,
    this.existing,
  });

  @override
  State<_CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends State<_CaptureSheet> {
  late final TextEditingController _controller;
  late IdeaTag _selectedTag;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.existing?.content ?? '');
    _selectedTag = widget.existing?.tag ?? IdeaTag.sermon;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final isEdit = widget.existing != null;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Text(
              isEdit ? 'Edit Idea' : 'Capture Idea',
              style: PulpitFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            // Tag picker
            SizedBox(
              height: 36,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                scrollDirection: Axis.horizontal,
                children: IdeaTag.values.map((tag) {
                  final sel = _selectedTag == tag;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedTag = tag);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? colors.accent : colors.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? colors.accent : colors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.tagIcons[tag]!,
                            size: 13,
                            color: sel
                                ? colors.background
                                : colors.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            widget.tagLabels[tag]!,
                            style: PulpitFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sel
                                  ? colors.background
                                  : colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            // Text field
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 6,
              minLines: 3,
              style: PulpitFonts.inter(
                fontSize: 15,
                height: 1.6,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: "What's on your mind? Jot it down…",
                hintStyle: PulpitFonts.inter(
                  fontSize: 15,
                  color: colors.textSecondary.withValues(alpha: 0.6),
                ),
                filled: true,
                fillColor: colors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: colors.accent, width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 16),
            // Save button
            GestureDetector(
              onTap: () {
                final text = _controller.text.trim();
                if (text.isEmpty) return;
                HapticFeedback.mediumImpact();
                widget.onSave(text, _selectedTag);
                Navigator.pop(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  isEdit ? 'Save Changes' : 'Save Idea',
                  style: PulpitFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.background,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
