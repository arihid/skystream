import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/utils/layout_constants.dart';
import 'package:skystream/core/extensions/extension_manager.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import 'package:skystream/core/widgets/focusable_wrapper.dart';
import 'package:skystream/features/home/presentation/delegates/home_search_delegate.dart';
import 'package:skystream/features/home/presentation/home_provider.dart';
import 'dart:async';

class DashboardHeaderBar extends ConsumerWidget {
  final FocusNode searchFocusNode;
  final VoidCallback onShowProviderSelector;

  const DashboardHeaderBar({
    super.key,
    required this.searchFocusNode,
    required this.onShowProviderSelector,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final activeProvider = ref.watch(activeProviderProvider);

    return Container(
      height: LayoutConstants.dashboardHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: LayoutConstants.dashboardContentPadding),
      child: Row(
        children: [
          // Capsule search bar
          Expanded(
            child: FocusableWrapper(
              useScaleEffect: false,
              borderRadius: BorderRadius.circular(LayoutConstants.radiusPill),
              onTap: () {
                unawaited(
                  showSearch<void>(
                    context: context, delegate: HomeSearchDelegate(),
                    useRootNavigator: false, maintainState: true,
                  ),
                );
              },
              child: Container(
                height: 38, constraints: const BoxConstraints(maxWidth: 500),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(LayoutConstants.radiusPill),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${l10n.search}...',
                        style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Refresh button
          FocusableWrapper(
            borderRadius: BorderRadius.circular(18),
            onTap: () => ref.read(homeDataProvider.notifier).fetch(),
            child: Container(
              width: 36, height: 36, alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              child: Icon(Icons.refresh, color: theme.colorScheme.onSurfaceVariant, size: 18),
            ),
          ),
          const SizedBox(width: 12),

          // Provider chip
          FocusableWrapper(
            borderRadius: BorderRadius.circular(LayoutConstants.radiusPill),
            onTap: onShowProviderSelector,
            child: Container(
              height: 36, padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(LayoutConstants.radiusPill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.extension, color: theme.colorScheme.primary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    activeProvider?.name ?? l10n.none,
                    style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}