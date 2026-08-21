import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:skystream/features/settings/presentation/big_picture_provider.dart';

import '../../../../core/router/app_router.dart';
import 'package:skystream/core/domain/entity/multimedia_item.dart';
import 'package:skystream/core/extensions/extension_manager.dart';
import 'package:skystream/core/utils/image_fallbacks.dart';
import 'package:skystream/features/search/presentation/search_provider.dart';

import '../../../../shared/widgets/desktop_scroll_wrapper.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../../shared/widgets/shimmer_placeholder.dart';
import '../../../../shared/widgets/thumbnail_error_placeholder.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

// TV/Gamepad Feature Imports
import '../../../../core/input/gamepad_actions.dart';
import '../../../../shared/widgets/gamepad_hints_overlay.dart';
import '../../../../core/providers/device_info_provider.dart';

part 'provider_search_section.g.dart';

// Delegates to the shared searchAllProviders() function — no duplicated
// fan-out, mapping, or filtering logic.
@riverpod
Stream<SearchAggregateState> providerSearch(Ref ref, String query) {
  ref.watch(extensionManagerProvider);
  final manager = ref.read(extensionManagerProvider.notifier);

  var cancelled = false;
  ref.onDispose(() => cancelled = true);

  return searchAllProviders(
    ref,
    query,
    manager,
    filter: SearchFilter.content,
    isCancelled: () => cancelled,
  );
}

class ProviderSearchSection extends ConsumerStatefulWidget {
  final String query;
  final bool compact;
  final String? parentMediaType; // 'movie' or 'tv'
  final int? tmdbId;
  final String? imdbId;

  const ProviderSearchSection({
    super.key,
    required this.query,
    this.compact = false,
    this.parentMediaType,
    this.tmdbId,
    this.imdbId,
  });

  @override
  ConsumerState<ProviderSearchSection> createState() =>
      _ProviderSearchSectionState();
}

class _ProviderSearchSectionState extends ConsumerState<ProviderSearchSection> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.query.isEmpty) return const SizedBox.shrink();

    final plugins = ref.watch(extensionManagerProvider);
    final searchAsync = ref.watch(providerSearchProvider(widget.query));

    // Master Switch Evaluation
    final isTv = ref.watch(deviceProfileProvider).asData?.value.isTv ?? false;
    final isBigPicture = ref.watch(bigPictureModeProvider).isEnabled || isTv;

    Widget content;
    if (plugins.isEmpty) {
      content = Container(
        height: 140,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(LayoutConstants.spacingMd),
        child: Text(
          AppLocalizations.of(context)!.noPluginsInstalled,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
      );
    } else {
      content = searchAsync.when(
        data: (state) {
          final allItems = <Map<String, dynamic>>[];
          for (final pResult in state.results) {
            for (final item in pResult.results) {
              allItems.add({
                'item': item,
                'providerName': pResult.providerName,
              });
            }
          }

          if (allItems.isEmpty) {
            if (state.isLoading) {
              return const SizedBox(
                height: 140,
                child: Center(
                  child: AppLoadingIndicator(
                    constraints: BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                      maxWidth: 24,
                      maxHeight: 24,
                    ),
                  ),
                ),
              );
            }
            return Container(
              height: 140,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(LayoutConstants.spacingMd),
              child: Text(
                AppLocalizations.of(context)!.noResultsFound,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            );
          }

          return RepaintBoundary(
            child: SizedBox(
              height: 140,
              child: DesktopScrollWrapper(
                controller: _scrollController,
                child: ListView.separated(
                  controller: _scrollController,
                  clipBehavior: Clip.none,
                  scrollDirection: Axis.horizontal,
                  padding: widget.compact
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(
                          horizontal: LayoutConstants.spacingMd,
                        ),
                  itemCount: allItems.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: LayoutConstants.spacingSm),
                  itemBuilder: (context, index) {
                    final data = allItems[index];
                    final item = data['item'] as MultimediaItem;
                    final providerName = data['providerName'] as String;

                    return _FocusableSourceCard(
                      isBigPicture: isBigPicture,
                      onTap: () {
                        // Enrich item with provider, content type, and metadata IDs before navigation
                        final enrichedItem = item.copyWith(
                          provider: providerName,
                          contentType: widget.parentMediaType != null
                              ? MultimediaItem.parseContentType(
                                  widget.parentMediaType,
                                )
                              : item.contentType,
                          tmdbId: widget.tmdbId ?? item.tmdbId,
                          imdbId: widget.imdbId ?? item.imdbId,
                        );
                        DetailsRoute(
                          $extra: DetailsRouteExtra(item: enrichedItem),
                        ).push<void>(context);
                      },
                      child: SizedBox(
                        width: 220,
                        child: Card(
                          elevation: 0,
                          margin: EdgeInsets.zero,
                          color: Theme.of(context).colorScheme.surface,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 90,
                                height: double.infinity,
                                child: CachedNetworkImage(
                                  imageUrl:
                                      AppImageFallbacks.poster(
                                        item.posterUrl,
                                        label: item.title,
                                      ) ??
                                      '',
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) =>
                                      ShimmerPlaceholder(borderRadius: 8),
                                  errorWidget: (_, _, _) =>
                                      const ThumbnailErrorPlaceholder(),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(10.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        item.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          providerName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
        loading: () => const SizedBox(
          height: 140,
          child: Center(
            child: AppLoadingIndicator(
              constraints: BoxConstraints(
                minWidth: 24,
                minHeight: 24,
                maxWidth: 24,
                maxHeight: 24,
              ),
            ),
          ),
        ),
        error: (err, _) => Padding(
          padding: const EdgeInsets.all(LayoutConstants.spacingMd),
          child: Text(
            AppLocalizations.of(context)!.errorPrefix(err.toString()),
          ),
        ),
      );
    }

    if (widget.compact) return content;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 180),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: LayoutConstants.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LayoutConstants.spacingMd,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.extension,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: LayoutConstants.spacingXs),
                Text(
                  AppLocalizations.of(context)!.availableSources,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: LayoutConstants.spacingXs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "BETA",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: LayoutConstants.spacingSm),
          content,
        ],
      ),
    );
  }
}

class _FocusableSourceCard extends ConsumerStatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool isBigPicture;

  const _FocusableSourceCard({
    required this.child,
    required this.onTap,
    required this.isBigPicture,
  });

  @override
  ConsumerState<_FocusableSourceCard> createState() =>
      _FocusableSourceCardState();
}

class _FocusableSourceCardState extends ConsumerState<_FocusableSourceCard> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Semantics(
      button: true,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
          AppSelectButtonIntent: CallbackAction<AppSelectButtonIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: Focus(
          onFocusChange: (hasFocus) {
            setState(() => _isFocused = hasFocus);
            if (hasFocus) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;

                // Perfect centering logic for TV UX
                Scrollable.maybeOf(context)?.position.ensureVisible(
                  context.findRenderObject()!,
                  alignment: 0.5,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.fastOutSlowIn,
                );

                // Dispatch Gamepad Hints
                if (widget.isBigPicture) {
                  ref.read(focusedGamepadHintsProvider.notifier).state = [
                    GamepadHint(
                      buttonLabel: 'A',
                      actionLabel: l10n.hintSelect,
                      buttonColor: Colors.greenAccent.shade400,
                    ),
                  ];
                }
              });
            } else {
              if (widget.isBigPicture) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final currentHints = ref.read(focusedGamepadHintsProvider);
                  if (currentHints?.any(
                        (h) => h.actionLabel == l10n.hintSelect,
                      ) ==
                      true) {
                    ref.read(focusedGamepadHintsProvider.notifier).state = null;
                  }
                });
              }
            }
          },
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.space) {
              widget.onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedScale(
                scale: _isFocused ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      14,
                    ), // Matches inner card + 2px
                    border: Border.all(
                      color: (_isFocused || _isHovered) && widget.isBigPicture
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: _isFocused && widget.isBigPicture
                        ? [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.35),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
