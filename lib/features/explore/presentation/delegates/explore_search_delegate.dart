import 'package:flutter/material.dart';
import 'package:gamepads/gamepads.dart';
import '../../../../core/router/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';

import '../../../../core/utils/layout_constants.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../../../../shared/widgets/multimedia_card.dart';

import '../../../../shared/widgets/virtual_keyboard.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import '../../../../core/input/gamepad_intents.dart'; 
import '../../../../core/widgets/focusable_wrapper.dart'; 
import '../../../../shared/widgets/gamepad_hints_overlay.dart'; 

import '../controllers/explore_search_controller.dart';

class ExploreSearchDelegate extends SearchDelegate<void> {
  ExploreSearchDelegate()
    : super(
        searchFieldLabel: 'Search movies, tv shows...',
        searchFieldStyle: const TextStyle(color: Colors.white70, fontSize: 18),
      );

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    final isBigPicture = MediaQuery.sizeOf(context).width > 600;

    if (isBigPicture) {
      return theme.copyWith(
        appBarTheme: const AppBarTheme(
          toolbarHeight: 0.0,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      );
    }

    return theme.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        toolbarHeight: 70,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        border: InputBorder.none,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: theme.colorScheme.primary,
        selectionColor: theme.colorScheme.primary.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildFakeHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(LayoutConstants.dashboardContentPadding, 24, LayoutConstants.dashboardContentPadding, 8),
      child: Row(
        children: [
          Icon(Icons.search, size: 28, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              query.isEmpty ? 'Search movies, tv shows...' : query,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: query.isEmpty 
                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5) 
                    : theme.colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return const [ SizedBox(width: 8) ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return const SizedBox.shrink();
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.isEmpty) return const SizedBox.shrink();
    
    final isBigPicture = MediaQuery.sizeOf(context).width > 600;
    
    Widget content = _SearchResultsGrid(
      query: query,
      onJumpToSearch: () => showSuggestions(context),
    );

    if (isBigPicture) {
      return Actions(
        actions: <Type, Action<Intent>>{
          AppBackIntent: CallbackAction<AppBackIntent>(
            onInvoke: (_) {
              showSuggestions(context);
              return null;
            }
          ),
        },
        child: Column(
          children: [
            _buildFakeHeader(context),
            Expanded(child: content),
          ],
        ),
      );
    }

    return content;
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final isBigPicture = MediaQuery.sizeOf(context).width > 600;

    if (isBigPicture) {
      return _ExploreSearchKeyboardAndList(
        initialQuery: query,
        fakeHeader: _buildFakeHeader(context),
        onQueryChanged: (val) {
          query = val;
        },
        onSearch: () {
          if (query.isNotEmpty) {
            FocusManager.instance.primaryFocus?.unfocus();
            showResults(context);
          }
        },
      );
    }

    return query.isEmpty 
        ? Center(
            child: Text(
              'Type to search...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontSize: 18,
              ),
            ),
          )
        : _SearchSuggestionsList(
            query: query,
            onSelect: (val) {
              query = val;
              FocusManager.instance.primaryFocus?.unfocus();
              showResults(context);
            }
          );
  }
}

class _ExploreSearchKeyboardAndList extends ConsumerStatefulWidget {
  final String initialQuery;
  final Widget fakeHeader;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onSearch;

  const _ExploreSearchKeyboardAndList({
    required this.initialQuery,
    required this.fakeHeader,
    required this.onQueryChanged,
    required this.onSearch,
  });

  @override
  ConsumerState<_ExploreSearchKeyboardAndList> createState() =>
      _ExploreSearchKeyboardAndListState();
}

class _ExploreSearchKeyboardAndListState extends ConsumerState<_ExploreSearchKeyboardAndList> {
  final FocusNode _keyboardProxyNode = FocusNode(skipTraversal: true);
  final FocusNode _listProxyNode = FocusNode(skipTraversal: true);
  StreamSubscription<GamepadEvent>? _gamepadSubscription;
  DateTime _lastLTTime = DateTime.now();
  bool _isKeyboardActiveRegion = true;

  @override
  void initState() {
    super.initState();
    _isKeyboardActiveRegion = widget.initialQuery.isEmpty;

    _gamepadSubscription = Gamepads.events.listen((event) {
      if (!mounted) return;
      if (!TickerMode.of(context)) return;

      try {
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) return;
      } catch (_) {}

      final key = event.key.toLowerCase();
      // 🎯 FIXED: Correctly constrained LT mapping
      final isLT = key == 'l2' || key == 'button 6' || (key.contains('trigger') && key.contains('left'));
      
      if (isLT) {
        if ((event.type == KeyType.button && event.value == 1.0) ||
            (event.type == KeyType.analog && event.value > 0.5)) {
          if (DateTime.now().difference(_lastLTTime).inMilliseconds > 500) {
            _lastLTTime = DateTime.now();
            _toggleKeyboardAndList();
          }
        }
      }
    });
  }

  void _toggleKeyboardAndList() {
    final nextRegionIsKeyboard = !_isKeyboardActiveRegion;
    setState(() {
      _isKeyboardActiveRegion = nextRegionIsKeyboard;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (nextRegionIsKeyboard) {
        _keyboardProxyNode.requestFocus();
      } else {
        _listProxyNode.requestFocus();
      }
      Future.microtask(() => FocusManager.instance.primaryFocus?.nextFocus());
    });
  }

  @override
  void dispose() {
    _gamepadSubscription?.cancel();
    _keyboardProxyNode.dispose();
    _listProxyNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        AppBackIntent: CallbackAction<AppBackIntent>(
          onInvoke: (_) {
            Navigator.maybePop(context);
            return null;
          }
        ),
      },
      child: Column(
        children: [
          widget.fakeHeader,
          Expanded(
            child: ExcludeFocus(
              excluding: _isKeyboardActiveRegion,
              child: Focus(
                focusNode: _listProxyNode,
                skipTraversal: true,
                child: widget.initialQuery.isEmpty
                    ? Center(
                        child: Text(
                          'Type to search...',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                            fontSize: 18,
                          ),
                        ),
                      )
                    : _SearchSuggestionsList(
                        query: widget.initialQuery,
                        isKeyboardActiveRegion: _isKeyboardActiveRegion,
                        onSelect: (val) {
                          widget.onQueryChanged(val);
                          widget.onSearch();
                        },
                      ),
              ),
            ),
          ),
          ExcludeFocus(
            excluding: !_isKeyboardActiveRegion,
            child: Focus(
              focusNode: _keyboardProxyNode,
              skipTraversal: true,
              onFocusChange: (hasFocus) {
                if (hasFocus) {
                  Future.microtask(() {
                    if (mounted) {
                      ref.read(focusedGamepadHintsProvider.notifier).state = [
                        GamepadHint(buttonLabel: 'A', actionLabel: 'Type', buttonColor: Colors.greenAccent.shade400),
                        GamepadHint(buttonLabel: 'LT', actionLabel: 'List', buttonColor: Colors.grey.shade400),
                      ];
                    }
                  });
                } else {
                  Future.microtask(() {
                    if (mounted) {
                      final currentHints = ref.read(focusedGamepadHintsProvider);
                      if (currentHints?.any((h) => h.actionLabel == 'Type') == true) {
                        ref.read(focusedGamepadHintsProvider.notifier).state = null;
                      }
                    }
                  });
                }
              },
              child: VirtualKeyboard(
                query: widget.initialQuery,
                onQueryChanged: widget.onQueryChanged,
                onSearch: widget.onSearch,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchSuggestionsList extends ConsumerStatefulWidget {
  final String query;
  final void Function(String)? onSelect;
  final bool isKeyboardActiveRegion;

  const _SearchSuggestionsList({
    required this.query,
    this.onSelect,
    this.isKeyboardActiveRegion = false,
  });

  @override
  ConsumerState<_SearchSuggestionsList> createState() =>
      _SearchSuggestionsListState();
}

class _SearchSuggestionsListState
    extends ConsumerState<_SearchSuggestionsList> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(exploreSearchControllerProvider.notifier)
          .onQueryChanged(widget.query);
    });
  }

  @override
  void didUpdateWidget(covariant _SearchSuggestionsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      Future.microtask(() {
        if (!context.mounted) return;
        ref
            .read(exploreSearchControllerProvider.notifier)
            .onQueryChanged(widget.query);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(exploreSearchControllerProvider);
    final isLoading = searchState.isLoading;
    final suggestions = searchState.suggestions;
    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
        ),
      );
    }

    if (suggestions.isEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    final isBigPicture = MediaQuery.sizeOf(context).width > 600;

    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final item = suggestions[index];
        final title = item.title;
        final year = item.releaseDate.split('-').first;
        final mediaType = item.mediaType;

        final tile = ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CachedNetworkImage(
              imageUrl: item.thumbnailImageUrl,
              width: 40,
              height: 60,
              fit: BoxFit.cover,
              placeholder: (_, _) => ShimmerPlaceholder(borderRadius: 4),
            ),
          ),
          title: Text(
            item.title ?? '', 
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          subtitle: Text(
            '$mediaType ${year.isNotEmpty ? '($year)' : ''}',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          onTap: () {
            if (widget.onSelect != null) {
              widget.onSelect!(item.title ?? '');
            } else {
              TmdbDetailsRoute(
                movieId: item.id,
                mediaType: item.tmdbMediaType,
                heroTag: 'search_${item.id}',
              ).push<void>(context);
            }
          },
        );

        if (isBigPicture) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Material(
              type: MaterialType.transparency,
              child: FocusableWrapper(
                useScaleEffect: false,
                gamepadHints: [
                  GamepadHint(buttonLabel: 'A', actionLabel: 'Search', buttonColor: Colors.greenAccent.shade400),
                  GamepadHint(buttonLabel: 'LT', actionLabel: widget.isKeyboardActiveRegion ? 'List' : 'Keyboard', buttonColor: Colors.grey.shade400),
                ],
                onTap: () {
                  if (widget.onSelect != null) widget.onSelect!(item.title ?? '');
                },
                child: tile,
              ),
            ),
          );
        }

        return Material(
          type: MaterialType.transparency,
          child: tile,
        );
      },
    );
  }
}

class _SearchResultsGrid extends ConsumerStatefulWidget {
  final String query;
  final VoidCallback? onJumpToSearch;

  const _SearchResultsGrid({required this.query, this.onJumpToSearch});

  @override
  ConsumerState<_SearchResultsGrid> createState() => _SearchResultsGridState();
}

class _SearchResultsGridState extends ConsumerState<_SearchResultsGrid> {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<GamepadEvent>? _gamepadSubscription;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(exploreSearchControllerProvider.notifier)
          .fetchResults(widget.query);
    });

    _gamepadSubscription = Gamepads.events.listen((event) {
      if (!mounted) return;
      if (!TickerMode.of(context)) return;
      try {
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) return;
      } catch (_) {}

      final key = event.key.toLowerCase();
      // 🎯 FIXED: Correctly constrained LT mapping
      final isLT = key == 'l2' || key == 'button 6' || (key.contains('trigger') && key.contains('left'));
                   
      if (isLT && ((event.type == KeyType.button && event.value == 1.0) || (event.type == KeyType.analog && event.value > 0.5))) {
         if (widget.onJumpToSearch != null) widget.onJumpToSearch!();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _SearchResultsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      Future.microtask(() {
        if (!context.mounted) return;
        ref
            .read(exploreSearchControllerProvider.notifier)
            .fetchResults(widget.query);
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(exploreSearchControllerProvider.notifier).fetchNextPage();
    }
  }

  @override
  void dispose() {
    _gamepadSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(exploreSearchControllerProvider);
    final isLoading = searchState.isLoading;
    final results = searchState.results;
    if (isLoading && results.isEmpty) {
      final screenWidth = MediaQuery.sizeOf(context).width;
      final isDesktop =
          screenWidth > LayoutConstants.exploreCarouselDesktopBreakpoint;
      final maxExtent = isDesktop ? 240.0 : 150.0;
      const childAspectRatio = 0.55;

      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxExtent,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: 10,
        itemBuilder: (context, index) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: ShimmerPlaceholder(borderRadius: 12)),
              const SizedBox(height: 8),
              ShimmerPlaceholder.rectangular(height: 14, borderRadius: 4),
            ],
          );
        },
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 60,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              "No results found for \"${widget.query}\"",
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop =
        screenWidth > LayoutConstants.exploreCarouselDesktopBreakpoint;
    final maxExtent = isDesktop ? 240.0 : 150.0;
    const childAspectRatio = 0.55;

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: results.length + (isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= results.length) {
          return ShimmerPlaceholder(borderRadius: 12);
        }

        final item = results[index];
        final imageUrl = item.posterImageUrl;
        final title = item.title;
        final id = item.id;
        final uniqueTag = 'search_result_${id}_$index';

        return FocusableWrapper(
          autofocus: index == 0,
          gamepadHints: [
            GamepadHint(buttonLabel: 'A', actionLabel: 'View', buttonColor: Colors.greenAccent.shade400),
            GamepadHint(buttonLabel: 'LT', actionLabel: 'Search field', buttonColor: Colors.grey.shade400),
          ],
          onTap: () {
            TmdbDetailsRoute(
              movieId: id,
              mediaType: item.tmdbMediaType,
              heroTag: uniqueTag,
              placeholderPoster: imageUrl,
            ).push<void>(context);
          },
          child: MultimediaCard(
            imageUrl: imageUrl,
            title: title ?? '', 
            heroTag: uniqueTag,
            onTap: () {
              TmdbDetailsRoute(
                movieId: id,
                mediaType: item.tmdbMediaType,
                heroTag: uniqueTag,
                placeholderPoster: imageUrl,
              ).push<void>(context);
            },
          ),
        );
      },
    );
  }
}