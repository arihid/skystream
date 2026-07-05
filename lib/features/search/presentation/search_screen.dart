import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gamepads/gamepads.dart';
import 'package:cached_network_image/cached_network_image.dart'; 
import '../../../core/utils/layout_constants.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../core/providers/device_info_provider.dart';
import 'search_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'widgets/search_result_section.dart';

import '../../../shared/widgets/virtual_keyboard.dart';
import '../../../core/input/gamepad_intents.dart';
import '../../../core/widgets/focusable_wrapper.dart';
import '../../../shared/widgets/gamepad_hints_overlay.dart';
import '../../../shared/widgets/shimmer_placeholder.dart';
import '../../../core/utils/image_fallbacks.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  final FocusNode _keyboardProxyNode = FocusNode(skipTraversal: true);
  final FocusNode _listProxyNode = FocusNode(skipTraversal: true);
  
  final GlobalKey<PopupMenuButtonState<SearchFilter>> _mobilePopupKey = GlobalKey();
  
  StreamSubscription<GamepadEvent>? _gamepadSubscription;
  DateTime _lastLTTime = DateTime.now();
  DateTime _lastRTTime = DateTime.now(); 
  
  bool _isKeyboardVisible = false;
  bool _isKeyboardActiveRegion = true; 
  bool _isFilterDialogOpen = false; 

  @override
  void initState() {
    super.initState();
    final initialQuery = ref.read(searchQueryProvider);
    _controller.text = initialQuery;
    
    if (initialQuery.isEmpty) {
      _isKeyboardVisible = true;
      _isKeyboardActiveRegion = true;
    }

    _focusNode.addListener(_onFocusChanged);
    _focusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        final suggestionState = ref.read(searchSuggestionControllerProvider);
        final typedLongEnough = suggestionState.query.trim().length >= 2;
        final hasSuggestionContent =
            suggestionState.isLoading || suggestionState.suggestions.isNotEmpty;

        if (typedLongEnough && hasSuggestionContent) {
          FocusManager.instance.primaryFocus?.focusInDirection(
            TraversalDirection.down,
          );
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };

    _gamepadSubscription = Gamepads.events.listen((event) {
      if (!mounted) return;
      if (!TickerMode.of(context)) return;

      try {
        final route = ModalRoute.of(context);
        // 🎯 THE FIX: If the dialog is open, the route is NOT current, but we must allow the event through
        // to catch the second RT press to close the dialog!
        if (route != null && !route.isCurrent && !_isFilterDialogOpen) return;
      } catch (_) {}

      final key = event.key.toLowerCase();
      final isLT = key == 'l2' || key == 'button 6' || (key.contains('trigger') && key.contains('left'));
      final isRT = key == 'r2' || key == 'button 7' || (key.contains('trigger') && key.contains('right'));
      
      if (isLT) {
        if ((event.type == KeyType.button && event.value == 1.0) ||
            (event.type == KeyType.analog && event.value > 0.5)) {
          if (DateTime.now().difference(_lastLTTime).inMilliseconds > 500) {
            _lastLTTime = DateTime.now();
            _toggleKeyboardAndList();
          }
        }
      } else if (isRT) {
        if ((event.type == KeyType.button && event.value == 1.0) ||
            (event.type == KeyType.analog && event.value > 0.5)) {
          if (DateTime.now().difference(_lastRTTime).inMilliseconds > 500) {
            _lastRTTime = DateTime.now();
            final profile = ref.read(deviceProfileProvider).asData?.value;
            final isTv = profile?.isTv == true || context.isTv;
            final isBigPicture = isTv || context.isDesktop;
            if (isBigPicture) _toggleFilterMenu();
          }
        }
      }
    });
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      if (!_isKeyboardVisible && mounted) {
        setState(() {
          _isKeyboardVisible = true;
          _isKeyboardActiveRegion = true;
        });
      }
    } else {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _gamepadSubscription?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    _keyboardProxyNode.dispose();
    _listProxyNode.dispose();
    super.dispose();
  }

  void _submitSearch(String val) {
    final trimmed = val.trim();
    _controller.value = TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
    ref.read(searchSuggestionControllerProvider.notifier).clear();
    ref.read(searchQueryProvider.notifier).set(trimmed);
    _focusNode.unfocus();
    
    if (mounted) {
      setState(() {
        _isKeyboardVisible = false;
      });
    }
  }

  void _fillSuggestion(String suggestion) {
    _controller.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
    ref
        .read(searchSuggestionControllerProvider.notifier)
        .onQueryChanged(suggestion);
        
    final profile = ref.read(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    final isDesktop = context.isDesktop;
    final isBigPicture = isTv || isDesktop;

    if (!isBigPicture) {
      _focusNode.requestFocus();
    } else {
      setState(() {
        _isKeyboardVisible = true;
        _isKeyboardActiveRegion = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _keyboardProxyNode.requestFocus();
        Future.microtask(() => FocusManager.instance.primaryFocus?.nextFocus());
      });
    }
  }

  void _toggleKeyboardAndList() {
    final profile = ref.read(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    final isDesktop = context.isDesktop;
    final isBigPicture = isTv || isDesktop;

    if (!isBigPicture) {
      _focusNode.requestFocus();
      return;
    }

    // Don't toggle the keyboard if the filter dialog is actively blocking the screen
    if (_isFilterDialogOpen) return;

    if (!_isKeyboardVisible) {
      setState(() {
        _isKeyboardVisible = true;
        _isKeyboardActiveRegion = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _keyboardProxyNode.requestFocus();
        Future.microtask(() => FocusManager.instance.primaryFocus?.nextFocus());
      });
      return;
    }

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

  // 🎯 THE FIX: Changed from show to toggle!
  void _toggleFilterMenu() {
    if (!mounted) return;

    // If the menu is already open, pressing RT or clicking it again destroys it!
    if (_isFilterDialogOpen) {
      Navigator.of(context, rootNavigator: true).pop();
      return; // The 'then' block below will cleanly handle resetting the state
    }
    
    _isFilterDialogOpen = true;

    final theme = Theme.of(context);
    final filter = ref.read(searchFilterProvider);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Scope'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Non Livestreams'),
              leading: const Text('🍿', style: TextStyle(fontSize: 24)),
              trailing: filter == SearchFilter.content ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
              onTap: () {
                ref.read(searchFilterProvider.notifier).set(SearchFilter.content);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Livestreams'),
              leading: const Text('📺', style: TextStyle(fontSize: 24)),
              trailing: filter == SearchFilter.live ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
              onTap: () {
                ref.read(searchFilterProvider.notifier).set(SearchFilter.live);
                Navigator.pop(context);
              },
            ),
          ],
        )
      )
    ).then((_) {
      if (mounted) {
        _isFilterDialogOpen = false;
      }
    });
  }

  Widget _buildMobileSearchField(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final searchResultsAsync = ref.watch(searchResultsProvider);

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, child) {
        final query = value.text;

        final isSearching = searchResultsAsync.maybeWhen(
          data: (state) => state.isLoading,
          loading: () => true,
          orElse: () => false,
        );

        Widget? suffix;
        if (isSearching) {
          suffix = Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          );
        } else if (query.isNotEmpty) {
          suffix = IconButton(
            icon: const Icon(Icons.clear, size: 18),
            onPressed: () {
              _controller.clear();
              ref.read(searchSuggestionControllerProvider.notifier).clear();
              ref.read(searchQueryProvider.notifier).set('');
            },
          );
        }

        return TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: false,
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurface,
          ),
          textAlignVertical: TextAlignVertical.center,
          textInputAction: TextInputAction.search,
          onChanged: (val) {
            ref.read(searchSuggestionControllerProvider.notifier).onQueryChanged(val);
          },
          onSubmitted: _submitSearch,
          decoration: InputDecoration(
            hintText: l10n.searchHint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LayoutConstants.radiusPill),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LayoutConstants.radiusPill),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LayoutConstants.radiusPill),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            hintStyle: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            prefixIcon: Icon(
              Icons.search,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 42,
            ),
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 42,
              minHeight: 42,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    final isDesktop = context.isDesktop;
    final isBigPicture = isTv || isDesktop;
    final isWidescreen = isTv || context.isTabletOrLarger;
    final theme = Theme.of(context);

    Widget content;

    if (isWidescreen) {
      content = Scaffold(
        extendBodyBehindAppBar: false,
        backgroundColor: Colors.transparent,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(LayoutConstants.dashboardContentPadding, 24, LayoutConstants.dashboardContentPadding, 8),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, child) {
                  return Row(
                    children: [
                      Icon(Icons.search, size: 28, color: theme.colorScheme.primary),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          value.text.isEmpty ? AppLocalizations.of(context)!.searchHint : value.text,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: value.text.isEmpty 
                                ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5) 
                                : theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      FocusableWrapper(
                        onTap: _toggleFilterMenu,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Text('RT', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 12)),
                              const SizedBox(width: 6),
                              Text('FILTER', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.0)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }
              ),
            ),
            Expanded(child: _buildBody(context, isBigPicture)),
          ],
        ),
      );
    } else {
      content = _buildMobileLayout(context, isBigPicture);
    }

    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.gameButtonLeft2) {
          _toggleKeyboardAndList();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          AppBackIntent: CallbackAction<AppBackIntent>(
            onInvoke: (_) {
              if (_isKeyboardVisible) {
                setState(() {
                  _isKeyboardVisible = false;
                });
                return null; 
              }

              final query = _controller.text;
              if (query.isNotEmpty) {
                setState(() {
                  _isKeyboardVisible = true;
                  _isKeyboardActiveRegion = true;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _keyboardProxyNode.requestFocus();
                  Future.microtask(() => FocusManager.instance.primaryFocus?.nextFocus());
                });
                return null;
              }

              Navigator.maybePop(context);
              return null;
            }
          ),
        },
        child: content,
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, bool isBigPicture) {
    final filter = ref.watch(searchFilterProvider);
    final theme = Theme.of(context);
    final isLive = filter == SearchFilter.live;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FocusableWrapper(
              onTap: () => _mobilePopupKey.currentState?.showButtonMenu(),
              child: PopupMenuButton<SearchFilter>(
                key: _mobilePopupKey,
                tooltip: 'Search scope',
                onSelected: (value) =>
                    ref.read(searchFilterProvider.notifier).set(value),
                offset: const Offset(0, 48),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: SearchFilter.content,
                    child: Row(
                      children: [
                        const Text('🍿', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('Non Livestreams')),
                        if (!isLive)
                          Icon(
                            Icons.check,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: SearchFilter.live,
                    child: Row(
                      children: [
                        const Text('📺', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('Livestreams')),
                        if (isLive)
                          Icon(
                            Icons.check,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    isLive ? '📺' : '🍿',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
          ),
        ],
        title: SizedBox(
          height: 42,
          child: ExcludeFocus(
            excluding: _isKeyboardVisible,
            child: _buildMobileSearchField(context),
          ),
        ),
      ),
      body: _buildBody(context, isBigPicture),
    );
  }

  Widget _buildBody(BuildContext context, bool isBigPicture) {
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final suggestionState = ref.watch(searchSuggestionControllerProvider);
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(searchQueryProvider);

    final typedLongEnough = suggestionState.query.trim().length >= 2;
    final hasSuggestionContent = suggestionState.isLoading || suggestionState.suggestions.isNotEmpty;
    
    final forceSuggestions = isBigPicture ? _isKeyboardVisible : _focusNode.hasFocus;
    final showSuggestions = forceSuggestions || (typedLongEnough && hasSuggestionContent);
    final shouldShowKeyboard = isBigPicture && (_isKeyboardVisible || query.isEmpty);

    Widget content = showSuggestions
        ? ExcludeFocus(
            excluding: _isKeyboardActiveRegion && shouldShowKeyboard,
            child: _buildSuggestionsView(context, suggestionState, shouldShowKeyboard),
          )
        : searchResultsAsync.when(
            data: (state) {
              final allResults = state.results
                  .expand((e) => e.results)
                  .toList();

              if (allResults.isEmpty && !state.isLoading) {
                return _buildEmptyState(context);
              } else if (allResults.isEmpty && state.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              return RepaintBoundary(
                child: ListView.builder(
                  cacheExtent: 99999, 
                  padding: const EdgeInsets.only(
                    bottom: LayoutConstants.spacingMd,
                  ),
                  itemCount: state.results.length,
                  itemBuilder: (context, index) {
                    final pResult = state.results[index];
                    return SearchResultSection(
                      key: ValueKey(pResult.providerId),
                      providerName: pResult.providerName,
                      providerId: pResult.providerId,
                      results: pResult.results,
                    );
                  },
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) =>
                Center(child: Text(l10n.errorPrefix(err.toString()))),
          );

    if (shouldShowKeyboard) {
      return Column(
        children: [
          Expanded(child: content),
          ExcludeFocus(
            excluding: !_isKeyboardActiveRegion,
            child: Focus(
              focusNode: _keyboardProxyNode,
              skipTraversal: true, 
              canRequestFocus: true,
              onFocusChange: (hasFocus) {
                if (hasFocus) {
                  Future.microtask(() {
                    if (mounted) {
                      ref.read(focusedGamepadHintsProvider.notifier).state = [
                        GamepadHint(buttonLabel: 'A', actionLabel: 'Type', buttonColor: Colors.greenAccent.shade400),
                        GamepadHint(buttonLabel: 'LT', actionLabel: 'List', buttonColor: Colors.grey.shade400),
                        GamepadHint(buttonLabel: 'RT', actionLabel: 'Filter', buttonColor: Colors.amberAccent.shade400),
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
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, child) {
                  return VirtualKeyboard(
                    query: value.text,
                    onQueryChanged: (val) {
                      _controller.value = TextEditingValue(
                        text: val,
                        selection: TextSelection.collapsed(offset: val.length),
                      );
                      ref.read(searchSuggestionControllerProvider.notifier).onQueryChanged(val);
                    },
                    onSearch: () {
                      _submitSearch(_controller.text);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    return content;
  }

  Widget _buildSuggestionsView(
    BuildContext context,
    SearchSuggestionState suggestionState,
    bool shouldShowKeyboard,
  ) {
    if (suggestionState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (suggestionState.suggestions.isEmpty) {
      if (ref.read(searchQueryProvider).isEmpty && _controller.text.isEmpty) {
        return _buildEmptyState(context);
      }
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final toggleHint = GamepadHint(buttonLabel: 'LT', actionLabel: 'Keyboard', buttonColor: Colors.grey.shade400);
    final filterHint = GamepadHint(buttonLabel: 'RT', actionLabel: 'Filter', buttonColor: Colors.amberAccent.shade400);

    return Focus(
      focusNode: _listProxyNode,
      skipTraversal: true,
      child: ListView.builder(
        cacheExtent: 99999, 
        itemCount: suggestionState.suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = suggestionState.suggestions[index];
          final title = suggestion.title;
          final year = suggestion.releaseDate.isNotEmpty ? suggestion.releaseDate.split('-').first : '';
          final mediaType = suggestion.tmdbMediaType;
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Material(
              type: MaterialType.transparency,
              child: FocusableWrapper(
                useScaleEffect: false, 
                gamepadHints: [
                  GamepadHint(buttonLabel: 'A', actionLabel: 'Search', buttonColor: Colors.greenAccent.shade400),
                  if (shouldShowKeyboard) toggleHint,
                  filterHint,
                ],
                onTap: () => _submitSearch(title),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: AppImageFallbacks.poster(suggestion.posterUrl, label: title) ?? '',
                      width: 40,
                      height: 60,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => ShimmerPlaceholder(borderRadius: 4),
                      errorWidget: (_, _, _) => Container(
                        width: 40, height: 60,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.movie_creation_outlined),
                      ),
                    ),
                  ),
                  title: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  subtitle: Text(
                    '${mediaType.toUpperCase()} ${year.isNotEmpty ? '($year)' : ''}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Fill query',
                    icon: const Icon(Icons.north_west_rounded),
                    focusNode: FocusNode(
                      canRequestFocus: false,
                    ), 
                    onPressed: () => _fillSuggestion(title),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie_filter_rounded,
            size: 64,
            color: Theme.of(context).dividerColor,
          ),
          const SizedBox(height: LayoutConstants.spacingMd),
          Text(
            l10n.searchFavoriteContent,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.pressSearchOrEnter,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}