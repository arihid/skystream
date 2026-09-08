import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/nuvio/data/nuvio_repository.dart';
import '../../../core/nuvio/data/nuvio_runtime.dart';
import '../../../core/nuvio/data/nuvio_stream_service.dart';
import '../../../core/nuvio/models/nuvio_models.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../shared/widgets/custom_widgets.dart';
import '../../../shared/widgets/loading_indicator.dart';
import 'nuvio_scraper_settings_dialog.dart';

// Gamepad / Master Switch Imports
import '../../../core/providers/device_info_provider.dart';
import '../../settings/presentation/big_picture_provider.dart';
import '../../../shared/widgets/gamepad_hints_overlay.dart';
import '../../../core/input/gamepad_actions.dart';

// ---------------------------------------------------------------------------
// Unified Action Tile (Listens ONLY to Gamepad Intents!)
// ---------------------------------------------------------------------------
class _ActionTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onTertiaryTap;
  final VoidCallback? onLeftTriggerTap;
  final VoidCallback? onRightTriggerTap;
  final ValueChanged<bool>? onFocusChange;

  const _ActionTile({
    required this.title,
    required this.subtitle,
    this.leading,
    this.trailing,
    required this.onTap,
    this.onSecondaryTap,
    this.onTertiaryTap,
    this.onLeftTriggerTap,
    this.onFocusChange,
  }) : onRightTriggerTap = null;

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
        if (widget.onSecondaryTap != null)
          AppSecondaryIntent: CallbackAction<AppSecondaryIntent>(
            onInvoke: (_) {
              widget.onSecondaryTap!();
              return null;
            },
          ),
        if (widget.onTertiaryTap != null)
          AppTertiaryIntent: CallbackAction<AppTertiaryIntent>(
            onInvoke: (_) {
              widget.onTertiaryTap!();
              return null;
            },
          ),
        if (widget.onLeftTriggerTap != null)
          AppLeftTriggerIntent: CallbackAction<AppLeftTriggerIntent>(
            onInvoke: (_) {
              widget.onLeftTriggerTap!();
              return null;
            },
          ),
        if (widget.onRightTriggerTap != null)
          AppRightTriggerIntent: CallbackAction<AppRightTriggerIntent>(
            onInvoke: (_) {
              widget.onRightTriggerTap!();
              return null;
            },
          ),
      },
      child: Focus(
        onFocusChange: (f) {
          setState(() => _isFocused = f);
          widget.onFocusChange?.call(f);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: _isFocused
                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border.all(
              color: _isFocused
                  ? theme.colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutConstants.spacingMd,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    if (widget.leading != null) ...[
                      widget.leading!,
                      const SizedBox(width: LayoutConstants.spacingSm),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _isFocused
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: 16),
                      ExcludeFocus(child: widget.trailing!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Manage Nuvio-format plugin repositories.
class NuvioPluginsView extends ConsumerStatefulWidget {
  const NuvioPluginsView({super.key});

  @override
  ConsumerState<NuvioPluginsView> createState() => _NuvioPluginsViewState();
}

class _NuvioPluginsViewState extends ConsumerState<NuvioPluginsView> {
  bool _busy = false;
  bool _checking = false;
  List<GamepadHint>? _mainHints;
  List<GamepadHint>? _autoUpdateHints;

  Future<void> _addRepository() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Add Nuvio Repository'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste the plugin manifest URL (the JSON listing "scrapers"). A bare host works too.',
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: LayoutConstants.spacingMd),
              CustomTextField(
                controller: controller,
                hintText: 'https://example.com/plugins/manifest.json',
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    Navigator.pop(dialogContext, value.trim());
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          CustomButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: LayoutConstants.spacingXs),
          CustomButton(
            isPrimary: true,
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (url == null || url.isEmpty) return;

    setState(() => _busy = true);
    try {
      final repo = await ref
          .read(nuvioRepositoryProvider.notifier)
          .addRepository(url);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Added ${repo.displayName} ${repo.manifest?.version ?? ''} · ${repo.manifest?.scrapers.length ?? 0} plugins',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkForUpdates() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checking = true);
    try {
      final changes = await ref
          .read(nuvioRepositoryProvider.notifier)
          .refreshAll();
      ref.read(nuvioStreamServiceProvider).clearCache();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            changes == 0
                ? 'All Nuvio plugins are up to date'
                : '$changes plugin${changes == 1 ? '' : 's'} updated',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nuvioRepositoryProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isTv = ref.watch(deviceProfileProvider).asData?.value.isTv ?? false;
    final isBigPicture = ref.watch(bigPictureModeProvider).isEnabled || isTv;

    return ListView(
      padding: const EdgeInsets.only(
        top: LayoutConstants.spacingMd,
        bottom: 100,
      ),
      addAutomaticKeepAlives: false,
      children: [
        _FocusableCard(
          margin: const EdgeInsets.symmetric(
            horizontal: LayoutConstants.spacingMd,
            vertical: LayoutConstants.spacingXs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ActionTile(
                title: 'Nuvio Scrapers',
                subtitle:
                    'JS scrapers feed the Explore sources sheet alongside SkyStream plugins.',
                leading: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.extension_outlined,
                    color: cs.primary,
                    size: 22,
                  ),
                ),
                trailing: isBigPicture
                    ? ExcludeFocus(
                        child: CustomSwitch(
                          value: state.enabled,
                          onChanged: (_) {},
                        ),
                      )
                    : CustomSwitch(
                        value: state.enabled,
                        onChanged: (val) => unawaited(
                          ref
                              .read(nuvioRepositoryProvider.notifier)
                              .setEnabled(val),
                        ),
                      ),
                onTap: () => unawaited(
                  ref
                      .read(nuvioRepositoryProvider.notifier)
                      .setEnabled(!state.enabled),
                ),
                onSecondaryTap: _busy
                    ? null
                    : () => unawaited(_addRepository()),
                onTertiaryTap: _checking
                    ? null
                    : () => unawaited(_checkForUpdates()),
                onFocusChange: (f) {
                  if (f && isBigPicture) {
                    _mainHints = [
                      GamepadHint(
                        buttonLabel: 'A',
                        actionLabel: 'Toggle',
                        buttonColor: Colors.greenAccent.shade400,
                      ),
                      GamepadHint(
                        buttonLabel: 'X',
                        actionLabel: 'Add Repo',
                        buttonColor: Colors.blueAccent.shade400,
                      ),
                      GamepadHint(
                        buttonLabel: 'Y',
                        actionLabel: 'Check Updates',
                        buttonColor: Colors.amberAccent.shade400,
                      ),
                    ];
                    ref.read(focusedGamepadHintsProvider.notifier).state =
                        _mainHints;
                  } else if (!f && isBigPicture) {
                    Future.microtask(() {
                      if (mounted &&
                          ref.read(focusedGamepadHintsProvider) == _mainHints) {
                        ref.read(focusedGamepadHintsProvider.notifier).state =
                            null;
                      }
                    });
                  }
                },
              ),

              if (!isBigPicture) ...[
                Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.5),
                ),
                Padding(
                  padding: const EdgeInsets.all(LayoutConstants.spacingMd),
                  child: Wrap(
                    spacing: LayoutConstants.spacingSm,
                    runSpacing: LayoutConstants.spacingXs,
                    children: [
                      CustomButton(
                        isPrimary: true,
                        onPressed: _busy
                            ? null
                            : () => unawaited(_addRepository()),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_busy) ...[
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: AppLoadingIndicator(
                                  constraints: BoxConstraints(
                                    maxWidth: 16,
                                    maxHeight: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ] else ...[
                              const Icon(Icons.add_circle_outline, size: 18),
                              const SizedBox(width: 8),
                            ],
                            const Text('Add Repository'),
                          ],
                        ),
                      ),
                      if (state.repos.isNotEmpty)
                        CustomButton(
                          isOutlined: true,
                          onPressed: _checking
                              ? null
                              : () => unawaited(_checkForUpdates()),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_checking) ...[
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: AppLoadingIndicator(
                                    constraints: BoxConstraints(
                                      maxWidth: 16,
                                      maxHeight: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ] else ...[
                                const Icon(Icons.refresh_rounded, size: 18),
                                const SizedBox(width: 8),
                              ],
                              Text(_checking ? 'Checking…' : 'Check Updates'),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              if (state.repos.isNotEmpty) ...[
                Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.5),
                ),
                _ActionTile(
                  title: 'Auto-update scrapers on launch',
                  subtitle:
                      'Checks each repository (max once every ${NuvioRepository.autoUpdateInterval.inHours}h).',
                  trailing: isBigPicture
                      ? ExcludeFocus(
                          child: CustomSwitch(
                            value: state.autoUpdate,
                            onChanged: (_) {},
                          ),
                        )
                      : CustomSwitch(
                          value: state.autoUpdate,
                          onChanged: (val) => unawaited(
                            ref
                                .read(nuvioRepositoryProvider.notifier)
                                .setAutoUpdate(val),
                          ),
                        ),
                  onTap: () => unawaited(
                    ref
                        .read(nuvioRepositoryProvider.notifier)
                        .setAutoUpdate(!state.autoUpdate),
                  ),
                  onFocusChange: (f) {
                    if (f && isBigPicture) {
                      _autoUpdateHints = [
                        GamepadHint(
                          buttonLabel: 'A',
                          actionLabel: 'Toggle',
                          buttonColor: Colors.greenAccent.shade400,
                        ),
                      ];
                      ref.read(focusedGamepadHintsProvider.notifier).state =
                          _autoUpdateHints;
                    } else if (!f && isBigPicture) {
                      Future.microtask(() {
                        if (mounted &&
                            ref.read(focusedGamepadHintsProvider) ==
                                _autoUpdateHints) {
                          ref.read(focusedGamepadHintsProvider.notifier).state =
                              null;
                        }
                      });
                    }
                  },
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: LayoutConstants.spacingSm),

        // Loading State
        if (state.isLoading && state.repos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: AppLoadingIndicator()),
          ),

        // Empty State
        if (!state.isLoading && state.repos.isEmpty && !isBigPicture)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LayoutConstants.spacingMd,
              vertical: LayoutConstants.spacingSm,
            ),
            child: _FocusableCard(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(LayoutConstants.spacingLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.snippet_folder_outlined,
                      size: 48,
                      color: cs.primary,
                    ),
                    const SizedBox(height: LayoutConstants.spacingMd),
                    Text(
                      'No Nuvio Repositories Yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: LayoutConstants.spacingSm),
                    Text(
                      'Add a repository URL to load scrapers for stream extraction.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: LayoutConstants.spacingLg),
                    CustomButton(
                      isPrimary: true,
                      onPressed: () => unawaited(_addRepository()),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_circle_outline, size: 18),
                          SizedBox(width: 8),
                          Text('Add Repository'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Repositories List
        for (final repo in state.repos)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LayoutConstants.spacingMd,
              vertical: LayoutConstants.spacingXs,
            ),
            child: _RepoCard(repo: repo),
          ),
      ],
    );
  }
}

String _relativeTime(DateTime? time) {
  if (time == null) return 'never';
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class _RepoCard extends ConsumerStatefulWidget {
  final NuvioRepo repo;
  const _RepoCard({required this.repo});

  @override
  ConsumerState<_RepoCard> createState() => _RepoCardState();
}

class _RepoCardState extends ConsumerState<_RepoCard> {
  bool _isExpanded = true;
  List<GamepadHint>? _repoHints;

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    final summary = await ref
        .read(nuvioRepositoryProvider.notifier)
        .refreshRepository(widget.repo.manifestUrl, silent: true);
    ref.read(nuvioStreamServiceProvider).clearCache();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          summary == null
              ? 'Could not reach that repository'
              : (summary.hasChanges ? summary.label : 'Already up to date'),
        ),
      ),
    );
  }

  void _confirmDeleteRepo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: Text('Remove ${widget.repo.displayName}?'),
        content: const Text(
          'This will remove the repository and disable all its scraper plugins from source extraction.',
        ),
        actions: [
          CustomButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: LayoutConstants.spacingXs),
          CustomButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              unawaited(
                ref
                    .read(nuvioRepositoryProvider.notifier)
                    .removeRepository(widget.repo.manifestUrl),
              );
            },
            child: Text(
              'Remove',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final manifest = repo.manifest;
    final scrapers = manifest?.scrapers ?? const <NuvioScraperInfo>[];
    final update = repo.lastUpdate;
    final changed = update?.changedScraperIds ?? const <String>{};

    final isTv = ref.watch(deviceProfileProvider).asData?.value.isTv ?? false;
    final isBigPicture = ref.watch(bigPictureModeProvider).isEnabled || isTv;

    final anyDisabled = scrapers.any((s) => !widget.repo.isScraperEnabled(s));
    final toggleAction = anyDisabled ? true : false;
    final toggleLabel = anyDisabled ? 'Enable all' : 'Disable all';
    final toggleIcon = anyDisabled
        ? Icons.check_circle_outline
        : Icons.cancel_outlined;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.5),
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActionTile(
            title: repo.displayName,
            subtitle:
                '${scrapers.length} scrapers · checked ${_relativeTime(repo.lastCheckedAt)}'
                '${repo.lastUpdatedAt != null ? ' · updated ${_relativeTime(repo.lastUpdatedAt)}' : ''}',
            trailing: AnimatedRotation(
              turns: _isExpanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: cs.onSurfaceVariant,
              ),
            ),
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            onSecondaryTap: () => unawaited(_refresh()),
            onTertiaryTap: () => _confirmDeleteRepo(context),
            onLeftTriggerTap: () => unawaited(
              ref
                  .read(nuvioRepositoryProvider.notifier)
                  .setAllScrapersEnabled(repo.manifestUrl, toggleAction),
            ),
            onFocusChange: (f) {
              if (f && isBigPicture) {
                _repoHints = [
                  GamepadHint(
                    buttonLabel: 'A',
                    actionLabel: _isExpanded ? 'Collapse' : 'Expand',
                    buttonColor: Colors.greenAccent.shade400,
                  ),
                  GamepadHint(
                    buttonLabel: 'X',
                    actionLabel: 'Refresh',
                    buttonColor: Colors.blueAccent.shade400,
                  ),
                  GamepadHint(
                    buttonLabel: 'Y',
                    actionLabel: 'Remove',
                    buttonColor: Colors.redAccent.shade400,
                  ),
                  GamepadHint(
                    buttonLabel: 'LT',
                    actionLabel: toggleLabel,
                    buttonColor: Colors.grey.shade400,
                  ),
                ];
                ref.read(focusedGamepadHintsProvider.notifier).state =
                    _repoHints;
              } else if (!f && isBigPicture) {
                Future.microtask(() {
                  if (mounted &&
                      ref.read(focusedGamepadHintsProvider) == _repoHints) {
                    ref.read(focusedGamepadHintsProvider.notifier).state = null;
                  }
                });
              }
            },
          ),

          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: !_isExpanded
                ? const SizedBox.shrink()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!isBigPicture)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: LayoutConstants.spacingMd,
                            vertical: LayoutConstants.spacingXs,
                          ),
                          child: Row(
                            children: [
                              CustomButton(
                                onPressed: () => unawaited(
                                  ref
                                      .read(nuvioRepositoryProvider.notifier)
                                      .setAllScrapersEnabled(
                                        repo.manifestUrl,
                                        toggleAction,
                                      ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(toggleIcon, size: 16),
                                    const SizedBox(width: 6),
                                    Text(toggleLabel),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              _TvIconButton(
                                tooltip: 'Refresh Repository',
                                icon: Icons.refresh_rounded,
                                onPressed: repo.isRefreshing
                                    ? null
                                    : () => unawaited(_refresh()),
                              ),
                              _TvIconButton(
                                tooltip: 'Remove Repository',
                                icon: Icons.delete_outline,
                                color: cs.error,
                                onPressed: () => _confirmDeleteRepo(context),
                              ),
                            ],
                          ),
                        ),

                      Divider(
                        height: 1,
                        color: theme.dividerColor.withValues(alpha: 0.5),
                      ),

                      if (update != null && update.hasChanges)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: LayoutConstants.spacingMd,
                            vertical: LayoutConstants.spacingXs,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.new_releases_outlined,
                                size: 16,
                                color: cs.tertiary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  update.label,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.tertiary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (repo.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: LayoutConstants.spacingMd,
                            vertical: LayoutConstants.spacingXs,
                          ),
                          child: Text(
                            repo.errorMessage!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.error,
                            ),
                          ),
                        ),

                      // Scrapers inside this repo
                      for (int i = 0; i < scrapers.length; i++) ...[
                        _ScraperTile(
                          repo: repo,
                          scraper: scrapers[i],
                          justUpdated: changed.contains(scrapers[i].id),
                          previousVersion: update?.updated
                              .where(
                                (entry) => entry.scraper.id == scrapers[i].id,
                              )
                              .map((entry) => entry.from)
                              .firstOrNull,
                        ),
                        if (i < scrapers.length - 1)
                          Divider(
                            height: 1,
                            indent: 64,
                            endIndent: LayoutConstants.spacingMd,
                            color: theme.dividerColor.withValues(alpha: 0.5),
                          ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScraperTile extends ConsumerStatefulWidget {
  final NuvioRepo repo;
  final NuvioScraperInfo scraper;
  final bool justUpdated;
  final String? previousVersion;

  const _ScraperTile({
    required this.repo,
    required this.scraper,
    this.justUpdated = false,
    this.previousVersion,
  });

  @override
  ConsumerState<_ScraperTile> createState() => _ScraperTileState();
}

class _ScraperTileState extends ConsumerState<_ScraperTile> {
  bool _testing = false;
  // ignore: unused_field
  String? _testResult;
  List<GamepadHint>? _myHints;

  static const String _testTmdbId = '603'; // The Matrix

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final repository = ref.read(nuvioRepositoryProvider.notifier);
    final runtime = ref.read(nuvioRuntimeProvider);
    try {
      final code = await repository.codeFor(widget.repo, widget.scraper);
      final settings = widget.scraper.hasSettings
          ? await repository.scraperSettings(widget.scraper.id)
          : const <String, dynamic>{};
      final type = widget.scraper.supportsType('movie') ? 'movie' : 'tv';
      final results = await runtime.run(
        code: code,
        scraperId: widget.scraper.id,
        scraperName: widget.scraper.name,
        tmdbId: _testTmdbId,
        mediaType: type,
        season: type == 'tv' ? 1 : null,
        episode: type == 'tv' ? 1 : null,
        settings: settings,
      );
      if (!mounted) return;
      setState(() {
        _testResult = results.isEmpty
            ? 'No streams returned for test title'
            : '${results.length} streams found · ${results.first.label}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _testResult = 'Test failed: $error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _openSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(nuvioRepositoryProvider.notifier);
    final runtime = ref.read(nuvioRuntimeProvider);
    List<NuvioSettingsField> layout;
    Map<String, dynamic> saved;
    try {
      final code = await repository.codeFor(widget.repo, widget.scraper);
      saved = await repository.scraperSettings(widget.scraper.id);
      layout = await runtime.settingsLayout(
        code: code,
        scraperId: widget.scraper.id,
        settings: saved,
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not read settings: $error')),
      );
      return;
    }
    if (!mounted) return;
    if (layout.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('This scraper exposes no configuration options'),
        ),
      );
      return;
    }

    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => NuvioScraperSettingsDialog(
        scraperName: widget.scraper.name,
        fields: layout,
        initialValues: saved,
      ),
    );
    if (values == null) return;
    await repository.saveScraperSettings(widget.scraper.id, values);
    ref.read(nuvioStreamServiceProvider).clearCache();
    messenger.showSnackBar(
      SnackBar(content: Text('${widget.scraper.name} settings saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scraper = widget.scraper;
    final theme = Theme.of(context);
    // ignore: unused_local_variable
    final cs = theme.colorScheme;
    final enabled = widget.repo.isScraperEnabled(scraper);
    final unsupported = !scraper.isSupportedOn(NuvioRepository.platformName);

    final isTv = ref.watch(deviceProfileProvider).asData?.value.isTv ?? false;
    final isBigPicture = ref.watch(bigPictureModeProvider).isEnabled || isTv;

    final typeChips = scraper.supportedTypes
        .map(NuvioScraperInfo.normalizeType)
        .toSet()
        .join(' / ');
    final languages = scraper.contentLanguage.take(3).join(', ');
    final formats = scraper.formats.take(3).join(' / ');

    // ignore: unused_local_variable
    final metaList = [
      if (typeChips.isNotEmpty) typeChips.toUpperCase(),
      if (languages.isNotEmpty) languages.toUpperCase(),
      if (formats.isNotEmpty) formats.toUpperCase(),
    ];

    void handleToggle() {
      if (unsupported) return;
      ref
          .read(nuvioRepositoryProvider.notifier)
          .setScraperEnabled(widget.repo.manifestUrl, scraper.id, !enabled);
    }

    return _ActionTile(
      title: scraper.name,
      subtitle: '', // Not used natively by custom content
      leading: _ScraperLogo(url: scraper.logo, name: scraper.name),
      trailing: isBigPicture
          ? ExcludeFocus(
              child: CustomSwitch(
                value: enabled && !unsupported,
                onChanged: (_) => handleToggle(),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (scraper.hasSettings)
                  _TvIconButton(
                    tooltip: '${scraper.name} Settings',
                    icon: Icons.settings_outlined,
                    onPressed: () => unawaited(_openSettings()),
                  ),
                _TvIconButton(
                  tooltip: 'Test Scraper',
                  icon: Icons.play_circle_outline_rounded,
                  customIcon: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: AppLoadingIndicator(
                            constraints: BoxConstraints(
                              maxWidth: 18,
                              maxHeight: 18,
                            ),
                          ),
                        )
                      : null,
                  onPressed: _testing ? null : () => unawaited(_test()),
                ),
                const SizedBox(width: 4),
                CustomSwitch(
                  value: enabled && !unsupported,
                  onChanged: unsupported ? null : (_) => handleToggle(),
                ),
              ],
            ),
      onTap: handleToggle,
      onSecondaryTap: scraper.hasSettings
          ? () => unawaited(_openSettings())
          : null,
      onTertiaryTap: () => unawaited(_test()),
      onFocusChange: (f) {
        if (f && isBigPicture) {
          _myHints = [
            GamepadHint(
              buttonLabel: 'A',
              actionLabel: 'Toggle',
              buttonColor: Colors.greenAccent.shade400,
            ),
            if (scraper.hasSettings)
              GamepadHint(
                buttonLabel: 'X',
                actionLabel: 'Settings',
                buttonColor: Colors.blueAccent.shade400,
              ),
            GamepadHint(
              buttonLabel: 'Y',
              actionLabel: 'Test',
              buttonColor: Colors.amberAccent.shade400,
            ),
          ];
          ref.read(focusedGamepadHintsProvider.notifier).state = _myHints;
        } else if (!f && isBigPicture) {
          Future.microtask(() {
            if (mounted && ref.read(focusedGamepadHintsProvider) == _myHints) {
              ref.read(focusedGamepadHintsProvider.notifier).state = null;
            }
          });
        }
      },
    );
  }
}

class _TvIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final Widget? customIcon;

  const _TvIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.customIcon,
  });

  @override
  State<_TvIconButton> createState() => _TvIconButtonState();
}

class _TvIconButtonState extends State<_TvIconButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;
    final enabled = widget.onPressed != null;

    return Focus(
      canRequestFocus: enabled,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (!enabled) return KeyEventResult.ignored;
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onPressed!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Tooltip(
        message: widget.tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isFocused
                ? (widget.color ?? primary).withValues(alpha: 0.2)
                : Colors.transparent,
            border: _isFocused
                ? Border.all(color: widget.color ?? primary, width: 2)
                : null,
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: (widget.color ?? primary).withValues(alpha: 0.5),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onPressed,
              child: Center(
                child:
                    widget.customIcon ??
                    Icon(
                      widget.icon,
                      size: 20,
                      color: _isFocused
                          ? (widget.color ?? primary)
                          : (widget.color ?? cs.onSurfaceVariant),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScraperLogo extends StatelessWidget {
  final String? url;
  final String name;
  const _ScraperLogo({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final letter = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    final fallback = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        letter,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    final logo = url;
    if (logo == null || logo.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        logo,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

// ignore: unused_element
class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FocusableCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;

  const _FocusableCard({required this.child, this.margin});

  @override
  State<_FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<_FocusableCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin:
            widget.margin ?? const EdgeInsets.all(LayoutConstants.spacingMd),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isFocused
                ? theme.colorScheme.primary
                : theme.dividerColor.withValues(alpha: 0.5),
            width: _isFocused ? 2.0 : 1.0,
          ),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(color: Colors.transparent, child: widget.child),
      ),
    );
  }
}
