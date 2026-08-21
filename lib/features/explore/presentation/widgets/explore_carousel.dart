import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:skystream/features/settings/presentation/big_picture_provider.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../shared/widgets/cards_wrapper.dart';
import '../../../../shared/widgets/thumbnail_error_placeholder.dart';

// TV/Gamepad Feature Imports
import 'package:skystream/core/input/gamepad_actions.dart';
import '../../../../core/providers/device_info_provider.dart';

/// Lightweight controller for the hero carousel.
/// API-compatible with the old CarouselSliderController (nextPage/previousPage).
class HeroCarouselController {
  VoidCallback? onNextPage;
  VoidCallback? onPreviousPage;

  void nextPage({Duration? duration, Curve? curve}) => onNextPage?.call();
  void previousPage({Duration? duration, Curve? curve}) =>
      onPreviousPage?.call();
}

class ExploreCarousel extends ConsumerStatefulWidget {
  final List<MultimediaItem> movies;
  final ScrollController? scrollController;
  final void Function(MultimediaItem)? onTap;
  final VoidCallback? onNavigateUp;
  final bool autofocus;

  /// Called once after initState with the internal [HeroCarouselController]
  /// so the parent can drive prev/next from an external UI (e.g. header arrows).
  final void Function(HeroCarouselController controller)? onControllerReady;

  const ExploreCarousel({
    super.key,
    required this.movies,
    this.scrollController,
    this.onTap,
    this.onNavigateUp,
    this.onControllerReady,
    this.autofocus = false,
  });

  @override
  ConsumerState<ExploreCarousel> createState() => _ExploreCarouselState();
}

class _ExploreCarouselState extends ConsumerState<ExploreCarousel>
    with TickerProviderStateMixin {
  final ValueNotifier<int> _currentIndexNotifier = ValueNotifier<int>(0);
  final HeroCarouselController _heroCarouselController =
      HeroCarouselController();
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);
  final FocusNode _carouselFocusNode = FocusNode(debugLabel: 'carousel_anchor');
  bool _isFocusHighlighted = false;
  bool _isVisibleOnScreen = true;

  late final AnimationController _transitionController;
  late final Animation<double> _transitionAnimation;
  int _currentSlide = 0;
  int? _previousSlide;
  bool _isTransitioning = false;

  late final AnimationController _fillController;

  @override
  void initState() {
    super.initState();

    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _transitionAnimation = CurvedAnimation(
      parent: _transitionController,
      curve: Curves.fastOutSlowIn,
    );
    _transitionController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _isTransitioning = false;
          _previousSlide = null;
        });
      }
    });

    _fillController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _fillController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _goToNextSlide();
      }
    });

    _heroCarouselController.onNextPage = _goToNextSlide;
    _heroCarouselController.onPreviousPage = _goToPreviousSlide;

    widget.scrollController?.addListener(_onParentScroll);
    if (widget.onControllerReady != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onControllerReady!(_heroCarouselController);
      });
    }

    _fillController.forward();

    // Defer focus requests so we don't yank focus away from the user
    // if they already started navigating before the carousel loaded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.autofocus) return;
      final currentFocus = FocusManager.instance.primaryFocus;

      if (currentFocus == null ||
          currentFocus == FocusManager.instance.rootScope) {
        _carouselFocusNode.requestFocus();
      }
    });
  }

  void _goToNextSlide() {
    if (widget.movies.length <= 1) return;
    final next = (_currentSlide + 1) % widget.movies.length;
    _startTransitionTo(next);
  }

  void _goToPreviousSlide() {
    if (widget.movies.length <= 1) return;
    final prev =
        (_currentSlide - 1 + widget.movies.length) % widget.movies.length;
    _startTransitionTo(prev);
  }

  void _startTransitionTo(int nextIndex) {
    if (_isTransitioning || nextIndex == _currentSlide || !mounted) return;
    setState(() {
      _previousSlide = _currentSlide;
      _currentSlide = nextIndex;
      _isTransitioning = true;
    });
    _currentIndexNotifier.value = nextIndex;
    _transitionController.forward(from: 0.0);
    _restartFill();
  }

  void _restartFill() {
    _fillController.reset();
    if (_isVisibleOnScreen) {
      _fillController.forward();
    }
  }

  void _onParentScroll() {
    if (widget.scrollController!.hasClients) {
      _scrollOffset.value = widget.scrollController!.offset;
    }
  }

  void _activateCurrent() {
    final movie = widget.movies[_currentSlide];
    if (widget.onTap != null) {
      widget.onTap!(movie);
    } else {
      _navigateToDetails(context, movie);
    }
  }

  @override
  void dispose() {
    _transitionController.dispose();
    _fillController.dispose();
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
    final isDesktop =
        size.width > LayoutConstants.exploreCarouselDesktopBreakpoint;

    // Master Switch Evaluation
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv ?? context.isTv;
    final isBigPicture = ref.watch(bigPictureModeProvider).isEnabled || isTv;

    return VisibilityDetector(
      key: const Key('explore-carousel-visibility'),
      onVisibilityChanged: (info) {
        final visible = info.visibleFraction > 0.1;
        if (visible != _isVisibleOnScreen && mounted) {
          setState(() => _isVisibleOnScreen = visible);
          if (visible) {
            _fillController.forward();
          } else {
            _fillController.stop();
          }
        }
      },
      child: FocusableActionDetector(
        focusNode: _carouselFocusNode,
        autofocus: false, // Managed by initState
        descendantsAreFocusable: false,
        mouseCursor: SystemMouseCursors.click,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        // Catch Gamepad directions purely through intents
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activateCurrent();
              return null;
            },
          ),
          GamepadDirectionalIntent: CallbackAction<GamepadDirectionalIntent>(
            onInvoke: (intent) {
              if (intent.direction == TraversalDirection.left) {
                _goToPreviousSlide();
              } else if (intent.direction == TraversalDirection.right) {
                _goToNextSlide();
              } else if (intent.direction == TraversalDirection.up) {
                if (widget.onNavigateUp != null) {
                  widget.onNavigateUp!.call();
                } else {
                  FocusManager.instance.primaryFocus?.focusInDirection(
                    TraversalDirection.up,
                  );
                }
              } else if (intent.direction == TraversalDirection.down) {
                FocusManager.instance.primaryFocus?.focusInDirection(
                  TraversalDirection.down,
                );
              }
              return null;
            },
          ),
          DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
            onInvoke: (intent) {
              if (intent.direction == TraversalDirection.left) {
                _goToPreviousSlide();
              } else if (intent.direction == TraversalDirection.right) {
                _goToNextSlide();
              } else if (intent.direction == TraversalDirection.up) {
                if (widget.onNavigateUp != null) {
                  widget.onNavigateUp!.call();
                } else {
                  FocusManager.instance.primaryFocus?.focusInDirection(
                    TraversalDirection.up,
                  );
                }
              } else if (intent.direction == TraversalDirection.down) {
                FocusManager.instance.primaryFocus?.focusInDirection(
                  TraversalDirection.down,
                );
              }
              return null;
            },
          ),
        },
        onShowFocusHighlight: (show) {
          setState(() => _isFocusHighlighted = show);
          // Force the screen to scroll to the top if the carousel gets focus
          if (show &&
              widget.scrollController != null &&
              widget.scrollController!.hasClients) {
            widget.scrollController!.animateTo(
              0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity == null) return;
            if (details.primaryVelocity! < -300) {
              _goToNextSlide();
            } else if (details.primaryVelocity! > 300) {
              _goToPreviousSlide();
            }
          },
          child: isDesktop
              ? RepaintBoundary(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      LayoutConstants.dashboardContentPadding,
                      LayoutConstants.spacingSm,
                      LayoutConstants.dashboardContentPadding,
                      0,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: _isFocusHighlighted
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2.5,
                              )
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
                          height: heroHeight,
                          child: _buildCarouselStack(
                            heroHeight,
                            isDesktop: isDesktop || isBigPicture,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : Padding(
                  padding: EdgeInsets.zero,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      border: _isFocusHighlighted
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2.5,
                            )
                          : null,
                    ),
                    child: SizedBox(
                      height: heroHeight,
                      child: _buildCarouselStack(
                        heroHeight,
                        isDesktop: isDesktop || isBigPicture,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Custom carousel with crossfade + scale transition
  // ---------------------------------------------------------------------------

  Widget _buildCarouselStack(double height, {required bool isDesktop}) {
    return Stack(
      children: [
        // Previous slide (exiting) — only during transition
        if (_isTransitioning && _previousSlide != null)
          AnimatedBuilder(
            animation: _transitionAnimation,
            builder: (context, _) {
              final t = _transitionAnimation.value;
              return Opacity(
                opacity: 1.0 - t,
                child: Transform.scale(
                  scale: 1.0 + 0.2 * t,
                  child: _buildSlideForIndex(
                    height,
                    _previousSlide!,
                    isDesktop: isDesktop,
                  ),
                ),
              );
            },
          ),

        // Current slide (entering or static)
        _isTransitioning
            ? AnimatedBuilder(
                animation: _transitionAnimation,
                builder: (context, _) {
                  final t = _transitionAnimation.value;
                  return Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: 0.8 + 0.2 * t,
                      child: _buildSlideForIndex(
                        height,
                        _currentSlide,
                        isDesktop: isDesktop,
                      ),
                    ),
                  );
                },
              )
            : _buildSlideForIndex(height, _currentSlide, isDesktop: isDesktop),

        // Progress bar indicators
        if (widget.movies.length > 1)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: RepaintBoundary(child: _buildProgressIndicators()),
          ),
      ],
    );
  }

  Widget _buildProgressIndicators() {
    return ValueListenableBuilder<int>(
      valueListenable: _currentIndexNotifier,
      builder: (context, currentIndex, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final entry in widget.movies.asMap().entries)
              _ProgressDot(
                key: ValueKey('hcd_${entry.key}'),
                isActive: currentIndex == entry.key,
                fillController: _fillController,
              ),
          ],
        );
      },
    );
  }

  Widget _buildSlideForIndex(
    double height,
    int index, {
    required bool isDesktop,
  }) {
    final movie = widget.movies[index];
    if (widget.scrollController == null) {
      return _buildStaticItem(context, movie, height, isDesktop: isDesktop);
    }
    return _buildCarouselItem(context, movie, height, isDesktop: isDesktop);
  }

  void _navigateToDetails(BuildContext context, MultimediaItem movie) {
    final String mediaType = movie.tmdbMediaType;

    TmdbDetailsRoute(
      movieId: movie.id,
      mediaType: mediaType,
      heroTag: 'hero_${movie.id}',
      source: movie.source,
    ).push<void>(context);
  }

  Widget _buildCarouselItem(
    BuildContext context,
    MultimediaItem movie,
    double height, {
    bool isDesktop = false,
  }) {
    final theme = Theme.of(context);
    final scaffoldColor = theme.scaffoldBackgroundColor;

    return CardsWrapper(
      scaleFactor: 1.0,
      onTap: () {
        if (widget.onTap != null) {
          widget.onTap!(movie);
        } else {
          _navigateToDetails(context, movie);
        }
      },
      borderRadius: BorderRadius.zero,
      child: RepaintBoundary(
        child: ValueListenableBuilder<double>(
          valueListenable: _scrollOffset,
          builder: (context, scrollOffset, child) {
            final parallaxOffset = scrollOffset * 0.1;
            final contentOffset = -scrollOffset * 0.2;
            final opacity = (1.0 - (scrollOffset / (height * 0.5))).clamp(
              0.0,
              1.0,
            );

            return _buildSlideBase(
              context: context,
              movie: movie,
              height: height,
              isDesktop: isDesktop,
              parallaxOffset: parallaxOffset,
              contentOffset: contentOffset,
              opacity: opacity,
              scaffoldColor: scaffoldColor,
              theme: theme,
            );
          },
        ),
      ),
    );
  }

  Widget _buildStaticItem(
    BuildContext context,
    MultimediaItem movie,
    double height, {
    bool isDesktop = false,
  }) {
    final theme = Theme.of(context);
    return CardsWrapper(
      scaleFactor: 1.0,
      onTap: () {
        if (widget.onTap != null) {
          widget.onTap!(movie);
        } else {
          _navigateToDetails(context, movie);
        }
      },
      borderRadius: BorderRadius.zero,
      child: _buildSlideBase(
        context: context,
        movie: movie,
        height: height,
        isDesktop: isDesktop,
        parallaxOffset: 0,
        contentOffset: 0,
        opacity: 1.0,
        scaffoldColor: theme.scaffoldBackgroundColor,
        theme: theme,
      ),
    );
  }

  Widget _buildSlideBase({
    required BuildContext context,
    required MultimediaItem movie,
    required double height,
    required bool isDesktop,
    required double parallaxOffset,
    required double contentOffset,
    required double opacity,
    required Color scaffoldColor,
    required ThemeData theme,
  }) {
    final imageUrl = movie.backdropImageUrl;
    final title = movie.title;

    const bleed = 60.0;

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background Image
          Positioned(
            top: -bleed + parallaxOffset,
            bottom: -bleed - parallaxOffset,
            left: 0,
            right: 0,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) =>
                  Container(color: theme.colorScheme.surfaceContainerHighest),
              errorWidget: (_, _, _) =>
                  ThumbnailErrorPlaceholder(label: title, isBackdrop: true),
            ),
          ),

          // 2. Parallax Gradients
          Positioned(
            top: -bleed + parallaxOffset,
            bottom: -bleed - parallaxOffset,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDesktop
                      ? [
                          Colors.black.withValues(alpha: 0.2),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                          Colors.black.withValues(alpha: 0.75),
                        ]
                      : [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.4),
                          Colors.black.withValues(alpha: 0.8),
                        ],
                  stops: isDesktop
                      ? const [0.0, 0.35, 0.75, 1.0]
                      : const [0.0, 0.4, 0.6, 1.0],
                ),
              ),
            ),
          ),

          // 2.5. Fixed Bottom Feather (eased page transition scrim)
          Positioned(
            bottom: -1,
            left: 0,
            right: 0,
            height: 120,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scaffoldColor.withValues(alpha: 0.0),
                      scaffoldColor.withValues(alpha: 0.15),
                      scaffoldColor.withValues(alpha: 0.45),
                      scaffoldColor.withValues(alpha: 0.8),
                      scaffoldColor,
                    ],
                    stops: const [0.0, 0.5, 0.75, 0.9, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 3. Content
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Transform.translate(
              offset: Offset(0, contentOffset),
              child: opacity >= 0.999
                  ? _buildCarouselContent(
                      isDesktop: isDesktop,
                      movie: movie,
                      theme: theme,
                      context: context,
                    )
                  : Opacity(
                      opacity: opacity,
                      child: _buildCarouselContent(
                        isDesktop: isDesktop,
                        movie: movie,
                        theme: theme,
                        context: context,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselContent({
    required bool isDesktop,
    required MultimediaItem movie,
    required ThemeData theme,
    required BuildContext context,
  }) {
    final logoUrl = movie.logoUrl;
    final title = movie.title;
    final year = movie.year?.toString() ?? '';
    final genres = movie.tags?.join(' • ') ?? '';
    final provider = movie.provider;

    String? type;
    final mType = movie.mediaType.toLowerCase();
    if (mType == 'movie') {
      type = "Movie";
    } else if (mType == 'series' || mType == 'tv') {
      type = "TV Show";
    } else if (mType == 'anime') {
      type = "Anime";
    } else if (mType == 'livestream') {
      type = "Live Stream";
    } else {
      type = mType.isNotEmpty
          ? mType[0].toUpperCase() + mType.substring(1)
          : null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isDesktop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
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
          spacing: 8.0,
          runSpacing: 4.0,
          children: [
            if (provider != null && provider.isNotEmpty) ...[
              _buildMiniBadge(
                context,
                provider.toUpperCase(),
                isProvider: true,
              ),
            ],
            if (type != null) ...[_buildMiniBadge(context, type.toUpperCase())],
            if (genres.isNotEmpty) ...[
              Text(
                genres,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
            if (year.isNotEmpty) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 10,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    year,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildLogo(String logoUrl, String title, {bool isDesktop = false}) {
    if (logoUrl.toLowerCase().endsWith('.svg')) {
      return SvgPicture.network(
        logoUrl,
        height: 140,
        width: 300,
        fit: BoxFit.contain,
        placeholderBuilder: (context) =>
            const SizedBox(height: 140, width: 300),
        errorBuilder: (context, error, stackTrace) =>
            _buildTitleFallback(title, isDesktop: isDesktop),
      );
    }
    return CachedNetworkImage(
      imageUrl: logoUrl,
      height: 140,
      width: 300,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      placeholder: (context, url) => const SizedBox(height: 140, width: 300),
      errorWidget: (context, url, error) =>
          _buildTitleFallback(title, isDesktop: isDesktop),
    );
  }

  Widget _buildTitleFallback(String title, {bool isDesktop = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LayoutConstants.spacingXs),
      child: Text(
        title.toUpperCase(),
        textAlign: isDesktop ? TextAlign.left : TextAlign.center,
        maxLines: isDesktop ? 2 : 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 40,
          fontFamily: 'RobotoCondensed',
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
          shadows: [Shadow(color: Colors.black, blurRadius: 10)],
        ),
      ),
    );
  }

  Widget _buildMiniBadge(
    BuildContext context,
    String label, {
    bool isProvider = false,
  }) {
    final theme = Theme.of(context);
    final color = isProvider
        ? theme.colorScheme.primary
        : theme.colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A single progress dot whose width animates with spring physics.
class _ProgressDot extends StatefulWidget {
  final bool isActive;
  final AnimationController fillController;

  const _ProgressDot({
    super.key,
    required this.isActive,
    required this.fillController,
  });

  @override
  State<_ProgressDot> createState() => _ProgressDotState();
}

class _ProgressDotState extends State<_ProgressDot>
    with SingleTickerProviderStateMixin {
  static const double _activeWidth = 35.0;
  static const double _inactiveWidth = 11.0;
  static const double _height = 4.0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.value = widget.isActive ? 1.0 : 0.0;
  }

  @override
  void didUpdateWidget(_ProgressDot old) {
    super.didUpdateWidget(old);
    if (widget.isActive != old.isActive) {
      _animateToTarget();
    }
  }

  void _animateToTarget() {
    _controller.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 300, damping: 30),
        _controller.value,
        widget.isActive ? 1.0 : 0.0,
        0,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final width = _inactiveWidth + (_activeWidth - _inactiveWidth) * t;

        return Container(
          width: width,
          height: _height,
          margin: const EdgeInsets.symmetric(horizontal: 3.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: Colors.white.withValues(alpha: widget.isActive ? 0.3 : 0.2),
          ),
          child: widget.isActive
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: AnimatedBuilder(
                    animation: widget.fillController,
                    builder: (context, _) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: _activeWidth * widget.fillController.value,
                          height: _height,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      );
                    },
                  ),
                )
              : null,
        );
      },
    );
  }
}
