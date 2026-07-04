import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:skystream/features/library/presentation/history_provider.dart';
import '../../../../core/domain/entity/multimedia_item.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/router/app_router.dart';
import 'package:skystream/core/utils/image_fallbacks.dart';
import 'package:skystream/core/utils/layout_constants.dart';
import '../../../../core/extensions/extension_manager.dart';
import '../../../../shared/widgets/cards_wrapper.dart';
import '../../../../shared/widgets/loading_dialog.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import 'package:skystream/core/services/notification_service.dart';
import '../../../../core/widgets/focusable_wrapper.dart'; 
import '../../../../shared/widgets/gamepad_hints_overlay.dart'; 

class ContinueWatchingCard extends ConsumerStatefulWidget {
  final HistoryItem historyItem;
  final double width;
  final bool isLarge;

  const ContinueWatchingCard({
    super.key,
    required this.historyItem,
    this.width = 280,
    this.isLarge = false,
  });

  @override
  ConsumerState<ContinueWatchingCard> createState() =>
      _ContinueWatchingCardState();
}

class _ContinueWatchingCardState extends ConsumerState<ContinueWatchingCard> {
  bool _isHovered = false;

  static String _normalizeMatchKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static MultimediaItem? _pickBestLiveMatch(
    Iterable<MultimediaItem> candidates,
    MultimediaItem target,
  ) {
    final normalizedTarget = _normalizeMatchKey(target.title);
    if (normalizedTarget.isEmpty) return null;

    final exactTitleMatches = candidates.where(
      (candidate) =>
          candidate.contentType == MultimediaContentType.livestream &&
          _normalizeMatchKey(candidate.title) == normalizedTarget,
    );

    if (target.posterUrl.isNotEmpty) {
      final posterMatch = exactTitleMatches.firstWhereOrNull(
        (candidate) => candidate.posterUrl == target.posterUrl,
      );
      if (posterMatch != null) return posterMatch;
    }

    return exactTitleMatches.firstOrNull;
  }

  Future<MultimediaItem?> _resolveFreshLiveItem(
    WidgetRef ref,
    MultimediaItem item,
  ) async {
    final providerId = item.provider;
    if (providerId == null || providerId.isEmpty) return null;

    final manager = ref.read(extensionManagerProvider.notifier);
    final provider = manager.getAllProviders().firstWhereOrNull(
      (p) => p.packageName == providerId || p.name == providerId,
    );
    if (provider == null) return null;

    try {
      final results = await provider.search(item.title);
      final match = _pickBestLiveMatch(results, item);
      if (match != null) {
        return match.copyWith(provider: provider.packageName);
      }
    } catch (_) {}

    try {
      final homeSections = await provider.getHome();
      final flattened = homeSections.values.expand((items) => items);
      final match = _pickBestLiveMatch(flattened, item);
      if (match != null) {
        return match.copyWith(provider: provider.packageName);
      }
    } catch (_) {}

    return null;
  }

  String _formatDuration(int milliseconds) {
    if (milliseconds <= 0) return '00:00';
    final d = Duration(milliseconds: milliseconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      if (m > 0) return '${h}h ${m}m';
      return '${h}h';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.historyItem.item;
    final double progress = (widget.historyItem.duration > 0)
        ? (widget.historyItem.position / widget.historyItem.duration).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    final isLivestream = item.contentType == MultimediaContentType.livestream;
    final isSeries = item.contentType == MultimediaContentType.series;
    final isAnime = item.contentType == MultimediaContentType.anime;
    final hasEpisodes = isSeries || isAnime;

    final imageUrl = hasEpisodes
        ? (widget.historyItem.episodePosterUrl ?? item.backdropImageUrl)
        : item.backdropImageUrl;
    final bannerUrl = AppImageFallbacks.poster(imageUrl, label: item.title);

    final episodeLabel =
        hasEpisodes &&
            widget.historyItem.season != null &&
            widget.historyItem.episode != null &&
            (widget.historyItem.season! > 0 || widget.historyItem.episode! > 0)
        ? "S${widget.historyItem.season} E${widget.historyItem.episode}${widget.historyItem.episodeTitle != null && widget.historyItem.episodeTitle!.isNotEmpty && !widget.historyItem.episodeTitle!.startsWith("Episode") ? " - ${widget.historyItem.episodeTitle}" : ""}"
        : null;

    return CardsWrapper(
      onTap: () async {
        if (isLivestream) {
          bool dialogDismissed = false;
          bool canceled = false;
          unawaited(
            LoadingDialog.show(
              context,
              message: AppLocalizations.of(context)!.refreshingLiveStream,
              onCancel: () {
                canceled = true;
                dialogDismissed = true;
              },
            ),
          );
          final refreshedItem = await _resolveFreshLiveItem(ref, item);
          if (!context.mounted || canceled) return;

        if (!dialogDismissed) {
          Navigator.of(context, rootNavigator: true).pop();
          dialogDismissed = true;
        }

        final liveItem = refreshedItem ?? item;
        if (!context.mounted || canceled) return;

        unawaited(
          PlayerRoute(
            $extra: PlayerRouteExtra(item: liveItem, videoUrl: liveItem.url),
          ).push<void>(context),
        );
        unawaited(
          ref.read(watchHistoryProvider.notifier).removeFromHistory(item.url),
        );
        return;
      }

      unawaited(
        DetailsRoute(
          $extra: DetailsRouteExtra(item: item, autoPlay: true),
        ).push<void>(context),
      );
    };

    // 2. GAMEPAD 'X' - Delete
    final handleSecondaryTap = () {
      ref.read(watchHistoryProvider.notifier).removeFromHistory(item.url);
      ref.read(notificationServiceProvider).showSuccess(
        AppLocalizations.of(context)!.removedFromHistory(item.title),
      );
    };

    // 3. GAMEPAD 'Y' (or Touch Hold) - Context Menu
    final handleLongPress = () {
      showModalBottomSheet<void>(
        context: context,
        builder: (context) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(AppLocalizations.of(context)!.viewDetails),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(
                    DetailsRoute(
                      $extra: DetailsRouteExtra(item: item),
                    ).push<void>(context),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  AppLocalizations.of(context)!.removeFromHistory,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                onTap: () {
                  handleSecondaryTap();
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text(AppLocalizations.of(context)!.cancel),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
    };

    // WIRED UP: Tap, SecondaryTap, and LongPress!
    return FocusableWrapper(
      onTap: handleTap,
      onSecondaryTap: handleSecondaryTap,
      onLongPress: handleLongPress,
      // CONTEXT AWARE HINTS: Tell the global overlay what this specific card does!
      gamepadHints: [
        GamepadHint(buttonLabel: 'A', actionLabel: 'Play', buttonColor: Colors.greenAccent.shade400),
        GamepadHint(buttonLabel: 'X', actionLabel: 'Remove', buttonColor: Colors.redAccent.shade400),
        GamepadHint(buttonLabel: 'Y', actionLabel: 'Options', buttonColor: Colors.amberAccent.shade400),
      ],
      child: CardsWrapper(
        onTap: handleTap,
        onLongPress: handleLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Container(
              width: width,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(12),
                      ),
                      child: CachedNetworkImage(
                        imageUrl:
                            AppImageFallbacks.poster(
                              item.posterUrl,
                              label: item.title,
                            ) ??
                            '',
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: Theme.of(context).dividerColor),
                        errorWidget: (_, _, _) =>
                            ThumbnailErrorPlaceholder(label: item.title),
                      ),
                    ),
                  ),
                ),

                // Bottom info column
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 24, 12, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasEpisodes || isLivestream) ...[
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        if (isLivestream)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(
                                LayoutConstants.radiusSm,
                              ),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          )
                        else
                          Text(
                            episodeLabel ?? item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
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
      ),
    );
  }
}