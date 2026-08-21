import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skystream/core/input/gamepad_actions.dart';
import 'package:skystream/core/providers/device_info_provider.dart';
import 'package:skystream/core/utils/layout_constants.dart';
import 'package:skystream/core/utils/responsive_breakpoints.dart';
import 'package:skystream/shared/widgets/custom_bottom_nav.dart';
import 'package:skystream/shared/widgets/app_sidebar.dart';
import 'package:dpad/dpad.dart'; 

import 'package:skystream/l10n/generated/app_localizations.dart';
import 'package:skystream/shared/widgets/global_system_menu.dart';
import '../../features/settings/presentation/general_settings_provider.dart';
import 'loading_indicator.dart';

import 'package:skystream/shared/widgets/gamepad_hints_overlay.dart';
import 'package:skystream/features/settings/presentation/big_picture_provider.dart';
import 'package:skystream/core/input/gamepad_intents.dart';

class AppScaffold extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppScaffold({super.key, required this.navigationShell});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  late final List<FocusNode> _sidebarNodes = List.generate(
    kSidebarDestinationCount,
    (i) => FocusNode(debugLabel: 'sidebar_$i'),
  );

  bool _isGlobalMenuVisible = false;

  @override
  void dispose() {
    for (final n in _sidebarNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _onItemTapped(int index, BuildContext context) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
    // Hide menu after selection on TV
    setState(() {
      _isGlobalMenuVisible = false;
    });
  }

  int _getRouteIndex(String route) {
    switch (route) {
      case '/home':
        return 0;
      case '/search':
        return 1;
      case '/explore':
        return 2;
      case '/library':
        return 3;
      case '/settings':
        return 4;
      default:
        return 0;
    }
  }

  void _toggleMenu(bool isBigPicture) {
    if (!isBigPicture) return;
    GlobalSystemMenu.toggle(context);
  }

  KeyEventResult _onContentKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;

    final moved = primary.focusInDirection(TraversalDirection.left);
    if (moved) {
      return KeyEventResult.handled;
    }
    
    final isBigPicture = ref.read(bigPictureModeProvider).isEnabled;
    
    if (isBigPicture) {
      GlobalSystemMenu.toggle(context);
      return KeyEventResult.handled;
    } else {
      final idx = widget.navigationShell.currentIndex;
      if (idx < 0 || idx >= _sidebarNodes.length) return KeyEventResult.ignored;
      
      final target = _sidebarNodes[idx];
      if (!target.canRequestFocus) return KeyEventResult.ignored;
      
      target.requestFocus();
      return KeyEventResult.handled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceProfileAsync = ref.watch(deviceProfileProvider);
    final defaultHome = ref.watch(
      generalSettingsProvider.select((s) => s.defaultHomeScreen),
    );
    final defaultIndex = _getRouteIndex(defaultHome);
    final isAtDefaultHome = widget.navigationShell.currentIndex == defaultIndex;
    
    final isBigPicture = ref.watch(bigPictureModeProvider).isEnabled;

    return deviceProfileAsync.when(
      data: (profile) {
        // FORK 1: Big Picture Layout
        if (isBigPicture) {
          return Actions(
            actions: <Type, Action<Intent>>{
              AppMenuIntent: CallbackAction<AppMenuIntent>(
                onInvoke: (_) {
                  _toggleMenu(isBigPicture);
                  return null;
                }
              ),
              AppBackIntent: CallbackAction<AppBackIntent>(
                onInvoke: (_) {
                  if (_isGlobalMenuVisible) {
                    setState(() => _isGlobalMenuVisible = false);
                    return null; 
                  }
                  return null; // Bubble up back intent
                }
              ),
            },
            child: PopScope(
              canPop: isAtDefaultHome && !_isGlobalMenuVisible,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop) {
                  if (_isGlobalMenuVisible) {
                    setState(() => _isGlobalMenuVisible = false);
                  } else {
                    widget.navigationShell.goBranch(defaultIndex);
                  }
                }
              },
              child: Scaffold(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                body: SafeArea(
                  bottom: false,
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
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
                          const GamepadHintsOverlay(),
                        ],
                      ),
                      
                      if (_isGlobalMenuVisible)
                        Positioned.fill(
                          child: GlobalSystemMenu(
                            currentLocation: GoRouterState.of(context).uri.path,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // FORK 2: Classic Upstream Desktop / Tablet Layout (Dock is always visible here)
        if (profile.isTv || context.isTabletOrLarger) {
          return PopScope(
            canPop: isAtDefaultHome,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) {
                widget.navigationShell.goBranch(defaultIndex);
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

        // FORK 3: Classic Upstream Mobile Layout (Bottom Navigation)
        return PopScope(
          canPop: isAtDefaultHome,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              widget.navigationShell.goBranch(defaultIndex);
            }
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            extendBody: true,
            body: widget.navigationShell,
            bottomNavigationBar: Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: CustomBottomNavBar.bottomInsetFor(context),
              ),
              child: CustomBottomNavBar(
                currentIndex: widget.navigationShell.currentIndex,
                onTap: (index) => _onItemTapped(index, context),
              ),
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