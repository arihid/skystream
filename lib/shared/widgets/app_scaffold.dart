import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skystream/core/providers/device_info_provider.dart';
import 'package:skystream/core/utils/layout_constants.dart';
import 'package:skystream/core/utils/responsive_breakpoints.dart';
import 'package:skystream/shared/widgets/custom_bottom_nav.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import '../../features/settings/presentation/general_settings_provider.dart';
import 'loading_indicator.dart';

import 'package:skystream/shared/widgets/gamepad_hints_overlay.dart';

class AppScaffold extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const AppScaffold({super.key, required this.navigationShell});

  int _getRouteIndex(String route) {
    switch (route) {
      case '/home': return 0;
      case '/search': return 1;
      case '/explore': return 2;
      case '/library': return 3;
      case '/settings': return 4;
      default: return 0;
    }
  }

  void _onItemTapped(int index, BuildContext context) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceProfileAsync = ref.watch(deviceProfileProvider);
    final defaultHome = ref.watch(
      generalSettingsProvider.select((s) => s.defaultHomeScreen),
    );
    final defaultIndex = _getRouteIndex(defaultHome);
    final isAtDefaultHome = navigationShell.currentIndex == defaultIndex;

    return deviceProfileAsync.when(
      data: (profile) {
        if (profile.isTv || context.isTabletOrLarger) {
          // 📺 TV & Desktop Layout - 100% Immersive Edge-to-Edge!
          return PopScope(
            canPop: isAtDefaultHome,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) {
                navigationShell.goBranch(defaultIndex);
              }
            },
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                ref
                    .read<DpadActiveNotifier>(isDpadActiveProvider.notifier)
                    .set(false);
              },
              onPointerHover: (_) {
                ref
                    .read<DpadActiveNotifier>(isDpadActiveProvider.notifier)
                    .set(false);
              },
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    final key = event.logicalKey;
                    if (key == LogicalKeyboardKey.arrowDown ||
                        key == LogicalKeyboardKey.arrowUp ||
                        key == LogicalKeyboardKey.arrowLeft ||
                        key == LogicalKeyboardKey.arrowRight ||
                        key == LogicalKeyboardKey.enter ||
                        key == LogicalKeyboardKey.select ||
                        key == LogicalKeyboardKey.space ||
                        key == LogicalKeyboardKey.tab) {
                      ref
                          .read<DpadActiveNotifier>(
                            isDpadActiveProvider.notifier,
                          )
                          .set(true);
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: Material(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: SafeArea(
                    bottom: false,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Content in its own traversal group, positioned first (bottom layer)
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: LayoutConstants.sidebarWidthCompact,
                            ),
                            child: FocusTraversalGroup(
                              policy: WidgetOrderTraversalPolicy(),
                              child: Focus(
                                canRequestFocus: false,
                                skipTraversal: true,
                                onKeyEvent: _onContentKeyEvent,
                                child: widget.navigationShell,
                              ),
                            ),
                          ),
                        ),
                        // Sidebar in its own traversal group, positioned second (top layer)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: LayoutConstants.sidebarWidthCompact,
                          child: FocusTraversalGroup(
                            policy: WidgetOrderTraversalPolicy(),
                            child: AppSidebar(
                              currentIndex: widget.navigationShell.currentIndex,
                              onItemTapped: (int index) =>
                                  _onItemTapped(index, context),
                              focusNodes: _sidebarNodes,
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

        // 📱 Mobile uses Bottom Navigation
        return PopScope(
          canPop: isAtDefaultHome,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              navigationShell.goBranch(defaultIndex);
            }
          },
          child: Scaffold(
            body: navigationShell,
            bottomNavigationBar: CustomBottomNavBar(
              currentIndex: navigationShell.currentIndex,
              onTap: (index) => _onItemTapped(index, context),
            ),
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: AppLoadingIndicator())),
      error: (err, stack) => Scaffold(
        body: Center(
          child: Text(
            AppLocalizations.of(context)!.errorPrefix(err.toString()),
          ),
        ),
      ),
    );
  }
}