import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gamepads/gamepads.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../core/providers/device_info_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'widgets/bookmarks_tab.dart';
import 'widgets/downloads_tab.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;
  StreamSubscription<GamepadEvent>? _gamepadSubscription;
  
  // 🎯 THE FIX: Persistent Focus Scopes!
  // By giving each tab its own FocusScope, Flutter will natively remember 
  // the exact item you last highlighted inside of it!
  late FocusScopeNode _downloadsScope;
  late FocusScopeNode _bookmarksScope;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pageController = PageController();
    _downloadsScope = FocusScopeNode(debugLabel: 'DownloadsScope');
    _bookmarksScope = FocusScopeNode(debugLabel: 'BookmarksScope');

    _pageController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final page = _pageController.page?.round() ?? 0;
        if (_tabController.index != page) {
          _tabController.animateTo(page);
        }
      }
    });

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        final disableSwipe = ref.read(deviceProfileProvider).asData?.value.isTv == true || context.isDesktop;
        
        if (!disableSwipe && _pageController.hasClients) {
          _pageController.animateToPage(
            _tabController.index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.ease,
          );
        } else if (disableSwipe) {
          // 🎯 NATIVE MEMORY: Tell the newly active tab to reclaim focus.
          // It will automatically snap right back to the exact movie/episode you were on!
          if (_tabController.index == 0) {
            _downloadsScope.requestFocus();
          } else {
            _bookmarksScope.requestFocus();
          }
        }
      }
    });

    _gamepadSubscription = Gamepads.events.listen((event) {
      if (!mounted) return;
      
      try {
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) return;
      } catch (_) {}

      if (event.type == KeyType.button && event.value == 1.0) {
        final key = event.key.toLowerCase();
        
        final isLeftBumper = key.contains('l1') || key.contains('lb') || key.contains('button 4') || key.contains('left_shoulder') || key.contains('leftshoulder') || key.contains('left_bumper');
        final isRightBumper = key.contains('r1') || key.contains('rb') || key.contains('button 5') || key.contains('right_shoulder') || key.contains('rightshoulder') || key.contains('right_bumper');

        if (isLeftBumper && _tabController.index > 0) {
          _tabController.animateTo(_tabController.index - 1);
        } else if (isRightBumper && _tabController.index < _tabController.length - 1) {
          _tabController.animateTo(_tabController.index + 1);
        }
      }
    });
  }

  @override
  void dispose() {
    _gamepadSubscription?.cancel();
    _tabController.dispose();
    _pageController.dispose();
    _downloadsScope.dispose();
    _bookmarksScope.dispose();
    super.dispose();
  }

  // 🎯 AAA ANIMATION: Custom Sliding Tabs for Gamepad/TV
  // Provides a beautiful parallax slide + crossfade without PageView's focus-bleed bugs!
  Widget _buildTvTabTransitions() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSlide(
              offset: _tabController.index == 0 ? Offset.zero : const Offset(-0.15, 0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _tabController.index == 0 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: _tabController.index != 0,
                  child: ExcludeFocus(
                    excluding: _tabController.index != 0,
                    child: FocusScope(
                      node: _downloadsScope,
                      child: const DownloadsTab(),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSlide(
              offset: _tabController.index == 1 ? Offset.zero : const Offset(0.15, 0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _tabController.index == 1 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: _tabController.index != 1,
                  child: ExcludeFocus(
                    excluding: _tabController.index != 1,
                    child: FocusScope(
                      node: _bookmarksScope,
                      child: const BookmarksTab(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    final isDesktop = context.isDesktop;
    final isWidescreen = isTv || context.isTabletOrLarger;
    
    final disableSwipe = isTv || isDesktop;

    if (isWidescreen) return _buildWidescreen(context, isTv, disableSwipe);
    return _buildMobile(context, isTv, disableSwipe);
  }

  Widget _buildWidescreen(BuildContext context, bool isTv, bool disableSwipe) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              height: LayoutConstants.dashboardHeaderHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: LayoutConstants.dashboardContentPadding,
              ),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.library,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  _buildTabChips(context, isTv),
                ],
              ),
            ),
          ),
          Expanded(
            child: disableSwipe
                ? _buildTvTabTransitions()
                : PageView(
                    controller: _pageController,
                    onPageChanged: (index) => _tabController.animateTo(index),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      ExcludeFocus(excluding: _tabController.index != 0, child: FocusScope(node: _downloadsScope, child: const DownloadsTab())),
                      ExcludeFocus(excluding: _tabController.index != 1, child: FocusScope(node: _bookmarksScope, child: const BookmarksTab())),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(BuildContext context, bool isTv, bool disableSwipe) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.library),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: AppLocalizations.of(context)!.downloads, icon: const Icon(Icons.download_for_offline_rounded)),
            Tab(text: AppLocalizations.of(context)!.bookmarks, icon: const Icon(Icons.bookmark_rounded)),
          ],
        ),
      ),
      body: disableSwipe
          ? _buildTvTabTransitions()
          : PageView(
              controller: _pageController,
              onPageChanged: (index) => _tabController.animateTo(index),
              physics: const BouncingScrollPhysics(),
              children: [
                ExcludeFocus(excluding: _tabController.index != 0, child: FocusScope(node: _downloadsScope, child: const DownloadsTab())),
                ExcludeFocus(excluding: _tabController.index != 1, child: FocusScope(node: _bookmarksScope, child: const BookmarksTab())),
              ],
            ),
    );
  }

  Widget _buildTabChips(BuildContext context, bool isTv) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TabChip(
              label: l10n.downloads,
              icon: Icons.download_for_offline_rounded,
              selected: _tabController.index == 0,
              onTap: () => _tabController.animateTo(0),
              theme: theme,
              bumperHint: isTv ? 'L1' : null, 
            ),
            const SizedBox(width: 8),
            _TabChip(
              label: l10n.bookmarks,
              icon: Icons.bookmark_rounded,
              selected: _tabController.index == 1,
              onTap: () => _tabController.animateTo(1),
              theme: theme,
              bumperHint: isTv ? 'R1' : null, 
            ),
          ],
        );
      },
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;
  final String? bumperHint; 

  const _TabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.theme,
    this.bumperHint,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(LayoutConstants.radiusPill),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (bumperHint == 'L1') ...[
                _buildBumperBadge(),
                const SizedBox(width: 8),
              ],
              Icon(
                icon,
                size: 16,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (bumperHint == 'R1') ...[
                const SizedBox(width: 8),
                _buildBumperBadge(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBumperBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        bumperHint!,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}