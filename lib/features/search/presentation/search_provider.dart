import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:dio/dio.dart';
import '../../../../core/extensions/extension_manager.dart';
import '../../../../core/extensions/base_provider.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../explore/data/explore_tmdb_provider.dart';

part 'search_provider.g.dart';

enum SearchFilter { content, live }

class ProviderSearchResult {
  final String providerId;
  final String providerName;
  final List<MultimediaItem> results;
  final String? error;

  ProviderSearchResult({
    required this.providerId,
    required this.providerName,
    required this.results,
    this.error,
  });
}

class SearchAggregateState {
  final List<ProviderSearchResult> results;
  final bool isLoading;

  const SearchAggregateState({this.results = const [], this.isLoading = false});
}

class _FilterParams {
  final List<MultimediaItem> items;
  final List<String> queryParts;
  const _FilterParams(this.items, this.queryParts);
}

List<MultimediaItem> _filterItems(_FilterParams params) {
  return params.items.where((item) {
    final titleLower = item.title.toLowerCase();
    final titleParts = titleLower
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();
    for (final qPart in params.queryParts) {
      bool foundPrefix = false;
      for (final tPart in titleParts) {
        if (tPart.startsWith(qPart)) {
          foundPrefix = true;
          break;
        }
      }
      if (!foundPrefix) return false;
    }
    return true;
  }).toList();
}

Stream<SearchAggregateState> searchAllProviders(
  Ref ref,
  String query,
  ExtensionManager manager, {
  required SearchFilter filter,
  required bool Function() isCancelled,
}) async* {
  final allProviders = manager.getAllProviders();
  final providers = allProviders.where((p) {
    final isLiveOnly =
        p.supportedTypes.isNotEmpty &&
        p.supportedTypes.every((t) => t == ProviderType.livestream);
    return filter == SearchFilter.live ? isLiveOnly : !isLiveOnly;
  }).toList();

  if (query.isEmpty || providers.isEmpty) {
    yield const SearchAggregateState(results: [], isLoading: false);
    return;
  }

  yield const SearchAggregateState(results: [], isLoading: true);

  final results = <ProviderSearchResult>[];
  final queryLower = query.toLowerCase();
  final queryParts = queryLower.split(' ').where((s) => s.isNotEmpty).toList();

  final controller = StreamController<SearchAggregateState>();

  int getSemaphoreSize() {
    int maxSlots = 8;
    try {
      final cores = io.Platform.numberOfProcessors;
      if (io.Platform.isMacOS || io.Platform.isWindows || io.Platform.isLinux) {
        maxSlots = 32;
      } else {
        maxSlots = (cores).clamp(4, 8);
      }
    } catch (_) {}
    return maxSlots;
  }

  final maxSlots = getSemaphoreSize();
  int activeJobs = 0;

  final sortedProviders = List<SkyStreamProvider>.from(providers)
    ..sort((a, b) {
      final aLiveOnly =
          a.supportedTypes.isNotEmpty &&
          a.supportedTypes.every((t) => t == ProviderType.livestream);
      final bLiveOnly =
          b.supportedTypes.isNotEmpty &&
          b.supportedTypes.every((t) => t == ProviderType.livestream);
      if (aLiveOnly == bLiveOnly) return 0;
      return aLiveOnly ? 1 : -1;
    });
  final queue = List<SkyStreamProvider>.from(sortedProviders);
  final List<CancelToken> activeTokens = [];
  final List<SkyStreamProvider> activeProviders = [];
  bool isCompleted = false;

  Timer? throttleTimer;
  bool pendingEmit = false;
  int lastEmittedResultCount = 0;

  void doEmit({bool force = false}) {
    if (controller.isClosed || isCancelled()) {
      return;
    }
    final stillLoading = queue.isNotEmpty || activeJobs > 0;
    if (!force && stillLoading && results.length == lastEmittedResultCount) {
      pendingEmit = false;
      return;
    }
    lastEmittedResultCount = results.length;
    controller.add(
      SearchAggregateState(
        results: List.from(results),
        isLoading: stillLoading,
      ),
    );
    pendingEmit = false;
  }

  void scheduleEmit({bool force = false}) {
    if (isCancelled() || controller.isClosed) return;

    if (force) {
      throttleTimer?.cancel();
      throttleTimer = null;
      doEmit(force: true);
      return;
    }

    pendingEmit = true;
    final throttleDuration = (io.Platform.isAndroid || io.Platform.isIOS)
        ? const Duration(milliseconds: 500)
        : const Duration(milliseconds: 150);
    throttleTimer ??= Timer(throttleDuration, () {
      throttleTimer = null;
      if (pendingEmit) doEmit();
    });
  }

  void processNext() {
    if (isCancelled()) {
      for (final t in activeTokens) {
        if (!t.isCancelled) t.cancel('Search cancelled');
      }
      activeTokens.clear();
      for (final p in activeProviders) {
        p.cancelInit();
      }
      activeProviders.clear();
      return;
    }

    while (activeJobs < maxSlots && queue.isNotEmpty) {
      final provider = queue.removeAt(0);
      activeJobs++;
      final token = CancelToken();
      activeTokens.add(token);
      activeProviders.add(provider);

      Future(() async {
        if (isCancelled() || token.isCancelled) return;

        try {
          // 🎯 THE FIX: Force a 15-second timeout so dead servers don't permanently hog queue slots and freeze the app!
          final rawResults = await provider.search(query, cancelToken: token).timeout(const Duration(seconds: 15));
          if (isCancelled() || token.isCancelled) return;

          final providerItems = rawResults
              .map(
                (item) => MultimediaItem(
                  title: item.title,
                  url: item.url,
                  posterUrl: item.posterUrl,
                  bannerUrl: item.bannerUrl,
                  description: item.description,
                  contentType: item.contentType,
                  episodes: item.episodes,
                  provider: provider.packageName,
                ),
              )
              .toList();

          final filtered = providerItems.length < 30
              ? _filterItems(_FilterParams(providerItems, queryParts))
              : await compute(
                  _filterItems,
                  _FilterParams(providerItems, queryParts),
                );

          if (isCancelled() || token.isCancelled) return;

          if (filtered.isNotEmpty) {
            results.add(
              ProviderSearchResult(
                providerId: provider.packageName,
                providerName: provider.name,
                results: filtered,
              ),
            );
          }
        } on TimeoutException {
          // Gracefully drop dead servers
          if (kDebugMode) debugPrint('Provider ${provider.name} timed out after 15s.');
        } catch (e) {
          if (isCancelled() || token.isCancelled) return;
          if (e is DioException && e.type == DioExceptionType.cancel) return;
        } finally {
          activeJobs--;
          activeTokens.remove(token);
          activeProviders.remove(provider);

          final isLast = activeJobs == 0 && queue.isEmpty;
          scheduleEmit(force: isLast);

          if (isLast && !isCompleted) {
            isCompleted = true;
            manager.runGC();
            if (!controller.isClosed) {
              unawaited(
                Future.microtask(() {
                  if (!controller.isClosed) controller.close();
                }),
              );
            }
          } else if (!isCancelled()) {
            processNext();
          }
        }
      });
    }
  }

  processNext();

  yield* controller.stream;
}

@Riverpod(keepAlive: true)
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';

  void set(String query) => state = query;
}

@Riverpod(keepAlive: true)
class SearchFilterNotifier extends _$SearchFilterNotifier {
  @override
  SearchFilter build() => SearchFilter.content;

  void set(SearchFilter filter) => state = filter;
}

@Riverpod(keepAlive: true)
Stream<SearchAggregateState> searchResults(Ref ref) {
  final query = ref.watch(searchQueryProvider);
  final filter = ref.watch(searchFilterProvider);
  final manager = ref.read(extensionManagerProvider.notifier);

  var cancelled = false;
  ref.onDispose(() {
    cancelled = true;
  });

  return searchAllProviders(
    ref,
    query,
    manager,
    filter: filter,
    isCancelled: () => cancelled,
  );
}

class SearchSuggestionState {
  final List<MultimediaItem> suggestions;
  final bool isLoading;
  final String query;

  const SearchSuggestionState({
    this.suggestions = const [],
    this.isLoading = false,
    this.query = '',
  });

  SearchSuggestionState copyWith({
    List<MultimediaItem>? suggestions,
    bool? isLoading,
    String? query,
  }) {
    return SearchSuggestionState(
      suggestions: suggestions ?? this.suggestions,
      isLoading: isLoading ?? this.isLoading,
      query: query ?? this.query,
    );
  }
}

@riverpod
class SearchSuggestionController extends _$SearchSuggestionController {
  Timer? _debounce;

  @override
  SearchSuggestionState build() {
    ref.onDispose(() {
      _debounce?.cancel();
    });
    return const SearchSuggestionState();
  }

  void onQueryChanged(String query) {
    if (query == state.query) return;

    final trimmed = query.trim();
    if (trimmed.length < 2) {
      _debounce?.cancel();
      state = state.copyWith(
        query: query,
        suggestions: const [],
        isLoading: false,
      );
      return;
    }

    state = state.copyWith(query: query, isLoading: true);

    _debounce?.cancel();
    
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final tmdb = ref.read(tmdbServiceProvider);
        
        final results = await tmdb.multiSearch(
          query: trimmed,
          language: 'en-US',
        );
        
        if (state.query == query) {
          state = state.copyWith(suggestions: results.take(10).toList(), isLoading: false);
        }
      } catch (e, stack) {
        if (kDebugMode) debugPrint("TMDB Suggestion Error: $e\n$stack");
        if (state.query == query) {
          state = state.copyWith(suggestions: const [], isLoading: false);
        }
      }
    });
  }

  void clear() {
    _debounce?.cancel();
    state = const SearchSuggestionState();
  }
}