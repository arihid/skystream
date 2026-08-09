import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skystream/core/providers/device_info_provider.dart';
import 'package:skystream/core/utils/responsive_breakpoints.dart';
import 'package:skystream/shared/widgets/custom_bottom_nav.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import '../../features/settings/presentation/general_settings_provider.dart';
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
        final isTv = profile.isTv || context.isTabletOrLarger || context.isDesktop;

        if (isTv) {
          // 📺 TV & Desktop Layout - Side Dock hidden, Edge-to-Edge restored!
          return PopScope(
            canPop: isAtDefaultHome,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) {
                navigationShell.goBranch(defaultIndex);
              }
            },
            child: Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              body: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: navigationShell),
                    const GamepadHintsOverlay(), // 🎯 RESTORED GLOBAL HINTS!
                  ],
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
            resizeToAvoidBottomInset: false,
            extendBody: true,
            body: navigationShell,
            bottomNavigationBar: Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: CustomBottomNavBar.bottomInsetFor(context),
              ),
              child: CustomBottomNavBar(
                currentIndex: navigationShell.currentIndex,
                onTap: (index) => _onItemTapped(index, context),
              ),
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
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