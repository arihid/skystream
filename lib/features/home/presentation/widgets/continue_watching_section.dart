import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:skystream/core/utils/responsive_breakpoints.dart';
import 'package:skystream/core/utils/layout_constants.dart';

import 'package:skystream/features/home/presentation/widgets/continue_watching_card.dart';
import 'package:skystream/features/library/presentation/history_provider.dart';
import 'package:skystream/shared/widgets/desktop_scroll_wrapper.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import 'package:skystream/core/services/notification_service.dart';
import 'package:skystream/core/widgets/focusable_wrapper.dart';

class ContinueWatchingSection extends ConsumerStatefulWidget {
  final String title;
  final List<HistoryItem> items;
  final double? topPadding;

  const ContinueWatchingSection({
    super.key,
    required this.title,
    required this.items,
    this.topPadding,
  });

  @override
  ConsumerState<ContinueWatchingSection> createState() =>
      _ContinueWatchingSectionState();
}

class _ContinueWatchingSectionState
    extends ConsumerState<ContinueWatchingSection> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final isLarge = context.isTabletOrLarger;

    final double width = isLarge ? 360.0 : 280.0;
    final double listHeight = isLarge ? 200.0 : 150.0;

    // FocusTraversalGroup fence applied!
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              isLarge ? LayoutConstants.dashboardContentPadding : 16,
              24,
              isLarge ? LayoutConstants.dashboardContentPadding : 16,
              12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Tight Anchor applied!
                FocusableWrapper(
                  onTap: () {},
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: isLarge ? 24 : 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: isLarge ? 30 : 20,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
                FocusableWrapper(
                  onTap: () {
                    final l10n = AppLocalizations.of(context)!;
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(l10n.clearAllHistory),
                        content: Text(l10n.confirmClearHistory),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(l10n.cancel),
                          ),
                          TextButton(
                            onPressed: () {
                              ref.read(watchHistoryProvider.notifier).clearAllHistory();
                              Navigator.pop(context);
                              ref.read(notificationServiceProvider).showSuccess(l10n.watchHistoryCleared);
                            },
                            child: Text(
                              l10n.clearAll,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.delete_sweep, size: 16, color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 6),
                        Text(
                          AppLocalizations.of(context)!.clearAll,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: listHeight,
            child: DesktopScrollWrapper(
              controller: _scrollController,
              showButtons: false, // Disabled Desktop Arrows completely!
              child: Builder(
                builder: (context) {
                  final double spacing = isLarge ? 24.0 : 12.0;
                  return ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(
                      horizontal: isLarge ? LayoutConstants.dashboardContentPadding : 16,
                      vertical: 8,
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.items.length,
                    itemExtent: width + spacing,
                    itemBuilder: (context, index) {
                      final historyItem = widget.items[index];
                      return Padding(
                        padding: EdgeInsets.only(right: spacing),
                        child: ContinueWatchingCard(
                          key: ValueKey(historyItem.item.url),
                          historyItem: historyItem,
                          width: width,
                          isLarge: isLarge,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}