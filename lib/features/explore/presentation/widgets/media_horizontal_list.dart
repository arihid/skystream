import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../../../core/router/app_router.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../shared/widgets/cards_wrapper.dart';
import '../../../../core/widgets/focusable_wrapper.dart';
import '../../../../shared/widgets/gamepad_hints_overlay.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../shared/widgets/multimedia_card.dart';
import '../view_all_screen.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/utils/image_utils.dart';

class MediaHorizontalList extends StatefulWidget {
  final String title;
  final List<MultimediaItem> mediaList;
  final ViewAllCategory category;
  final void Function(MultimediaItem)? onTap;
  final bool showViewAll;
  final String? heroTagPrefix;

  const MediaHorizontalList({
    super.key,
    required this.title,
    required this.mediaList,
    required this.category,
    this.onTap,
    this.showViewAll = true,
    this.heroTagPrefix,
  });

  @override
  State<MediaHorizontalList> createState() => _MediaHorizontalListState();
}

class _MediaHorizontalListState extends State<MediaHorizontalList> {
  late ScrollController _scrollController;
  bool _isPortrait = true;

  static const int _aspectRatioCacheMax = 5000;
  static final LinkedHashMap<String, bool> _aspectRatioCache =
      LinkedHashMap<String, bool>();

  static bool? _lookupCached(String url) {
    if (!_aspectRatioCache.containsKey(url)) return null;
    final v = _aspectRatioCache.remove(url)!;
    _aspectRatioCache[url] = v;
    return v;
  }

  static void _storeCached(String url, bool isPortrait) {
    _aspectRatioCache.remove(url);
    _aspectRatioCache[url] = isPortrait;
    while (_aspectRatioCache.length > _aspectRatioCacheMax) {
      _aspectRatioCache.remove(_aspectRatioCache.keys.first);
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    if (widget.mediaList.isNotEmpty) {
      final url = widget.mediaList.first.posterImageUrl;
      final cached = _lookupCached(url);
      if (cached != null) {
        _isPortrait = cached;
      } else {
        _checkAspectRatio();
      }
    }
  }

  @override
  void didUpdateWidget(MediaHorizontalList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mediaList.isNotEmpty &&
        oldWidget.mediaList != widget.mediaList) {
      final url = widget.mediaList.first.posterImageUrl;
      final cached = _lookupCached(url);
      if (cached != null) {
        if (_isPortrait != cached) {
          setState(() => _isPortrait = cached);
        }
      } else {
        _checkAspectRatio();
      }
    }
  }

  Future<void> _checkAspectRatio() async {
    if (widget.mediaList.isEmpty) return;
    final url = widget.mediaList.first.posterImageUrl;
    if (url.isEmpty) return;
    final isPortrait = await ImageUtils.isImagePortrait(url);
    _storeCached(url, isPortrait);
    if (mounted && _isPortrait != isPortrait) {
      setState(() {
        _isPortrait = isPortrait;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _navigateToViewAll() {
    ViewAllRoute(
      $extra: ViewAllRouteExtra(
        title: widget.title,
        initialMediaList: widget.mediaList,
        category: widget.category,
        onTap: widget.onTap,
      ),
    ).push<void>(context);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaList.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    
    final isDesktop = context.isDesktop;
    final isBigPicture = context.isTv || context.isDesktop || context.isTabletOrLarger;
    
    const int maxItems = 15;
    final displayList = widget.mediaList.take(maxItems).toList();
    final bool renderViewAll = widget.showViewAll && isBigPicture;
    final int totalCount = displayList.length + (renderViewAll ? 1 : 0);

    final double cardWidth = isDesktop
        ? (_isPortrait ? 200.0 : 300.0)
        : (_isPortrait ? 130.0 : 200.0);
    final double imageHeight = cardWidth / (_isPortrait ? (2 / 3) : (16 / 9));
    final double listHeight = imageHeight + 40.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            isDesktop ? LayoutConstants.dashboardContentPadding : LayoutConstants.spacingMd,
            LayoutConstants.spacingLg,
            isDesktop ? LayoutConstants.dashboardContentPadding : LayoutConstants.spacingMd,
            LayoutConstants.spacingSm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isDesktop ? 24 : 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: isDesktop ? 30 : 20,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
              
              if (widget.showViewAll && !isBigPicture)
                FocusableWrapper(
                  onTap: _navigateToViewAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LayoutConstants.spacingSm,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Text(
                          l10n.viewAll,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 10,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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
          child: Builder(
            builder: (context) {
              final double spacing = isDesktop
                  ? LayoutConstants.spacingLg
                  : LayoutConstants.spacingSm;

              return ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                  dragDevices: {
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  clipBehavior: Clip.none,
                  cacheExtent: 99999,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop
                        ? LayoutConstants.dashboardContentPadding
                        : LayoutConstants.spacingMd,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemCount: totalCount,
                  itemExtent: cardWidth + spacing,
                  itemBuilder: (context, index) {
                    
                    if (index == displayList.length) {
                      return Padding(
                        padding: EdgeInsets.only(right: spacing),
                        child: FocusableWrapper(
                          onTap: _navigateToViewAll,
                          gamepadHints: [
                            GamepadHint(buttonLabel: 'A', actionLabel: 'View All', buttonColor: Colors.greenAccent.shade400),
                          ],
                          child: ExcludeFocus(
                            child: CardsWrapper(
                              onTap: _navigateToViewAll,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: cardWidth,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 32,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      l10n.viewAll,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.primary,
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

                    final item = displayList[index];
                    final imageUrl = item.posterImageUrl;
                    final itemTitle = item.title;
                    final prefix = widget.heroTagPrefix ?? 'list';
                    final uniqueTag = '${prefix}_${widget.title}_${item.id}_${itemTitle.hashCode}_$index';

                    final handleTap = () {
                      if (widget.onTap != null) {
                        widget.onTap!(item);
                      } else {
                        TmdbDetailsRoute(
                          movieId: item.id,
                          mediaType: item.tmdbMediaType,
                          heroTag: uniqueTag,
                          placeholderPoster: imageUrl,
                        ).push<void>(context);
                      }
                    };

                    return Padding(
                      padding: EdgeInsets.only(right: spacing),
                      child: FocusableWrapper(
                        onTap: handleTap,
                        gamepadHints: [
                          GamepadHint(buttonLabel: 'A', actionLabel: 'Select', buttonColor: Colors.greenAccent.shade400),
                        ],
                        child: ExcludeFocus(
                          child: MultimediaCard(
                            imageUrl: imageUrl,
                            title: itemTitle,
                            heroTag: uniqueTag,
                            isPortrait: _isPortrait,
                            onTap: handleTap,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}