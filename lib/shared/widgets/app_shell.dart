import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../state/theme_provider.dart';

/// Root scaffold for the 6 main destinations of the app, wired in as a
/// [StatefulShellRoute] in app_router.dart.
///
/// Why this exists: before this, Sermons was the only reachable screen from
/// a cold start — Bible, Word Study, Idea Bank, and Profile/Settings were
/// all fully built screens with registered routes but *zero* tap target
/// anywhere in the UI that led to them. `StatefulShellRoute.indexedStack`
/// keeps each tab's navigation state (scroll position, nested pushes)
/// alive when switching tabs, unlike a plain IndexedStack you'd wire up
/// by hand. Home was added later as the app's landing destination — see
/// home_screen.dart — pushing every other branch's path over by one.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // Bottom nav visibility, driven by scroll direction from whatever
  // scrollable is active in the current tab. NotificationListener catches
  // ScrollNotification bubbling up from ANY descendant scroll view (a
  // ListView, GridView, PageView, etc. several Navigator pushes deep inside
  // navigationShell) without each individual screen needing to know about
  // this — scroll notifications propagate up the widget tree regardless of
  // how many tabs/pages are nested underneath.
  bool _navVisible = true;

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      final direction = notification.direction;
      if (direction == ScrollDirection.reverse && _navVisible) {
        // Scrolling down (revealing more content below) — hide.
        setState(() => _navVisible = false);
      } else if (direction == ScrollDirection.forward && !_navVisible) {
        // Scrolling up (back toward the top) — reveal.
        setState(() => _navVisible = true);
      }
    }
    return false; // Let the notification keep bubbling.
  }

  @override
  Widget build(BuildContext context) {
    final colors = PulpitColors.of(ref.watch(themeProvider));
    // Home (index 0) is the landing hub — its own destination tiles are the
    // primary way to navigate from there, so the tab bar stays hidden on
    // Home and only appears once the user taps into an actual section.
    // Tapping "Home" from inside any section collapses it again. Solomon's
    // framing: "the itemized icons... are great... when user goes to one
    // of them, the tabs below now appear so user can navigate easily."
    final isHome = widget.navigationShell.currentIndex == 0;
    final showNav = !isHome && _navVisible;

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: widget.navigationShell,
      ),
      bottomNavigationBar: ClipRect(
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          heightFactor: showNav ? 1.0 : 0.0,
          child: Container(
            decoration: BoxDecoration(
              color: colors.card,
              border: Border(top: BorderSide(color: colors.border, width: 0.5)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 60,
                child: Row(
                  children: [
                    _NavItem(
                      icon: Icons.home_rounded,
                      label: 'Home',
                      selected: widget.navigationShell.currentIndex == 0,
                      colors: colors,
                      onTap: () => _onTap(0),
                    ),
                    _NavItem(
                      icon: Icons.menu_book_rounded,
                      label: 'Sermons',
                      selected: widget.navigationShell.currentIndex == 1,
                      colors: colors,
                      onTap: () => _onTap(1),
                    ),
                    _NavItem(
                      icon: Icons.auto_stories_rounded,
                      label: 'Bible',
                      selected: widget.navigationShell.currentIndex == 2,
                      colors: colors,
                      onTap: () => _onTap(2),
                    ),
                    _NavItem(
                      icon: Icons.psychology_alt_rounded,
                      label: 'Word Study',
                      selected: widget.navigationShell.currentIndex == 3,
                      colors: colors,
                      onTap: () => _onTap(3),
                    ),
                    _NavItem(
                      icon: Icons.lightbulb_rounded,
                      label: 'Ideas',
                      selected: widget.navigationShell.currentIndex == 4,
                      colors: colors,
                      onTap: () => _onTap(4),
                    ),
                    _NavItem(
                      icon: Icons.person_rounded,
                      label: 'Profile',
                      selected: widget.navigationShell.currentIndex == 5,
                      colors: colors,
                      onTap: () => _onTap(5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onTap(int index) {
    // Every other tab-switch/toggle surface in the app fires selectionClick
    // on tap — this was the one bottom-nav-shaped hole in that pattern.
    HapticFeedback.selectionClick();
    // Switching tabs should always bring the nav back — otherwise tapping a
    // tab while it's hidden would be a dead tap target.
    if (!_navVisible) setState(() => _navVisible = true);
    // goBranch with initialLocation:true when re-tapping the already-active
    // tab resets that branch back to its root (e.g. tapping "Sermons" again
    // while deep in a scroll position pops back to the top) — standard
    // bottom-nav behavior.
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final PulpitColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? colors.accent : colors.textSecondary;
    // Icon-only: adding a 6th tab (Home) on a 360dp-wide test device left
    // no room for icon+label without labels crowding/truncating ("Word
    // Study" was already tight at 5 tabs). The selection pill + icon
    // recolor already does the "which tab is this" job on its own — this
    // was true even before, per the comment below — so dropping the label
    // loses no information, just the crowding. Tooltip keeps the name
    // available on long-press for accessibility.
    return Expanded(
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: SizedBox(
              height: 34,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Icon-only slide+scale (0.08 offset, 1.16 scale on a 22px
                  // icon) turned out to be too small a delta to register
                  // against the recolor happening at the same time —
                  // Solomon tested on-device and couldn't see it. The
                  // background pill below is what actually reads as a
                  // spring morph from normal viewing distance; the icon
                  // lift/scale stays as a smaller secondary flourish on top
                  // of it, bumped up slightly too.
                  AnimatedScale(
                    duration: const Duration(milliseconds: 340),
                    curve: Curves.easeOutBack,
                    scale: selected ? 1.0 : 0.4,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: selected ? 1.0 : 0.0,
                      child: Container(
                        width: 46,
                        height: 34,
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(17),
                        ),
                      ),
                    ),
                  ),
                  AnimatedSlide(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.elasticOut,
                    offset: selected ? const Offset(0, -0.12) : Offset.zero,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.elasticOut,
                      scale: selected ? 1.22 : 1.0,
                      child: TweenAnimationBuilder<Color?>(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOut,
                        tween: ColorTween(end: color),
                        builder: (context, animatedColor, _) =>
                            Icon(icon, size: 23, color: animatedColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
