import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/extensions/extension_manager.dart';
import '../../../../core/extensions/base_provider.dart';
import '../../../../core/utils/image_fallbacks.dart';
import '../../../search/presentation/search_provider.dart';
import 'package:skystream/shared/widgets/multimedia_card.dart';
import 'package:skystream/shared/widgets/virtual_keyboard.dart';
import '../../../../core/widgets/focusable_wrapper.dart';
import '../../../../core/input/gamepad_intents.dart'; 
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../core/providers/device_info_provider.dart';
import '../../../../core/utils/responsive_breakpoints.dart';

class HomeSearchDelegate extends SearchDelegate<void> {
  final String? initialQuery;

  HomeSearchDelegate({this.initialQuery})
    : super(
        searchFieldLabel: 'Search movies, series...',
        searchFieldStyle: null,
      ) {
    if (initialQuery != null) {
      query = initialQuery!;
    }
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
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
      textTheme: theme.textTheme.copyWith(
        titleMedium: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 18,
        ),
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
    return _HomeSearchResults(
      query: query,
      onBack: () => showSuggestions(context), 
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
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
          Expanded(
            child: query.isEmpty
                ? Center(
                    child: Text(
                      'Type to search...',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        fontSize: 18,
                      ),
                    ),
                  )
                : _HomeSearchSuggestions(
                    query: query,
                    onSelect: (val) {
                      query = val;
                      FocusManager.instance.primaryFocus?.unfocus();
                      showResults(context);
                    },
                  ),
          ),
          VirtualKeyboard(
            query: query,
            onQueryChanged: (newQuery) {
              query = newQuery; 
            },
            onSearch: () {
              if (query.isNotEmpty) {
                FocusManager.instance.primaryFocus?.unfocus();
                showResults(context); 
              }
            },
          ),
        ],
      ),
    );
  }
}

class _HomeSearchSuggestions extends ConsumerStatefulWidget {
  final String query;
  final void Function(String) onSelect;

  const _HomeSearchSuggestions({required this.query, required this.onSelect});

  @override
  ConsumerState<_HomeSearchSuggestions> createState() =>
      _HomeSearchSuggestionsState();
}

class _HomeSearchSuggestionsState extends ConsumerState<_HomeSearchSuggestions> {
  
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(searchSuggestionControllerProvider.notifier).onQueryChanged(widget.query);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _HomeSearchSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      Future.microtask(() {
        if (mounted) {
          ref.read(searchSuggestionControllerProvider.notifier).onQueryChanged(widget.query);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🎯 Unconditional ref.watch ensures Riverpod keeps the state alive
    final searchState = ref.watch(searchSuggestionControllerProvider);
    final isLoading = searchState.isLoading;
    final suggestions = searchState.suggestions;

    if (widget.query.trim().length < 2) {
      return Center(
        child: Text(
          'Keep typing...',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    if (isLoading) {
      return Center(
        child: AppLoadingIndicator(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
        ),
      );
    }

    if (suggestions.isEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = suggestions[index];
        return Material(
          type: MaterialType.transparency,
          child: ListTile(
            leading: const Icon(Icons.search_rounded),
            title: Text(suggestion),
            trailing: IconButton(
              tooltip: 'Fill query',
              icon: const Icon(Icons.north_west_rounded),
              onPressed: () {
                widget.onSelect(suggestion);
              },
            ),
            onTap: () => widget.onSelect(suggestion),
          ),
        );
      },
    );
  }
}

class _HomeSearchResults extends ConsumerStatefulWidget {
  final String query;
  final VoidCallback onBack; 

  const _HomeSearchResults({required this.query, required this.onBack});

  @override
  ConsumerState<_HomeSearchResults> createState() => _HomeSearchResultsState();
}

class _HomeSearchResultsState extends ConsumerState<_HomeSearchResults> {
  bool isLoading = true;
  ProviderSearchResult? result;

  @override
  void initState() {
    super.initState();
    _performSearch();
  }

  @override
  void didUpdateWidget(covariant _HomeSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _performSearch();
    }
  }

  Future<void> _performSearch() async {
    setState(() {
      isLoading = true;
      result = null;
    });

    final SkyStreamProvider? provider = ref.read(activeProviderProvider);
    if (provider == null) {
      if (mounted) setState(() => isLoading = false);
      return;
    }

    try {
      final rawResults = await provider.search(widget.query);
      if (mounted) {
        setState(() {
          isLoading = false;
          result = ProviderSearchResult(
            providerId: provider.packageName,
            providerName: provider.name,
            results: rawResults.toList(),
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (isLoading) {
      content = const Focus(
        autofocus: true,
        child: Center(child: AppLoadingIndicator()),
      );
    } else if (result == null || result!.results.isEmpty) {
      final profile = ref.watch(deviceProfileProvider).asData?.value;
      final isTv = profile?.isTv == true || context.isTv;
      final isWidescreen = isTv || context.isTabletOrLarger;
      final imageWidth = isWidescreen ? 320.0 : 200.0;
      final nativeFont = Theme.of(context).textTheme.bodyLarge?.fontFamily;

      content = Focus(
        autofocus: true,
        child: Center(
          child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'No Results Found',
                style: TextStyle(
                  fontFamily: nativeFont,
                fontSize: 16.0,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
              ),
            ),
            const SizedBox(height: 16),
            Image.asset(
              'assets/images/no_results.png',
              fit: BoxFit.contain,
              width: imageWidth,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ],
        ),
      );
    } else {
      final isLarge = MediaQuery.of(context).size.width > 600;
      final maxExtent = isLarge ? 200.0 : 130.0;

      content = GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxExtent,
          childAspectRatio: 2 / 3.2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
        itemCount: result!.results.length,
        itemBuilder: (context, index) {
          final item = result!.results[index];
          final uniqueTag = 'search_${result!.providerId}_${item.url}_$index';

          return FocusableWrapper(
            autofocus: index == 0,
            onTap: () => DetailsRoute(
              $extra: DetailsRouteExtra(item: item),
            ).push<void>(context),
            child: MultimediaCard(
              key: ValueKey(item.url),
              imageUrl: AppImageFallbacks.poster(item.posterUrl, label: item.title),
              title: item.title,
              heroTag: uniqueTag,
              onTap: () => DetailsRoute(
                $extra: DetailsRouteExtra(item: item),
              ).push<void>(context),
            ),
          );
        },
      );
    }

    return Actions(
      actions: <Type, Action<Intent>>{
        AppBackIntent: CallbackAction<AppBackIntent>(
          onInvoke: (_) {
            widget.onBack(); 
            return null;
          }
        ),
      },
      child: content,
    );
  }
}