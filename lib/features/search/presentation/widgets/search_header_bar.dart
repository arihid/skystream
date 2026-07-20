import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/utils/layout_constants.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import '../search_provider.dart';

import '../../../../core/widgets/focusable_wrapper.dart';

class SearchHeaderBar extends ConsumerStatefulWidget {
  final TextEditingController textController;
  final FocusNode searchFocusNode;
  final FocusNode clearButtonFocusNode;
  final FocusNode moviesShowsFocusNode;
  final FocusNode liveTvFocusNode;
  final bool isCompact;
  final bool isBigPicture; 
  final VoidCallback onTapFakeInput; 
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;

  const SearchHeaderBar({
    super.key,
    required this.textController,
    required this.searchFocusNode,
    required this.clearButtonFocusNode,
    required this.moviesShowsFocusNode,
    required this.liveTvFocusNode,
    required this.isCompact,
    required this.isBigPicture,
    required this.onTapFakeInput,
    required this.onSubmitted,
    required this.onChanged,
  });

  @override
  ConsumerState<SearchHeaderBar> createState() => _SearchHeaderBarState();
}

class _SearchHeaderBarState extends ConsumerState<SearchHeaderBar> {
  final GlobalKey<PopupMenuButtonState<SearchFilter>> _popupKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final filter = ref.watch(searchFilterProvider);
    final isLive = filter == SearchFilter.live;
    final searchResultsAsync = ref.watch(searchResultsProvider);

    return Container(
      height: LayoutConstants.dashboardHeaderHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: LayoutConstants.dashboardContentPadding,
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.textController,
                builder: (context, value, child) {
                  final query = value.text;

                  if (widget.isBigPicture) {
                    return ExcludeFocus(
                      excluding: true,
                      child: FocusableWrapper(
                        onTap: widget.onTapFakeInput,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(LayoutConstants.radiusPill),
                            border: Border.all(color: Colors.transparent), 
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  query.isEmpty ? l10n.searchHint : query,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: query.isEmpty ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (query.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Icon(Icons.edit_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

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
                  } else if (value.text.isNotEmpty) {
                    suffix = IconButton(
                      focusNode: widget.clearButtonFocusNode,
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        widget.textController.clear();
                        ref.read(searchSuggestionControllerProvider.notifier).clear();
                        ref.read(searchQueryProvider.notifier).set('');
                      },
                    );
                  }

                  return TextField(
                    controller: widget.textController,
                    focusNode: widget.searchFocusNode,
                    autofocus: false,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlignVertical: TextAlignVertical.center,
                    textInputAction: TextInputAction.search,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
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
                      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 42),
                      suffixIcon: suffix,
                      suffixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(width: 12),

          FocusableWrapper(
            onTap: () => _popupKey.currentState?.showButtonMenu(),
            child: PopupMenuButton<SearchFilter>(
              key: _popupKey,
              tooltip: 'Search scope',
              onSelected: (value) => ref.read(searchFilterProvider.notifier).set(value),
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
                        Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
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
                        Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ],
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                ),
                child: Text(
                  isLive ? '📺' : '🍿',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}