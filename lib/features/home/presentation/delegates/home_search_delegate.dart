import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/input/gamepad_actions.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/extensions/extension_manager.dart';
import '../../../../core/extensions/base_provider.dart';
import '../../../../core/utils/image_fallbacks.dart';
import '../../../search/presentation/search_provider.dart';
import 'package:skystream/shared/widgets/multimedia_card.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../core/utils/responsive_breakpoints.dart';

import '../../../../shared/widgets/virtual_keyboard.dart';
import '../../../../core/input/gamepad_intents.dart';
import '../../../../core/widgets/focusable_wrapper.dart';
import '../../../../shared/widgets/gamepad_hints_overlay.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../l10n/generated/app_localizations.dart';

// Master Switch Imports
import '../../../../core/providers/device_info_provider.dart';
import '../../../../features/settings/presentation/big_picture_provider.dart';

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

  bool _isBigPicture(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    final isTv =
        container.read(deviceProfileProvider).asData?.value.isTv ?? false;
    return container.read(bigPictureModeProvider).isEnabled || isTv;
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    final isBigPicture = _isBigPicture(context);

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
      textTheme: theme.textTheme.copyWith(
        titleMedium: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 18,
        ),
      ),
    );
  }

  Widget _buildFakeHeader(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LayoutConstants.dashboardContentPadding,
        24,
        LayoutConstants.dashboardContentPadding,
        8,
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 28, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              query.isEmpty ? l10n.search : query,
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
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
      const SizedBox(width: 8),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.isEmpty) return const SizedBox.shrink();

    final isBigPicture = _isBigPicture(context);
    final Widget content = _HomeSearchResults(
      query: query,
      onBack: () => showSuggestions(context),
    );

    if (isBigPicture) {
      return Actions(
        actions: <Type, Action<Intent>>{
          AppBackIntent: CallbackAction<AppBackIntent>(
            onInvoke: (_) {
              showSuggestions(context);
              return null;
            },
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
    final isBigPicture = _isBigPicture(context);

    if (isBigPicture) {
      return _HomeSearchKeyboardAndList(
        initialQuery: query,
        fakeHeader: _buildFakeHeader(context),
        onQueryChanged: (val) {
          query = val;
        },
        onSelect: (val) {
          query = val;
          FocusManager.instance.primaryFocus?.unfocus();
          showResults(context);
        },
        onSearch: () {
          if (query.isNotEmpty) {
            FocusManager.instance.primaryFocus?.unfocus();
            showResults(context);
          }
        },
      );
    }

    if (query.isEmpty) return const SizedBox.shrink();
    return _HomeSearchSuggestions(
      query: query,
      onSelect: (val) {
        query = val;
        showResults(context);
      },
    );
  }
}

class _HomeSearchKeyboardAndList extends ConsumerStatefulWidget {
  final String initialQuery;
  final Widget fakeHeader;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSelect;
  final VoidCallback onSearch;

  const _HomeSearchKeyboardAndList({
    required this.initialQuery,
    required this.fakeHeader,
    required this.onQueryChanged,
    required this.onSelect,
    required this.onSearch,
  });

  @override
  ConsumerState<_HomeSearchKeyboardAndList> createState() =>
      _HomeSearchKeyboardAndListState();
}

class _HomeSearchKeyboardAndListState
    extends ConsumerState<_HomeSearchKeyboardAndList> {
  final FocusNode _keyboardProxyNode = FocusNode(skipTraversal: true);
  final FocusNode _listProxyNode = FocusNode(skipTraversal: true);
  DateTime _lastLTTime = DateTime.now();
  bool _isKeyboardActiveRegion = true;

  @override
  void initState() {
    super.initState();
    _isKeyboardActiveRegion = widget.initialQuery.isEmpty;
  }

  void _toggleKeyboardAndList() {
    final isTv = ref.read(deviceProfileProvider).asData?.value.isTv ?? false;
    final isBigPicture = ref.read(bigPictureModeProvider).isEnabled || isTv;

    if (!isBigPicture) return;

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
    _keyboardProxyNode.dispose();
    _listProxyNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTv = ref.watch(deviceProfileProvider).asData?.value.isTv ?? false;
    final isBigPicture = ref.watch(bigPictureModeProvider).isEnabled || isTv;
    final l10n = AppLocalizations.of(context)!;

    return Actions(
      actions: <Type, Action<Intent>>{
        AppBackIntent: CallbackAction<AppBackIntent>(
          onInvoke: (_) {
            Navigator.maybePop(context);
            return null;
          },
        ),
        AppLeftTriggerIntent: CallbackAction<AppLeftTriggerIntent>(
          onInvoke: (_) {
            // Debounce to prevent analog trigger spam
            if (DateTime.now().difference(_lastLTTime).inMilliseconds > 500) {
              _lastLTTime = DateTime.now();
              _toggleKeyboardAndList();
            }
            return null;
          },
        ),
      },
      child: Column(
        children: [
          widget.fakeHeader,
          Expanded(
            child: ExcludeFocus(
              excluding: isBigPicture && _isKeyboardActiveRegion,
              child: Focus(
                focusNode: _listProxyNode,
                skipTraversal: true,
                child: widget.initialQuery.isEmpty
                    ? Center(
                        child: Text(
                          l10n.searchSubtitleNameHint,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.5),
                            fontSize: 18,
                          ),
                        ),
                      )
                    : _HomeSearchSuggestions(
                        query: widget.initialQuery,
                        onSelect: widget.onSelect,
                        isKeyboardActiveRegion: _isKeyboardActiveRegion,
                      ),
              ),
            ),
          ),
          if (isBigPicture)
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
                          GamepadHint(
                            buttonLabel: 'A',
                            actionLabel: l10n.hintType,
                            buttonColor: Colors.greenAccent.shade400,
                          ),
                          GamepadHint(
                            buttonLabel: 'LT',
                            actionLabel: l10n.hintList,
                            buttonColor: Colors.grey.shade400,
                          ),
                        ];
                      }
                    });
                  } else {
                    Future.microtask(() {
                      if (mounted) {
                        final currentHints = ref.read(
                          focusedGamepadHintsProvider,
                        );
                        if (currentHints?.any(
                              (h) => h.actionLabel == l10n.hintType,
                            ) ==
                            true) {
                          ref.read(focusedGamepadHintsProvider.notifier).state =
                              null;
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

class _HomeSearchSuggestions extends ConsumerStatefulWidget {
  final String query;
  final void Function(String) onSelect;
  final bool isKeyboardActiveRegion;

  const _HomeSearchSuggestions({
    required this.query,
    required this.onSelect,
    this.isKeyboardActiveRegion = false,
  });

  @override
  ConsumerState<_HomeSearchSuggestions> createState() =>
      _HomeSearchSuggestionsState();
}

class _HomeSearchSuggestionsState
    extends ConsumerState<_HomeSearchSuggestions> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(searchSuggestionControllerProvider.notifier)
          .onQueryChanged(widget.query);
    });
  }

  @override
  void didUpdateWidget(covariant _HomeSearchSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      Future.microtask(() {
        if (!context.mounted) return;
        ref
            .read(searchSuggestionControllerProvider.notifier)
            .onQueryChanged(widget.query);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchSuggestionControllerProvider);
    final isLoading = searchState.isLoading;
    final suggestions = searchState.suggestions;
    final l10n = AppLocalizations.of(context)!;

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
          l10n.noResultsFound,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    final isTv = ref.watch(deviceProfileProvider).asData?.value.isTv ?? false;
    final isBigPicture = ref.watch(bigPictureModeProvider).isEnabled || isTv;

    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = suggestions[index];
        final tile = ListTile(
          leading: const Icon(Icons.search_rounded),
          title: Text(suggestion),
          trailing: IconButton(
            tooltip: 'Fill query',
            icon: const Icon(Icons.north_west_rounded),
            focusNode: FocusNode(canRequestFocus: false),
            onPressed: () {
              widget.onSelect(suggestion);
            },
          ),
          onTap: () => widget.onSelect(suggestion),
        );

        if (isBigPicture) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Material(
              type: MaterialType.transparency,
              child: FocusableWrapper(
                useScaleEffect: false,
                gamepadHints: [
                  GamepadHint(
                    buttonLabel: 'A',
                    actionLabel: l10n.hintSearch,
                    buttonColor: Colors.greenAccent.shade400,
                  ),
                  GamepadHint(
                    buttonLabel: 'LT',
                    actionLabel: widget.isKeyboardActiveRegion
                        ? l10n.hintList
                        : l10n.hintKeyboard,
                    buttonColor: Colors.grey.shade400,
                  ),
                ],
                onTap: () => widget.onSelect(suggestion),
                child: tile,
              ),
            ),
          );
        }

        return Material(type: MaterialType.transparency, child: tile);
      },
    );
  }
}

class _HomeSearchResults extends ConsumerStatefulWidget {
  final String query;
  final VoidCallback? onBack;

  const _HomeSearchResults({required this.query, this.onBack});

  @override
  ConsumerState<_HomeSearchResults> createState() => _HomeSearchResultsState();
}

class _HomeSearchResultsState extends ConsumerState<_HomeSearchResults> {
  bool isLoading = true;
  ProviderSearchResult? result;
  DateTime _lastLTTime = DateTime.now();

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
    final l10n = AppLocalizations.of(context)!;

    if (isLoading) {
      return const Center(child: AppLoadingIndicator());
    }

    if (result == null || result!.results.isEmpty) {
      final profile = ref.watch(deviceProfileProvider).asData?.value;
      final isTv = profile?.isTv == true || context.isTv;
      final isWidescreen = isTv || context.isTabletOrLarger;
      final imageWidth = isWidescreen ? 320.0 : 200.0;
      final nativeFont = Theme.of(context).textTheme.bodyLarge?.fontFamily;

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.noResultsFound,
              style: TextStyle(
                fontFamily: nativeFont,
                fontSize: 16.0,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    }

    final isLarge = MediaQuery.of(context).size.width > 600;
    final maxExtent = isLarge ? 200.0 : 130.0;
    final isTv = ref.watch(deviceProfileProvider).asData?.value.isTv ?? false;
    final isBigPicture = ref.watch(bigPictureModeProvider).isEnabled || isTv;

    final Widget content = GridView.builder(
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

        if (isBigPicture) {
          return FocusableWrapper(
            autofocus: index == 0,
            gamepadHints: [
              GamepadHint(
                buttonLabel: 'A',
                actionLabel: l10n.hintView,
                buttonColor: Colors.greenAccent.shade400,
              ),
              GamepadHint(
                buttonLabel: 'LT',
                actionLabel: l10n.hintSearchField,
                buttonColor: Colors.grey.shade400,
              ),
            ],
            onTap: () => DetailsRoute(
              $extra: DetailsRouteExtra(item: item),
            ).push<void>(context),
            child: MultimediaCard(
              key: ValueKey(item.url),
              imageUrl: AppImageFallbacks.poster(
                item.posterUrl,
                label: item.title,
              ),
              title: item.title,
              heroTag: uniqueTag,
              onTap: () => DetailsRoute(
                $extra: DetailsRouteExtra(item: item),
              ).push<void>(context),
            ),
          );
        }

        return MultimediaCard(
          key: ValueKey(item.url),
          imageUrl: AppImageFallbacks.poster(item.posterUrl, label: item.title),
          title: item.title,
          heroTag: uniqueTag,
          onTap: () => DetailsRoute(
            $extra: DetailsRouteExtra(item: item),
          ).push<void>(context),
        );
      },
    );

    return Actions(
      actions: <Type, Action<Intent>>{
        AppBackIntent: CallbackAction<AppBackIntent>(
          onInvoke: (_) {
            if (widget.onBack != null) widget.onBack!();
            return null;
          },
        ),
        AppLeftTriggerIntent: CallbackAction<AppLeftTriggerIntent>(
          onInvoke: (_) {
            // Debounce to prevent analog trigger spam
            if (DateTime.now().difference(_lastLTTime).inMilliseconds > 500) {
              _lastLTTime = DateTime.now();
              if (widget.onBack != null) widget.onBack!();
            }
            return null;
          },
        ),
      },
      child: content,
    );
  }
}
