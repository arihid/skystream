import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/gamepad_actions.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../core/providers/device_info_provider.dart';
import '../../../l10n/generated/app_localizations.dart';

// Big Picture Master Switch
import '../../settings/presentation/big_picture_provider.dart';

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
  final FocusNode _downloadsFocusNode = FocusNode(
    debugLabel: 'downloads_first_item',
  );
  final FocusNode _bookmarksFocusNode = FocusNode(
    debugLabel: 'bookmarks_first_item',
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Autofocus the active tab's first item on launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (_tabController.index == 0) {
          _downloadsFocusNode.requestFocus();
        } else {
          _bookmarksFocusNode.requestFocus();
        }
      }
    });
  }

  void _switchTab(int index) {
    if (_tabController.index == index) return;

    _tabController.animateTo(index);
    // Wait for the slide animation to finish before safely requesting focus
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (index == 0) {
        _downloadsFocusNode.requestFocus();
      } else {
        _bookmarksFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _downloadsFocusNode.dispose();
    _bookmarksFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(deviceProfileProvider).asData?.value;

    // Master Switch Evaluation
    final isTv = profile?.isTv == true || context.isTv;
    final isBigPicture = ref.watch(bigPictureModeProvider).isEnabled || isTv;

    final isWidescreen = isBigPicture || context.isTabletOrLarger;

    Widget content;

    if (isWidescreen) {
      content = Scaffold(
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
                    _buildTabChips(context, isBigPicture),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const BouncingScrollPhysics(),
                children: [
                  DownloadsTab(firstItemFocusNode: _downloadsFocusNode),
                  BookmarksTab(firstItemFocusNode: _bookmarksFocusNode),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      content = Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.library),
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                text: AppLocalizations.of(context)!.downloads,
                icon: const Icon(Icons.download_for_offline_rounded),
              ),
              Tab(
                text: AppLocalizations.of(context)!.bookmarks,
                icon: const Icon(Icons.bookmark_rounded),
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          physics: const BouncingScrollPhysics(),
          children: [
            DownloadsTab(firstItemFocusNode: _downloadsFocusNode),
            BookmarksTab(firstItemFocusNode: _bookmarksFocusNode),
          ],
        ),
      );
    }

    // Catch Gamepad Bumper Intents to switch tabs globally on this screen
    return Actions(
      actions: <Type, Action<Intent>>{
        AppLeftBumperIntent: CallbackAction<AppLeftBumperIntent>(
          onInvoke: (_) {
            _switchTab(_tabController.index == 0 ? 1 : 0);
            return null;
          },
        ),
        AppRightBumperIntent: CallbackAction<AppRightBumperIntent>(
          onInvoke: (_) {
            _switchTab(_tabController.index == 1 ? 0 : 1);
            return null;
          },
        ),
      },
      child: content,
    );
  }

  Widget _buildTabChips(BuildContext context, bool isBigPicture) {
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
              onTap: () => _switchTab(0),
              theme: theme,
              isBigPicture: isBigPicture,
            ),
            const SizedBox(width: 8),
            _TabChip(
              label: l10n.bookmarks,
              icon: Icons.bookmark_rounded,
              selected: _tabController.index == 1,
              onTap: () => _switchTab(1),
              theme: theme,
              isBigPicture: isBigPicture,
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
  final bool isBigPicture;

  const _TabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.theme,
    required this.isBigPicture,
  });

  @override
  Widget build(BuildContext context) {
    // Exclude from focus in Big Picture mode so users rely on bumpers
    // This traps the D-pad inside the content grids perfectly.
    return ExcludeFocus(
      excluding: isBigPicture,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
            borderRadius: BorderRadius.circular(LayoutConstants.radiusPill),
            border: Border.all(color: Colors.transparent, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
            ],
          ),
        ),
      ),
    );
  }
}
