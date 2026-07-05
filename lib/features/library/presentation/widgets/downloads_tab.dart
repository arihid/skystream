import 'dart:async';
import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/utils/image_fallbacks.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/services/download_service.dart';
import '../../../../core/utils/layout_constants.dart';
import '../../../details/presentation/playback_launcher.dart';
import '../downloads_provider.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/providers/device_info_provider.dart';

import '../../../../core/widgets/focusable_wrapper.dart';
import '../../../../shared/widgets/gamepad_hints_overlay.dart';
import '../../../../shared/widgets/loading_indicator.dart';

class DownloadsTab extends ConsumerStatefulWidget {
  const DownloadsTab({super.key});

  @override
  ConsumerState<DownloadsTab> createState() => _DownloadsTabState();
}

class _DownloadsTabState extends ConsumerState<DownloadsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final downloadsAsync = ref.watch(downloadsProvider);
    final activeProgress = ref.watch(downloadProgressProvider);
    final l10n = AppLocalizations.of(context)!;

    return downloadsAsync.when(
      data: (downloads) {
        if (downloads.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.download_for_offline_outlined,
                  size: 64,
                  color: Theme.of(context).dividerColor,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.noDownloadsYet,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          );
        }

        // Grouping logic
        final Map<String, List<DownloadItem>> grouped = {};
        final List<String> keys = [];

        for (final item in downloads) {
          final String key = item.item.tmdbId?.toString() ?? item.item.title;
          if (!grouped.containsKey(key)) {
            keys.add(key);
            grouped[key] = [];
          }
          grouped[key]!.add(item);
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: keys.length,
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final key = keys[index];
            final groupItems = grouped[key]!;

            if (groupItems.length == 1) {
              final download = groupItems.first;
              final trackingUrl = download.task.metaData;
              final progressData = activeProgress[trackingUrl];
              final double displayProgress =
                  progressData?.progress ?? download.progress;
              final TaskStatus displayStatus =
                  progressData?.status ?? download.status;

              return _DownloadItemTile(
                item: download,
                progress: displayProgress,
                status: displayStatus,
                progressData: progressData,
              );
            } else {
              return _GroupedDownloadTile(
                items: groupItems,
                activeProgress: activeProgress,
              );
            }
          },
        );
      },
      loading: () => const Center(child: AppLoadingIndicator()),
      error: (err, stack) =>
          Center(child: Text(l10n.errorPrefix(err.toString()))),
    );
  }
}

class _GroupedDownloadTile extends ConsumerStatefulWidget {
  final List<DownloadItem> items;
  final Map<String, DownloadProgressData> activeProgress;

  const _GroupedDownloadTile({
    required this.items,
    required this.activeProgress,
  });

  @override
  ConsumerState<_GroupedDownloadTile> createState() => _GroupedDownloadTileState();
}

class _GroupedDownloadTileState extends ConsumerState<_GroupedDownloadTile> {
  bool _isExpanded = false;

  void _toggleExpand() {
    setState(() => _isExpanded = !_isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final firstItem = widget.items.first;

    final isTv = ref.watch(deviceProfileProvider).asData?.value.isTv ?? false;

    final completedCount = widget.items.where((i) {
      final status = widget.activeProgress[i.task.metaData]?.status ?? i.status;
      return status == TaskStatus.complete;
    }).length;

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LayoutConstants.radiusXl),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FocusableWrapper(
            useScaleEffect: false, 
            onTap: _toggleExpand,
            onSecondaryTap: () => _confirmDeleteAll(context, ref),
            gamepadHints: [
              GamepadHint(buttonLabel: 'A', actionLabel: _isExpanded ? 'Collapse' : 'Expand', buttonColor: Colors.greenAccent.shade400),
              GamepadHint(buttonLabel: 'X', actionLabel: 'Delete All', buttonColor: Colors.redAccent.shade400),
              // 🎯 Split into two beautiful distinct buttons!
              GamepadHint(buttonLabel: 'LB', actionLabel: 'Prev Tab', buttonColor: Colors.white), 
              GamepadHint(buttonLabel: 'RB', actionLabel: 'Next Tab', buttonColor: Colors.white), 
              GamepadHint(buttonLabel: '≡', actionLabel: 'Menu', buttonColor: Colors.white),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LayoutConstants.spacingMd,
                vertical: LayoutConstants.spacingSm,
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(LayoutConstants.radiusMd),
                    child: CachedNetworkImage(
                      imageUrl: AppImageFallbacks.poster(
                            firstItem.item.posterUrl,
                            label: firstItem.item.title,
                          ) ?? '',
                      width: 60,
                      height: 90,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => Container(
                        width: 60,
                        height: 90,
                        color: theme.dividerColor,
                        child: const Icon(Icons.movie_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: LayoutConstants.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          firstItem.item.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.library_books_rounded,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l10n.episodesCount(widget.items.length, completedCount),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: LayoutConstants.spacingSm),
                  
                  if (!isTv)
                    ExcludeFocus(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => _confirmDeleteAll(context, ref),
                            color: theme.colorScheme.error.withValues(alpha: 0.8),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            icon: Icon(_isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                            onPressed: _toggleExpand,
                            color: theme.colorScheme.onSurfaceVariant,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_isExpanded
                ? const SizedBox.shrink()
                : Column(
                    children: widget.items.asMap().entries.map((entry) {
                      final download = entry.value;

                      final trackingUrl = download.task.metaData;
                      final progressData = widget.activeProgress[trackingUrl];
                      final double displayProgress = progressData?.progress ?? download.progress;
                      final TaskStatus displayStatus = progressData?.status ?? download.status;

                      return Column(
                        children: [
                          Divider(
                            height: 1,
                            color: theme.dividerColor.withValues(alpha: 0.4),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: LayoutConstants.spacingSm,
                              vertical: LayoutConstants.spacingSm,
                            ),
                            child: _DownloadItemTile(
                              item: download,
                              progress: displayProgress,
                              status: displayStatus,
                              progressData: progressData,
                              isInsideGroup: true,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAll(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteAllEpisodes),
        content: Text(
          l10n.confirmDeleteAllEpisodes(widget.items.length, widget.items.first.item.title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(downloadsProvider.notifier).removeDownloads(widget.items);
            },
            child: Text(
              l10n.deleteAll,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadItemTile extends ConsumerWidget {
  final DownloadItem item;
  final double progress;
  final TaskStatus status;
  final DownloadProgressData? progressData;
  final bool isInsideGroup;

  const _DownloadItemTile({
    required this.item,
    required this.progress,
    required this.status,
    this.progressData,
    this.isInsideGroup = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    
    final isTv = ref.watch(deviceProfileProvider).asData?.value.isTv ?? false;

    final isDone = status == TaskStatus.complete;
    final isWorking = status == TaskStatus.running || status == TaskStatus.enqueued;
    final isPaused = status == TaskStatus.paused;

    VoidCallback? primaryAction;
    String primaryActionLabel = '';

    if (isDone) {
      primaryAction = () => _playLocalFile(context, ref, l10n);
      primaryActionLabel = 'Play';
    } else if (isPaused) {
      primaryAction = () => ref.read(downloadsProvider.notifier).resumeDownload(item.task.taskId);
      primaryActionLabel = 'Resume';
    } else if (isWorking) {
      primaryAction = () => ref.read(downloadsProvider.notifier).pauseDownload(item.task.taskId);
      primaryActionLabel = 'Pause';
    }

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(LayoutConstants.radiusMd),
          child: CachedNetworkImage(
            imageUrl: AppImageFallbacks.poster(
                  item.item.posterUrl,
                  label: item.item.title,
                ) ?? '',
            width: 80,
            height: 120,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => Container(
              width: 80,
              height: 120,
              color: theme.dividerColor,
              child: const Icon(Icons.movie_outlined),
            ),
          ),
        ),
        const SizedBox(width: LayoutConstants.spacingMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (isInsideGroup && item.episode != null)
                    ? 'S${item.episode!.season} E${item.episode!.episode}: ${item.episode!.name}'
                    : item.item.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (!isInsideGroup &&
                  item.episode != null &&
                  item.item.contentType == MultimediaContentType.series) ...[
                const SizedBox(height: 2),
                Text(
                  'S${item.episode!.season} E${item.episode!.episode}: ${item.episode!.name}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    isDone ? Icons.check_circle_rounded : Icons.download_rounded,
                    size: 14,
                    color: isDone ? Colors.green : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isDone ? l10n.completed : _getStatusText(status, l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDone ? Colors.green : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LayoutConstants.spacingSm),
              if (!isDone) ...[
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: theme.dividerColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(LayoutConstants.radiusSm),
                ),
                const SizedBox(height: 4),
                if (progressData != null && isWorking)
                  Text(
                    progressData!.speedString,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isTv)
                    ExcludeFocus(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isWorking)
                            IconButton(
                              icon: const Icon(Icons.pause_rounded),
                              onPressed: primaryAction,
                              visualDensity: VisualDensity.compact,
                            ),
                          if (isPaused)
                            IconButton(
                              icon: const Icon(Icons.play_arrow_rounded),
                              onPressed: primaryAction,
                              visualDensity: VisualDensity.compact,
                            ),
                          if (isDone)
                            IconButton(
                              icon: const Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.green,
                              ),
                              onPressed: primaryAction,
                              iconSize: 28,
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => _confirmDelete(context, ref, l10n),
                            color: theme.colorScheme.error.withValues(alpha: 0.8),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return FocusableWrapper(
      useScaleEffect: false, 
      onTap: primaryAction ?? () {},
      onSecondaryTap: () => _confirmDelete(context, ref, l10n),
      gamepadHints: [
        if (primaryActionLabel.isNotEmpty)
          GamepadHint(buttonLabel: 'A', actionLabel: primaryActionLabel, buttonColor: Colors.greenAccent.shade400),
        GamepadHint(buttonLabel: 'X', actionLabel: 'Delete', buttonColor: Colors.redAccent.shade400),
        // 🎯 Split into two beautiful distinct buttons!
        GamepadHint(buttonLabel: 'LB', actionLabel: 'Prev Tab', buttonColor: Colors.white), 
        GamepadHint(buttonLabel: 'RB', actionLabel: 'Next Tab', buttonColor: Colors.white), 
        GamepadHint(buttonLabel: '≡', actionLabel: 'Menu', buttonColor: Colors.white),
      ],
      child: Container(
        padding: EdgeInsets.all(isInsideGroup ? LayoutConstants.spacingSm : LayoutConstants.spacingMd),
        decoration: isInsideGroup 
           ? null 
           : BoxDecoration(
               color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
               borderRadius: BorderRadius.circular(LayoutConstants.radiusXl),
               border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
             ),
        child: content,
      ),
    );
  }

  String _getStatusText(TaskStatus status, AppLocalizations l10n) {
    switch (status) {
      case TaskStatus.enqueued:
        return l10n.statusQueued;
      case TaskStatus.running:
        return l10n.statusDownloading;
      case TaskStatus.complete:
        return l10n.statusFinished;
      case TaskStatus.failed:
        return l10n.statusFailed;
      case TaskStatus.canceled:
        return l10n.statusCanceled;
      case TaskStatus.paused:
        return l10n.statusPaused;
      default:
        return l10n.statusWaiting;
    }
  }

  Future<void> _playLocalFile(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final downloadService = ref.read(downloadServiceProvider);
    final File? file = await downloadService.getDownloadedFile(
      item.item,
      episode: item.episode,
    );

    if (file == null || !await file.exists()) {
      if (context.mounted) {
        ref
            .read(notificationServiceProvider)
            .showError(l10n.fileNotFoundRemoving);
      }
      await ref.read(downloadsProvider.notifier).removeDownload(item);
      return;
    }

    if (context.mounted) {
      unawaited(
        ref
            .read(playbackLauncherProvider)
            .play(context, file.path, baseItem: item.item),
      );
    }
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteDownload),
        content: Text(l10n.confirmDeleteDownload),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(downloadsProvider.notifier).removeDownload(item);
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}