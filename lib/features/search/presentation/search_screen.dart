import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gamepads/gamepads.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../core/utils/responsive_breakpoints.dart';
import '../../../core/providers/device_info_provider.dart';
import 'search_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'widgets/search_result_section.dart';
import 'widgets/search_header_bar.dart';
import 'widgets/bouncy_entry_animation.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/virtual_keyboard.dart';
import '../../../core/input/gamepad_intents.dart';
import '../../../core/widgets/focusable_wrapper.dart';
import '../../../shared/widgets/gamepad_hints_overlay.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _clearButtonFocusNode = FocusNode();
  final FocusNode _moviesShowsFocusNode = FocusNode();
  final FocusNode _liveTvFocusNode = FocusNode();
  final FocusNode _firstSuggestionFocusNode = FocusNode();
  final FocusNode _firstResultFocusNode = FocusNode();

  final FocusNode _keyboardProxyNode = FocusNode(skipTraversal: true);
  final FocusNode _listProxyNode = FocusNode(skipTraversal: true);
  
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
    _controller.addListener(_onTextChanged);

    if (initialQuery.isEmpty) {
      _isKeyboardVisible = true;
      _isKeyboardActiveRegion = true;
    }

    _focusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (_controller.text.isNotEmpty &&
              _controller.selection.extentOffset == _controller.text.length) {
            _clearButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          final filter = ref.read(searchFilterProvider);
          if (filter == SearchFilter.live) {
            _liveTvFocusNode.requestFocus();
          } else {
            _moviesShowsFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };

    _clearButtonFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _focusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          final filter = ref.read(searchFilterProvider);
          if (filter == SearchFilter.live) {
            _liveTvFocusNode.requestFocus();
          } else {
            _moviesShowsFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };

    _moviesShowsFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _focusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _liveTvFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          final suggestionState = ref.read(searchSuggestionControllerProvider);
          final typedLongEnough = suggestionState.query.trim().length >= 2;
          final hasSuggestionContent =
              suggestionState.isLoading ||
              suggestionState.suggestions.isNotEmpty;

          if (typedLongEnough && hasSuggestionContent) {
            _firstSuggestionFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else {
            final resultsState = ref.read(searchResultsProvider).asData?.value;
            final hasResults =
                resultsState != null &&
                resultsState.results.any((r) => r.results.isNotEmpty);
            if (hasResults) {
              _firstResultFocusNode.requestFocus();
              return KeyEventResult.handled;
            }
          }
        }
      }
      return KeyEventResult.ignored;
    };

    _liveTvFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _focusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _moviesShowsFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          final suggestionState = ref.read(searchSuggestionControllerProvider);
          final typedLongEnough = suggestionState.query.trim().length >= 2;
          final hasSuggestionContent =
              suggestionState.isLoading ||
              suggestionState.suggestions.isNotEmpty;

          if (typedLongEnough && hasSuggestionContent) {
            _firstSuggestionFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else {
            final resultsState = ref.read(searchResultsProvider).asData?.value;
            final hasResults =
                resultsState != null &&
                resultsState.results.any((r) => r.results.isNotEmpty);
            if (hasResults) {
              _firstResultFocusNode.requestFocus();
              return KeyEventResult.handled;
            }
          }
        }
      }
      return KeyEventResult.ignored;
    };

    _firstResultFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowUp) {
        final filter = ref.read(searchFilterProvider);
        if (filter == SearchFilter.live) {
          _liveTvFocusNode.requestFocus();
        } else {
          _moviesShowsFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    _gamepadSubscription = Gamepads.events.listen((event) {
      if (!mounted) return;
      if (!TickerMode.of(context)) return;

      try {
        final route = ModalRoute.of(context);
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

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _gamepadSubscription?.cancel();
    _keyboardProxyNode.dispose();
    _listProxyNode.dispose();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _clearButtonFocusNode.dispose();
    _moviesShowsFocusNode.dispose();
    _liveTvFocusNode.dispose();
    _firstSuggestionFocusNode.dispose();
    _firstResultFocusNode.dispose();
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

  void _toggleFilterMenu() {
    if (!mounted) return;

    if (_isFilterDialogOpen) {
      Navigator.of(context, rootNavigator: true).pop();
      return; 
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

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    final isWidescreen = isTv || context.isTabletOrLarger;
    final isBigPicture = isTv || context.isDesktop;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget content;

    if (isWidescreen) {
      content = Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Stack(
          children: [
            if (isDark)
              Positioned.fill(
                child: Image.asset(
                  'assets/images/search_background.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            if (isDark)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7), 
                  ),
                ),
              ),
            if (isDark)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.1,
                      colors: [
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.85),
                        Colors.black.withValues(alpha: 0.98),
                      ],
                      stops: const [0.0, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
            if (isDark)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 320, 
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          theme.scaffoldBackgroundColor,
                          theme.scaffoldBackgroundColor.withValues(alpha: 0.85),
                          theme.scaffoldBackgroundColor.withValues(alpha: 0.50),
                          theme.scaffoldBackgroundColor.withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.25, 0.55, 0.8, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            if (isDark)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          theme.scaffoldBackgroundColor,
                          theme.scaffoldBackgroundColor.withValues(alpha: 0.8),
                          Colors.transparent,
                          Colors.transparent,
                          theme.scaffoldBackgroundColor.withValues(alpha: 0.8),
                          theme.scaffoldBackgroundColor,
                        ],
                        stops: const [0.0, 0.08, 0.2, 0.8, 0.92, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 76, 
              left: 0,
              right: 0,
              height: 250,
              child: ListenableBuilder(
                listenable: _focusNode,
                builder: (context, child) {
                  if (!_focusNode.hasFocus) return const SizedBox.shrink();
                  final spotlightColor = isDark
                      ? const Color(0xFF1E40AF)
                      : theme.colorScheme.primary;
                  return IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 900, 
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.topCenter, 
                            radius: 1.3,
                            colors: [
                              spotlightColor.withValues(alpha: isDark ? 0.35 : 0.22), 
                              spotlightColor.withValues(alpha: isDark ? 0.18 : 0.10), 
                              spotlightColor.withValues(alpha: isDark ? 0.06 : 0.03), 
                              spotlightColor.withValues(alpha: 0.0), 
                            ],
                            stops: const [0.0, 0.35, 0.70, 1.0],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned.fill(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  SearchHeaderBar(
                    textController: _controller,
                    searchFocusNode: _focusNode,
                    clearButtonFocusNode: _clearButtonFocusNode,
                    moviesShowsFocusNode: _moviesShowsFocusNode,
                    liveTvFocusNode: _liveTvFocusNode,
                    isCompact: false,
                    isBigPicture: isBigPicture,
                    onTapFakeInput: () {
                      _isKeyboardVisible = true;
                      _isKeyboardActiveRegion = true;
                      setState(() {});
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _keyboardProxyNode.requestFocus();
                      });
                    },
                    onSubmitted: _submitSearch,
                    onChanged: (val) {
                      ref
                          .read(searchSuggestionControllerProvider.notifier)
                          .onQueryChanged(val);
                    },
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24.0),
                      child: _buildBody(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      content = _buildMobileLayout(context);
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

  Widget _buildMobileLayout(BuildContext context) {
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final filter = ref.watch(searchFilterProvider);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isLive = filter == SearchFilter.live;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: PopupMenuButton<SearchFilter>(
              tooltip: 'Search scope',
              onSelected: (value) {
                ref.read(searchFilterProvider.notifier).set(value);
                final text = _controller.text.trim();
                ref.read(searchQueryProvider.notifier).set(text);
              },
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
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: Center(child: Text('📺', style: const TextStyle(fontSize: 14))),
                      ),
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
                child: isLive
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: Center(child: Text('📺', style: TextStyle(fontSize: 14))),
                      )
                    : const Text('🍿', style: TextStyle(fontSize: 18)),
              ),
            ),
          ),
        ],
        title: GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 42,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) {
                final isSearching = searchResultsAsync.maybeWhen(
                  data: (state) => state.isLoading,
                  loading: () => true,
                  orElse: () => false,
                );

                Widget? suffix;
                if (isSearching) {
                  suffix = Padding(
                    padding: const EdgeInsets.all(12),
                    child: AppLoadingIndicator(
                      color: theme.colorScheme.primary,
                      constraints: BoxConstraints.tight(const Size(18, 18)),
                    ),
                  );
                } else if (value.text.isNotEmpty) {
                  suffix = IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(32, 32),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      _controller.clear();
                      ref
                          .read(searchSuggestionControllerProvider.notifier)
                          .clear();
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
                    ref
                        .read(searchSuggestionControllerProvider.notifier)
                        .onQueryChanged(val);
                  },
                  onSubmitted: _submitSearch,
                  decoration: InputDecoration(
                    hintText: l10n.searchHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        LayoutConstants.radiusPill,
                      ),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        LayoutConstants.radiusPill,
                      ),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        LayoutConstants.radiusPill,
                      ),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
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
            ),
          ),
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final suggestionState = ref.watch(searchSuggestionControllerProvider);
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(searchQueryProvider);

    final typedLongEnough = suggestionState.query.trim().length >= 2;
    final hasSuggestionContent =
        suggestionState.isLoading || suggestionState.suggestions.isNotEmpty;
        
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    final isDesktop = context.isDesktop;
    final isBigPicture = isTv || isDesktop;

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
                return  Center(child: AppLoadingIndicator());
              }

              return RepaintBoundary(
                child: ExcludeFocus(
                  excluding: _isKeyboardActiveRegion && shouldShowKeyboard,
                  child: Focus(
                    focusNode: _listProxyNode,
                    skipTraversal: true,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(
                        bottom: 100,
                      ),
                      itemCount: state.results.length,
                      itemBuilder: (context, index) {
                        final pResult = state.results[index];
                        return SearchResultSection(
                          key: ValueKey(pResult.providerId),
                          providerName: pResult.providerName,
                          providerId: pResult.providerId,
                          results: pResult.results,
                          firstCardFocusNode: index == 0
                              ? _firstResultFocusNode
                              : null,
                        );
                      },
                    ),
                  ),
                ),
              );
            },
            loading: () => const Center(child: AppLoadingIndicator()),
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
      return const Center(child: AppLoadingIndicator());
    }

    if (suggestionState.suggestions.isEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: suggestionState.suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = suggestionState.suggestions[index];
        return BouncyEntryAnimation(
          delay: Duration(milliseconds: index * 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: _SuggestionCard(
              suggestion: suggestion,
              shouldShowKeyboard: shouldShowKeyboard,
              focusNode: index == 0 ? _firstSuggestionFocusNode : null,
              isFirst: index == 0,
              onFocusSearch: () {
                final filter = ref.read(searchFilterProvider);
                if (filter == SearchFilter.live) {
                  _liveTvFocusNode.requestFocus();
                } else {
                  _moviesShowsFocusNode.requestFocus();
                }
              },
              onTap: () => _submitSearch(suggestion),
              onFill: () => _fillSuggestion(suggestion),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(searchQueryProvider);
    final isInputEmpty = _controller.text.trim().isEmpty;

    if (query.isEmpty || isInputEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_filter_rounded,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
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
    final nativeFont = Theme.of(context).textTheme.bodyLarge?.fontFamily;
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isTv = profile?.isTv == true || context.isTv;
    final isWidescreen = isTv || context.isTabletOrLarger;
    final imageWidth = isWidescreen ? 320.0 : 200.0;

    return Center(
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
}

class _SuggestionCard extends StatelessWidget {
  final String suggestion;
  final VoidCallback onTap;
  final VoidCallback onFill;
  final FocusNode? focusNode;
  final bool isFirst;
  final bool shouldShowKeyboard;
  final VoidCallback onFocusSearch;

  const _SuggestionCard({
    required this.suggestion,
    required this.onTap,
    required this.onFill,
    required this.isFirst,
    required this.shouldShowKeyboard,
    required this.onFocusSearch,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final nativeFont = theme.textTheme.bodyLarge?.fontFamily;

    return FocusableWrapper(
      focusNode: focusNode,
      onTap: onTap,           // 'A' to Search!
      onSecondaryTap: onFill, // 'X' to Fill Query!
      gamepadHints: [
        GamepadHint(buttonLabel: 'A', actionLabel: 'Search', buttonColor: Colors.greenAccent.shade400),
        GamepadHint(buttonLabel: 'X', actionLabel: 'Fill Query', buttonColor: Colors.blueAccent.shade400),
        if (shouldShowKeyboard)
          GamepadHint(buttonLabel: 'LT', actionLabel: 'Keyboard', buttonColor: Colors.grey.shade400),
      ],
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withValues(alpha: 0.65)
              : theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : theme.colorScheme.outlineVariant,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        suggestion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: nativeFont,
                          color: theme.colorScheme.onSurface,
                          fontSize: 16.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(width: 1.0, height: 24.0, color: theme.dividerColor.withValues(alpha: 0.2)),
            ExcludeFocus(
              child: IconButton(
                icon: const Icon(Icons.north_west_rounded, size: 20),
                color: theme.colorScheme.onSurfaceVariant,
                onPressed: onFill,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

