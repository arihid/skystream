import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/router/app_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../shared/widgets/cards_wrapper.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/device_info_provider.dart';

import '../../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/input/gamepad_actions.dart'; 

class ExploreCarousel extends ConsumerStatefulWidget {
  final List<MultimediaItem> movies;
  final ScrollController? scrollController;
  final void Function(MultimediaItem)? onTap;
  final VoidCallback? onNavigateUp;

  final void Function(CarouselSliderController controller)? onControllerReady;

  const ExploreCarousel({
    super.key,
    required this.movies,
    this.scrollController,
    this.onTap,
    this.onNavigateUp,
    this.onControllerReady,
  });

  @override
  ConsumerState<ExploreCarousel> createState() => _ExploreCarouselState();
}

class _ExploreCarouselState extends ConsumerState<ExploreCarousel> {
  final ValueNotifier<int> _currentIndexNotifier = ValueNotifier<int>(0);
  final CarouselSliderController _carouselController = CarouselSliderController();
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);
  final FocusNode _carouselFocusNode = FocusNode(debugLabel: 'carousel_anchor');
  
  bool _isCarouselHovered = false;
  bool _isFocusHighlighted = false;
  bool _isVisibleOnScreen = true;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onParentScroll);
    if (widget.onControllerReady != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onControllerReady!(_carouselController);
      });
    }
  }

  void _onParentScroll() {
    if (widget.scrollController!.hasClients) {
      _scrollOffset.value = widget.scrollController!.offset;
    }
  }

  void _activateCurrent() {
    final movie = widget.movies[_currentIndexNotifier.value];
    if (widget.onTap != null) {
      widget.onTap!(movie);
    } else {
      _navigateToDetails(context, movie);
    }
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onParentScroll);
    _scrollOffset.dispose();
    _currentIndexNotifier.dispose();
    _carouselFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.movies.isEmpty) return const SizedBox.shrink();

    final size = MediaQuery.sizeOf(context);
    final heroHeight = size.height * 0.60;
    final isDesktop = size.width > LayoutConstants.exploreCarouselDesktopBreakpoint;

    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv ?? context.isTv;

    return VisibilityDetector(
      key: const Key('explore-carousel-visibility'),
      onVisibilityChanged: (info) {
        final visible = info.visibleFraction > 0.1;
        if (visible != _isVisibleOnScreen && mounted) {
          setState(() => _isVisibleOnScreen = visible);
        }
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activateCurrent();
              return null;
            },
          ),
          GamepadDirectionalIntent: CallbackAction<GamepadDirectionalIntent>(
            onInvoke: (GamepadDirectionalIntent intent) {
              if (intent.direction == TraversalDirection.left) {
                _carouselController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                return null;
              } else if (intent.direction == TraversalDirection.right) {
                _carouselController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                return null;
              } 
              // FIX: If UP or DOWN is pressed, we manually trigger a focus shift to escape the carousel naturally!
              Actions.maybeInvoke(context, DirectionalFocusIntent(intent.direction));
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _carouselFocusNode,
          onFocusChange: (hasFocus) {
            setState(() => _isFocusHighlighted = hasFocus);
            if (hasFocus) {
              Scrollable.ensureVisible(
                context,
                alignment: 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
              );
            }
          },
          onKeyEvent: (node, event) {
            // FIXED: Removed invalid gameButton constants. 
            // Standard Keyboards and Remotes trigger this block. 
            // Gamepads are handled securely by the Actions map above!
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _carouselController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _carouselController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter) {
                _activateCurrent();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored; // Let Up/Down escape normally!
          },
          child: isDesktop
              ? MouseRegion(
                  onEnter: (_) => setState(() => _isCarouselHovered = true),
                  onExit: (_) => setState(() => _isCarouselHovered = false),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LayoutConstants.dashboardContentPadding,
                      vertical: LayoutConstants.spacingSm,
                    ),
                    child: AnimatedScale(
                      scale: (_isCarouselHovered || _isFocusHighlighted) ? 1.015 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isFocusHighlighted
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent, 
                            width: 3.0,
                          ),
                          boxShadow: _isFocusHighlighted
                              ? [
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.primary.withAlpha(100),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  )
                                ]
                              : [],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: SizedBox(
                            height: heroHeight,
                            child: Stack(
                              children: [
                                CarouselSlider.builder(
                                  carouselController: _carouselController,
                                  itemCount: widget.movies.length,
                                  options: CarouselOptions(
                                    height: heroHeight,
                                    viewportFraction: 1.0,
                                    autoPlay: _isVisibleOnScreen,
                                    autoPlayInterval: const Duration(seconds: 15),
                                    autoPlayAnimationDuration: const Duration(milliseconds: 1000),
                                    autoPlayCurve: Curves.fastOutSlowIn,
                                    enableInfiniteScroll: !isTv,
                                    scrollPhysics: const BouncingScrollPhysics(),
                                    onPageChanged: (index, reason) {
                                      _currentIndexNotifier.value = index;
                                    },
                                  ),
                                  itemBuilder: (context, index, realIndex) {
                                    final movie = widget.movies[index];
                                    return ExcludeFocus(
                                      child: _buildCarouselItem(
                                        context,
                                        movie,
                                        heroHeight,
                                        index,
                                        isDesktop: isDesktop || isTv,
                                      ),
                                    );
                                  },
                                ),
                                Positioned(
                                  bottom: 20,
                                  left: 0,
                                  right: 0,
                                  child: RepaintBoundary(
                                    child: ValueListenableBuilder<int>(
                                      valueListenable: _currentIndexNotifier,
                                      builder: (context, currentIndex, _) {
                                        return Wrap(
                                          alignment: WrapAlignment.center,
                                          children: widget.movies.asMap().entries.map((entry) {
                                            return AnimatedContainer(
                                              duration: const Duration(milliseconds: 300),
                                              width: currentIndex == entry.key ? 24.0 : 8.0,
                                              height: 8.0,
                                              margin: const EdgeInsets.symmetric(horizontal: 4.0),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(4),
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: currentIndex == entry.key ? 0.9 : 0.3),
                                              ),
                                            );
                                          }).toList(),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ) 
              : Padding(
                  padding: EdgeInsets.zero,
                  child: AnimatedScale(
                    scale: _isFocusHighlighted ? 1.015 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isFocusHighlighted
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 3.0,
                        ),
                        boxShadow: _isFocusHighlighted
                              ? [
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.primary.withAlpha(100),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  )
                                ]
                              : [],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          height: heroHeight,
                          child: Stack(
                            children: [
                              CarouselSlider.builder(
                                carouselController: _carouselController,
                                itemCount: widget.movies.length,
                                options: CarouselOptions(
                                  height: heroHeight,
                                  viewportFraction: 1.0,
                                  autoPlay: _isVisibleOnScreen,
                                  autoPlayInterval: const Duration(seconds: 15),
                                  autoPlayAnimationDuration: const Duration(milliseconds: 1000),
                                  autoPlayCurve: Curves.fastOutSlowIn,
                                  enableInfiniteScroll: !isTv,
                                  scrollPhysics: const BouncingScrollPhysics(),
                                  onPageChanged: (index, reason) {
                                    _currentIndexNotifier.value = index;
                                  },
                                ),
                                itemBuilder: (context, index, realIndex) {
                                  final movie = widget.movies[index];
                                  return ExcludeFocus(
                                    child: _buildCarouselItem(
                                      context,
                                      movie,
                                      heroHeight,
                                      index,
                                      isDesktop: isDesktop || isTv,
                                    ),
                                  );
                                },
                              ),
                              Positioned(
                                bottom: 20,
                                left: 0,
                                right: 0,
                                child: RepaintBoundary(
                                  child: ValueListenableBuilder<int>(
                                    valueListenable: _currentIndexNotifier,
                                    builder: (context, currentIndex, _) {
                                      return Wrap(
                                        alignment: WrapAlignment.center,
                                        children: widget.movies.asMap().entries.map((entry) {
                                          return AnimatedContainer(
                                            duration: const Duration(milliseconds: 300),
                                            width: currentIndex == entry.key ? 24.0 : 8.0,
                                            height: 8.0,
                                            margin: const EdgeInsets.symmetric(horizontal: 4.0),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(4),
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: currentIndex == entry.key ? 0.9 : 0.3),
                                            ),
                                          );
                                        }).toList(),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  void _navigateToDetails(BuildContext context, MultimediaItem movie) {
    final String mediaType = movie.tmdbMediaType;

    TmdbDetailsRoute(
      movieId: movie.id,
      mediaType: mediaType,
      heroTag: 'hero_${movie.id}',
    ).push<void>(context);
  }

  Widget _buildCarouselItem(
    BuildContext context, MultimediaItem movie, double height, int index, {bool isDesktop = false,}
  ) {
    final imageUrl = movie.backdropImageUrl;
    final title = movie.title;
    final logoUrl = movie.logoUrl;
    final theme = Theme.of(context);
    final scaffoldColor = theme.scaffoldBackgroundColor;

    final year = movie.year?.toString() ?? '';
    final genres = movie.tags?.join(' • ') ?? '';
    final provider = movie.provider;

    String? type;
    final mType = movie.mediaType.toLowerCase();

    if (mType == 'movie') type = "Movie";
    else if (mType == 'series' || mType == 'tv') type = "TV Show";
    else if (mType == 'anime') type = "Anime";
    else if (mType == 'livestream') type = "Live Stream";
    else type = mType.isNotEmpty ? mType[0].toUpperCase() + mType.substring(1) : null;

    final metadata = [
      if (provider != null && provider.isNotEmpty) provider,
      type,
      if (genres.isNotEmpty) genres,
      if (year.isNotEmpty) year,
    ].whereType<String>().join(' • ');

    if (widget.scrollController == null) {
      return _buildStaticItem(
        context, imageUrl, logoUrl, title, metadata, height, movie, index, isDesktop: isDesktop,
      );
    }

    return CardsWrapper(
      scaleFactor: 1.0,
      onTap: () {
        if (widget.onTap != null) widget.onTap!(movie);
        else _navigateToDetails(context, movie);
      },
      borderRadius: BorderRadius.zero,
      child: RepaintBoundary(
        child: ValueListenableBuilder<double>(
          valueListenable: _scrollOffset,
          builder: (context, scrollOffset, child) {
            final parallaxOffset = scrollOffset * 0.1;
            final contentOffset = -scrollOffset * 0.2;
            final opacity = (1.0 - (scrollOffset / (height * 0.5))).clamp(0.0, 1.0);

            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Transform.translate(
                    offset: Offset(0, parallaxOffset),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl, fit: BoxFit.cover, height: height, width: double.infinity,
                      placeholder: (context, url) => Container(color: theme.colorScheme.surfaceContainerHighest),
                      errorWidget: (_, _, _) => ThumbnailErrorPlaceholder(label: title, isBackdrop: true),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: isDesktop
                              ? [
                                  Colors.black.withValues(alpha: 0.2), Colors.transparent,
                                  Colors.black.withValues(alpha: 0.6), Colors.black.withValues(alpha: 0.85),
                                ]
                              : [
                                  Colors.black.withValues(alpha: 0.3), Colors.transparent,
                                  Colors.black.withValues(alpha: 0.1), scaffoldColor.withValues(alpha: 0.8), scaffoldColor,
                                ],
                          stops: isDesktop ? const [0.0, 0.35, 0.75, 1.0] : const [0.0, 0.4, 0.6, 0.85, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24, right: 24, bottom: 50,
                    child: Transform.translate(
                      offset: Offset(0, contentOffset),
                      child: opacity >= 0.999
                          ? _buildCarouselContent(
                              isDesktop: isDesktop, logoUrl: logoUrl, title: title, provider: provider, type: type, genres: genres, year: year, theme: theme, context: context,
                            )
                          : Opacity(
                              opacity: opacity,
                              child: _buildCarouselContent(
                                isDesktop: isDesktop, logoUrl: logoUrl, title: title, provider: provider, type: type, genres: genres, year: year, theme: theme, context: context,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCarouselContent({
    required bool isDesktop, required String? logoUrl, required String title,
    required String? provider, required String? type, required String genres,
    required String year, required ThemeData theme, required BuildContext context,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isDesktop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (logoUrl != null)
          Padding(
            padding: const EdgeInsets.only(bottom: LayoutConstants.spacingLg),
            child: _buildLogo(logoUrl, title, isDesktop: isDesktop),
          )
        else
          _buildTitleFallback(title, isDesktop: isDesktop),
        Wrap(
          alignment: isDesktop ? WrapAlignment.start : WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8.0, runSpacing: 4.0,
          children: [
            if (provider != null && provider.isNotEmpty) ...[_buildMiniBadge(context, provider.toUpperCase(), isProvider: true)],
            if (type != null) ...[_buildMiniBadge(context, type.toUpperCase())],
            if (genres.isNotEmpty) ...[
              Text(genres, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
            ],
            if (year.isNotEmpty) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_rounded, size: 10, color: Colors.white.withValues(alpha: 0.6)), const SizedBox(width: 4),
                  Text(year, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildStaticItem(
    BuildContext context, String imageUrl, String? logoUrl, String title,
    String metadata, double height, MultimediaItem movie, int index, {bool isDesktop = false,}
  ) {
    return CardsWrapper(
      scaleFactor: 1.0,
      onTap: () {
        if (widget.onTap != null) widget.onTap!(movie);
        else _navigateToDetails(context, movie);
      },
      borderRadius: BorderRadius.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: imageUrl, fit: BoxFit.cover, height: height, width: double.infinity,
            placeholder: (context, url) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
            errorWidget: (_, _, _) => ThumbnailErrorPlaceholder(label: title, isBackdrop: true),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8), Theme.of(context).scaffoldBackgroundColor],
                stops: const [0.5, 0.85, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 24, right: 24, bottom: 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logoUrl != null) _buildLogo(logoUrl, title, isDesktop: isDesktop)
                else _buildTitleFallback(title, isDesktop: isDesktop),
                const SizedBox(height: 8),
                Text(metadata, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(String logoUrl, String title, {bool isDesktop = false}) {
    if (logoUrl.toLowerCase().endsWith('.svg')) {
      return SvgPicture.network(
        logoUrl, height: 140, width: 300, fit: BoxFit.contain,
        placeholderBuilder: (context) => const SizedBox(height: 140, width: 300),
        errorBuilder: (context, error, stackTrace) => _buildTitleFallback(title, isDesktop: isDesktop),
      );
    }
    return CachedNetworkImage(
      imageUrl: logoUrl, height: 140, width: 300, fit: BoxFit.contain, alignment: Alignment.bottomCenter,
      placeholder: (context, url) => const SizedBox(height: 140, width: 300),
      errorWidget: (context, url, error) => _buildTitleFallback(title, isDesktop: isDesktop),
    );
  }

  Widget _buildTitleFallback(String title, {bool isDesktop = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LayoutConstants.spacingXs),
      child: Text(
        title.toUpperCase(), textAlign: isDesktop ? TextAlign.left : TextAlign.center, maxLines: isDesktop ? 2 : 3, overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white, fontSize: 40, fontFamily: 'RobotoCondensed', fontWeight: FontWeight.w900,
          letterSpacing: 1.0, shadows: [Shadow(color: Colors.black, blurRadius: 10)],
        ),
      ),
    );
  }

  Widget _buildMiniBadge(BuildContext context, String label, {bool isProvider = false}) {
    final theme = Theme.of(context);
    final color = isProvider ? theme.colorScheme.primary : theme.colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(
        label, style: theme.textTheme.labelSmall?.copyWith(color: color, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5),
      ),
    );
  }
}