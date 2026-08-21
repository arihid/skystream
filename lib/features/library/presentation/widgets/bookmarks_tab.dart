import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/image_fallbacks.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../shared/widgets/multimedia_card.dart';
import '../library_provider.dart';

import '../library_state.dart';
import '../../../../shared/widgets/loading_indicator.dart';

// TV/Gamepad Feature Imports
import '../../../../core/widgets/focusable_wrapper.dart';
import '../../../../shared/widgets/gamepad_hints_overlay.dart';

class BookmarksTab extends ConsumerStatefulWidget {
  final FocusNode? firstItemFocusNode;
  const BookmarksTab({super.key, this.firstItemFocusNode});

  @override
  ConsumerState<BookmarksTab> createState() => _BookmarksTabState();
}

class _BookmarksTabState extends ConsumerState<BookmarksTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final libraryState = ref.watch(libraryProvider);
    final isLarge = context.isTabletOrLarger;
    final double totalHeight = isLarge ? 180.0 : 150.0;

    return switch (libraryState) {
      LibraryLoading() => const Center(child: AppLoadingIndicator()),
      LibraryError(message: final msg) => Center(child: Text(msg)),
      LibraryEmpty() => _buildEmpty(context),
      LibrarySuccess(items: final items) => GridView.builder(
        scrollCacheExtent: const ScrollCacheExtent.pixels(99999),
        padding: const EdgeInsets.fromLTRB(
          LayoutConstants.spacingMd,
          LayoutConstants.spacingMd,
          LayoutConstants.spacingMd,
          100,
        ),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: totalHeight,
          childAspectRatio: 2 / 3.4,
          crossAxisSpacing: LayoutConstants.spacingMd,
          mainAxisSpacing: LayoutConstants.spacingMd,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];

          return _BookmarkCard(
            item: item,
            index: index,
            firstItemFocusNode: index == 0 ? widget.firstItemFocusNode : null,
          );
        },
      ),
    };
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bookmark_outline_rounded,
            size: 64,
            color: Theme.of(context).dividerColor,
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.libraryEmpty,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _BookmarkCard extends HookConsumerWidget {
  final MultimediaItem item;
  final int index;
  final FocusNode? firstItemFocusNode;

  const _BookmarkCard({
    required this.item,
    required this.index,
    this.firstItemFocusNode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final localNode = useFocusNode();
    final nodeToUse = firstItemFocusNode ?? localNode;

    final handleTap = () async {
      // 1. Wait for the user to return from the Details Screen
      await DetailsRoute(
        $extra: DetailsRouteExtra(item: item),
      ).push<void>(context);

      // 2. Instantly reclaim focus!
      if (context.mounted) {
        nodeToUse.requestFocus();
      }
    };

    return FocusableWrapper(
      focusNode: nodeToUse,
      onTap: handleTap,
      useScaleEffect: true,
      gamepadHints: [
        GamepadHint(
          buttonLabel: 'A',
          actionLabel: l10n.hintSelect,
          buttonColor: Colors.greenAccent.shade400,
        ),
        GamepadHint(
          buttonLabel: 'LB',
          actionLabel: l10n.hintPrevTab,
          buttonColor: Colors.white,
        ),
        GamepadHint(
          buttonLabel: 'RB',
          actionLabel: l10n.hintNextTab,
          buttonColor: Colors.white,
        ),
        GamepadHint(
          buttonLabel: '≡',
          actionLabel: l10n.hintMenu,
          buttonColor: Colors.white,
        ),
      ],
      child: ExcludeFocus(
        child: MultimediaCard(
          key: ValueKey(item.url),
          imageUrl:
              AppImageFallbacks.poster(item.posterUrl, label: item.title) ?? '',
          title: item.title,
          heroTag: 'lib_bookmark_${item.url}_$index',
          onTap: handleTap,
        ),
      ),
    );
  }
}
