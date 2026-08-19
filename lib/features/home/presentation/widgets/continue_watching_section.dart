import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:skystream/core/utils/responsive_breakpoints.dart';
import 'package:skystream/core/utils/layout_constants.dart';

import 'package:skystream/features/home/presentation/widgets/continue_watching_card.dart';
import 'package:skystream/features/library/presentation/history_provider.dart';
import 'package:skystream/shared/widgets/desktop_scroll_wrapper.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            isLarge ? LayoutConstants.dashboardContentPadding : 16,
            widget.topPadding ?? 24,
            isLarge ? LayoutConstants.dashboardContentPadding : 16,
            12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
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
              // REMOVED: "Clear All" UI button 
              // (Now handled entirely by Gamepad 'Y' or Long Press menu!)
            ],
          ),
        ),
        SizedBox(
          height: listHeight,
          child: DesktopScrollWrapper(
            controller: _scrollController,
            showButtons: isLarge, // Show nav buttons on desktop and TV
            child: Builder(
              builder: (context) {
                const double spacing = 16.0;
                return ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.symmetric(
                    horizontal: isLarge
                        ? LayoutConstants.dashboardContentPadding
                        : 16,
                    vertical: 8,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.items.length,
                  itemExtent: width + spacing,
                  itemBuilder: (context, index) {
                    final historyItem = widget.items[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: spacing),
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
    );
  }
}