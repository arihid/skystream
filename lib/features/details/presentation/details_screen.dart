import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';

import '../../../core/domain/entity/multimedia_item.dart';
import '../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../../core/utils/image_fallbacks.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skystream/core/utils/layout_constants.dart';
import 'package:skystream/core/utils/responsive_breakpoints.dart';

import 'package:skystream/shared/widgets/custom_widgets.dart';

import '../../library/presentation/library_provider.dart';
import '../../library/presentation/library_state.dart';

import 'details_controller.dart';
import "widgets/details_layout_widgets.dart";
import "widgets/details_desktop_hero.dart";
import "widgets/premium_details_widgets.dart";
import "../../../shared/widgets/expandable_text.dart";
import "../../../shared/widgets/loading_indicator.dart";
import 'package:skystream/l10n/generated/app_localizations.dart';

class DetailsScreen extends ConsumerStatefulWidget {
  final MultimediaItem item;
  final bool autoPlay;

  const DetailsScreen({super.key, required this.item, this.autoPlay = false});

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  bool _didTriggerAutoPlay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(detailsControllerProvider(widget.item.url).notifier)
          .loadDetails(widget.item, autoPlay: widget.autoPlay);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(detailsControllerProvider(widget.item.url), (prev, next) {
      if (!widget.autoPlay || _didTriggerAutoPlay) return;
      final prevState = prev ?? const DetailsState();
      final nextState = next;
      if (prevState.details.isLoading != true || !nextState.details.hasValue) {
        return;
      }
      final item = nextState.details.value!;
      _didTriggerAutoPlay = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref
            .read(detailsControllerProvider(widget.item.url).notifier)
            .handlePlayPress(context, item);
      });
    });

    final isBookmarked = ref.watch(
      libraryProvider.select(
        (state) =>
            state is LibrarySuccess &&
            state.items.any((i) => i.url == widget.item.url),
      ),
    );
    final libraryNotifier = ref.read(libraryProvider.notifier);
    final isLarge = context.isTabletOrLarger;

    final detailsAsync = ref.watch(
      detailsControllerProvider(widget.item.url).select((s) => s.details),
    );
    final details = detailsAsync.value;
    final isMovie = ref.watch(
      detailsControllerProvider(widget.item.url).select((s) => s.isMovie),
    );
    final item = details ?? widget.item;

    final l10n = AppLocalizations.of(context)!;

    // Setting to dynamic bool to avoid dead code warnings
    bool isBigPicture = DateTime.now().year > 2000; 

    if (isLarge) {
      return _buildDesktopLayout(
        context, item, details, detailsAsync, isMovie, isBookmarked,
        libraryNotifier, l10n, isBigPicture,
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: LayoutConstants.detailsExpandedHeightMobile,
            stretch: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground, StretchMode.blurBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'banner_${item.url}',
                    child: CachedNetworkImage(
                      imageUrl: AppImageFallbacks.optional(item.bannerUrl) ?? AppImageFallbacks.poster(item.posterUrl, label: item.title) ?? '',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      // Bound decoded bitmap; plugin backdrops are often at
                      // source resolution. Without this, 4K-source posters
                      // burn ~33 MB per detail page.
                      memCacheWidth:
                          (MediaQuery.sizeOf(context).width *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      placeholder: (context, url) =>
                          Container(color: Theme.of(context).dividerColor),
                      errorWidget: (_, _, _) => ThumbnailErrorPlaceholder(
                        label: item.title,
                        isBackdrop: true,
                      ),
                    ),
                  ),
                  // 1. Legibility Scrim: Fixed dark-tinted overlay at the bottom of the backdrop
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.65),
                        ],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                  // 2. Blend-into-page transition: Theme-aware eased fade to surface
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0.0),
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0.15),
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0.45),
                          Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withValues(alpha: 0.8),
                          Theme.of(context).scaffoldBackgroundColor,
                        ],
                        stops: const [0.0, 0.5, 0.75, 0.9, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            leading: isBigPicture ? const SizedBox.shrink() : Focus(
              descendantsAreTraversable: false,
              child: CustomButton(
                shape: const CircleBorder(),
                backgroundColor: Colors.black45,
                onPressed: () => context.pop(),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
            ),
            actions: const [],
          ),
          ..._buildMobileSlivers(
            context, item, details, detailsAsync, isMovie, l10n, isBookmarked, libraryNotifier,
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context, MultimediaItem item, MultimediaItem? details,
    AsyncValue<MultimediaItem?> detailsState, bool isMovie, bool isBookmarked,
    dynamic libraryNotifier, AppLocalizations l10n, bool isBigPicture,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: isBigPicture ? const SizedBox.shrink() : IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
          style: IconButton.styleFrom(
            backgroundColor: isDark ? Colors.black45 : Colors.white54,
            foregroundColor: textColor,
          ),
        ),
        actions: const [],
      ),
      body: DetailsDesktopHero(
        displayItem: item,
        baseItem: widget.item,
        details: details,
        detailsState: detailsState,
        isMovie: isMovie,
        itemUrl: widget.item.url,
        actionButtons: _buildStackedActionButtons(
          context, isBookmarked, libraryNotifier, item, details, detailsState,
        ),
        child: _buildDesktopContentBelow(
          context, item, details, detailsState, isMovie, l10n,
        ),
      ),
    );
  }

  Widget _buildStackedActionButtons(
    BuildContext context, bool isBookmarked, dynamic libraryNotifier, 
    MultimediaItem item, MultimediaItem? details, AsyncValue<MultimediaItem?> detailsState,
  ) {
    // 1. Calculate exact same padding used in the Play CustomButton
    final isMobile = context.isMobile;
    final btnPadding = EdgeInsets.symmetric(
      vertical: isMobile ? LayoutConstants.spacingSm : LayoutConstants.spacingMd,
      horizontal: LayoutConstants.spacingMd,
    );

    // 2. Disable button while loading (details == null or AsyncLoading)
    final isLoading = detailsState is AsyncLoading || details == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailsActionButtons(
          item: widget.item,
          details: details,
          itemUrl: widget.item.url,
        ),
        const SizedBox(height: 12),
        // 3. Swapped to CustomButton! This ensures exact height, border radius, 
        //    and gamepad focus glow behavior matches the Play button perfectly.
        CustomButton(
          isPrimary: !isBookmarked,
          isOutlined: isBookmarked, // Automatically handles styling!
          onPressed: isLoading ? null : () {
            if (isBookmarked) {
              libraryNotifier.removeItem(item.url);
            } else {
              libraryNotifier.addItem(item);
            }
          },
          child: Padding(
            padding: btnPadding,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isBookmarked 
                      ? Icons.bookmark_remove_rounded 
                      : Icons.bookmark_add_rounded,
                ),
                const SizedBox(width: LayoutConstants.spacingXs),
                Text(
                  isBookmarked ? "Remove Bookmark" : "Add Bookmark",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopContentBelow(
    BuildContext context, MultimediaItem item, MultimediaItem? details,
    AsyncValue<MultimediaItem?> detailsState, bool isMovie, AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detailsState is AsyncLoading)
          const Center(child: AppLoadingIndicator())
        else if (detailsState is AsyncError)
          Text("Error: ${detailsState.error}", style: TextStyle(color: Theme.of(context).colorScheme.error))
        else if (!isMovie && details?.episodes != null)
          DetailsSeasonListWrapper(itemUrl: widget.item.url),

        const SizedBox(height: 16),
        DetailsDesktopEpisodeColumn(parentItem: item, itemUrl: widget.item.url, isMovie: isMovie),
        const SizedBox(height: 32),

        if (item.cast != null && item.cast!.isNotEmpty) ...[
          CastCarousel(cast: item.cast!),
        ],
        if (item.trailers != null && item.trailers!.isNotEmpty) ...[
          const SizedBox(height: 32),
          TrailersSection(trailers: item.trailers!),
        ],
        if (item.recommendations != null && item.recommendations!.isNotEmpty) ...[
          const SizedBox(height: 32),
          RecommendationsCarousel(
            items: item.recommendations!,
            onItemTap: (rec) {
              DetailsRoute($extra: DetailsRouteExtra(item: rec)).push<void>(context);
            },
          ),
        ],
        const SizedBox(height: 100),
      ],
    );
  }

  List<Widget> _buildMobileSlivers(
    BuildContext context, MultimediaItem item, MultimediaItem? details,
    AsyncValue<MultimediaItem?> detailsState, bool isMovie, AppLocalizations l10n,
    bool isBookmarked, dynamic libraryNotifier,
  ) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: 'poster_${item.url}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: AppImageFallbacks.poster(item.posterUrl, label: item.title) ?? '',
                        width: 100, height: 150, fit: BoxFit.cover,
                        errorWidget: (_, _, _) => ThumbnailErrorPlaceholder(label: item.title),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.logoUrl != null)
                          CachedNetworkImage(
                            imageUrl: item.logoUrl!, height: 50, fit: BoxFit.contain, alignment: Alignment.centerLeft,
                            errorWidget: (_, _, _) => Text(item.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                          )
                        else
                          Text(item.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        MetadataBar(item: item, isLoading: detailsState is AsyncLoading),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              _buildStackedActionButtons(context, isBookmarked, libraryNotifier, item, details, detailsState),

              if (item.nextAiring != null) ...[
                const SizedBox(height: 16),
                NextAiringWidget(nextAiring: item.nextAiring!),
              ],
              const SizedBox(height: 24),
              Text(
                l10n.synopsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ExpandableText(
                text: item.description ?? l10n.noDescription, maxLines: 4,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).textTheme.bodyMedium?.color, height: 1.5),
              ),
              const SizedBox(height: 32),
              if (detailsState is AsyncLoading)
                const Center(child: AppLoadingIndicator())
              else if (detailsState is AsyncError)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                  child: Text(AppLocalizations.of(context)!.errorPrefix(detailsState.error.toString())),
                )
              else if (!isMovie && details?.episodes != null)
                DetailsSeasonListWrapper(itemUrl: widget.item.url),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        sliver: SliverDetailsEpisodeList(parentItem: item, itemUrl: widget.item.url, isMovie: isMovie),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.cast != null && item.cast!.isNotEmpty) ...[
                const SizedBox(height: 16),
                CastCarousel(cast: item.cast!),
              ],
              if (item.trailers != null && item.trailers!.isNotEmpty) ...[
                const SizedBox(height: 32),
                TrailersSection(trailers: item.trailers!),
              ],
              if (item.recommendations != null && item.recommendations!.isNotEmpty) ...[
                const SizedBox(height: 32),
                RecommendationsCarousel(
                  items: item.recommendations!,
                  onItemTap: (rec) {
                    DetailsRoute($extra: DetailsRouteExtra(item: rec)).push<void>(context);
                  },
                ),
              ],
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    ];
  }
}