import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/input/gamepad_actions.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/addons/data/addon_repository.dart';
import '../../../../core/addons/data/debrid_service.dart';
import '../../../../core/addons/models/addon_manifest.dart';
import '../../../../core/services/notification_service.dart';

class AddonPreset {
  final String name;
  final String description;
  final String url;
  final IconData icon;

  const AddonPreset({
    required this.name,
    required this.description,
    required this.url,
    required this.icon,
  });
}

const List<AddonPreset> kAddonPresets = [
  AddonPreset(
    name: 'Cinemeta',
    description: 'Official movie & series catalogs and metadata',
    url: 'https://v3-cinemeta.strem.io/manifest.json',
    icon: Icons.movie_filter_rounded,
  ),
  AddonPreset(
    name: 'Torrentio',
    description: 'Torrent streams from public trackers',
    url: 'https://torrentio.strem.fun/manifest.json',
    icon: Icons.bolt_rounded,
  ),
  AddonPreset(
    name: 'OpenSubtitles v3',
    description: 'Subtitles in 60+ languages',
    url: 'https://opensubtitles-v3.strem.io/manifest.json',
    icon: Icons.subtitles_rounded,
  ),
  AddonPreset(
    name: 'WatchHub',
    description: 'Where to watch: Netflix, Prime, Plex… (opens the service)',
    url: 'https://watchhub.strem.io/manifest.json',
    icon: Icons.open_in_new_rounded,
  ),
  AddonPreset(
    name: 'MediaFusion',
    description: 'Streams from many sources, debrid-friendly',
    url: 'https://mediafusion.elfhosted.com/manifest.json',
    icon: Icons.hub_rounded,
  ),
  AddonPreset(
    name: 'Comet',
    description: 'Torrent + debrid streams',
    url: 'https://comet.elfhosted.com/manifest.json',
    icon: Icons.bolt_outlined,
  ),
  AddonPreset(
    name: 'Streaming Catalogs',
    description: 'Netflix, Disney+, HBO… catalogs (browse only, no streams)',
    url:
        'https://7a82163c306e-stremio-netflix-catalog-addon.baby-beamup.club/manifest.json',
    icon: Icons.grid_view_rounded,
  ),
];

class AddonManageView extends ConsumerStatefulWidget {
  final FocusNode? firstActionFocusNode;
  const AddonManageView({super.key, this.firstActionFocusNode});

  @override
  ConsumerState<AddonManageView> createState() => _AddonManageViewState();
}

class _AddonManageViewState extends ConsumerState<AddonManageView> {
  final Set<String> _busy = {};

  Future<void> _install(String url, {String? label}) async {
    setState(() => _busy.add(url));
    try {
      final addon = await ref
          .read(addonRepositoryProvider.notifier)
          .install(url);
      ref
          .read(notificationServiceProvider)
          .showSuccess('Installed ${addon.displayName}');
    } catch (error) {
      ref
          .read(notificationServiceProvider)
          .showError('Could not install ${label ?? url}: $error');
    } finally {
      if (mounted) setState(() => _busy.remove(url));
    }
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add an add-on'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste a manifest URL. stremio:// links and configured URLs '
              '(with ?query settings) work too.',
            ),
            const SizedBox(height: 14),
            Actions(
              actions: {
                GamepadDirectionalIntent:
                    CallbackAction<GamepadDirectionalIntent>(
                      onInvoke: (intent) {
                        if (intent.direction == TraversalDirection.down) {
                          FocusManager.instance.primaryFocus?.nextFocus();
                          return null;
                        }
                        return null;
                      },
                    ),
              },
              child: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'https://example.strem.io/manifest.json',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Paste',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      final text = data?.text;
                      if (text != null) controller.text = text.trim();
                    },
                  ),
                ),
                onSubmitted: (value) =>
                    Navigator.pop(dialogContext, value.trim()),
              ),
            ),
          ],
        ),
        actions: [
          _DpadDialogButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(dialogContext),
            isPrimary: false,
          ),
          _DpadDialogButton(
            label: 'Install',
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            isPrimary: true,
          ),
        ],
      ),
    );

    if (url != null && url.isNotEmpty) await _install(url);
  }

  Future<void> _confirmRemove(ManagedAddon addon) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${addon.displayName}?'),
        content: const Text(
          'Its catalogs, metadata and streams will no longer appear.',
        ),
        actions: [
          _DpadDialogButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(dialogContext, false),
            isPrimary: false,
          ),
          _DpadDialogButton(
            label: 'Remove',
            onPressed: () => Navigator.pop(dialogContext, true),
            isPrimary: true,
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref
          .read(addonRepositoryProvider.notifier)
          .remove(addon.manifestUrl);
      ref
          .read(notificationServiceProvider)
          .showInfo('Removed ${addon.displayName}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addonRepositoryProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dashboard_customize_rounded, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Add-ons Management',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Add-ons provide catalogs, metadata, streams and subtitles. '
                  'The first enabled add-on that answers a query wins.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    DpadFocusable(
                      focusNode: widget.firstActionFocusNode,
                      onSelect: () => unawaited(_showAddDialog()),
                      child: const SizedBox.shrink(),
                      builder: (context, focusState, _) {
                        final isFocused = focusState.focused;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isFocused
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: FilledButton.icon(
                            onPressed: () => unawaited(_showAddDialog()),
                            icon: const Icon(Icons.add_link_rounded),
                            label: const Text('Add add-on URL'),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    DpadFocusable(
                      onSelect: () {
                        unawaited(
                          ref
                              .read(addonRepositoryProvider.notifier)
                              .refreshAll(),
                        );
                        ref
                            .read(notificationServiceProvider)
                            .showInfo('Refreshing manifests...');
                      },
                      child: const SizedBox.shrink(),
                      builder: (context, focusState, _) {
                        final isFocused = focusState.focused;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isFocused
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: FilledButton.tonalIcon(
                            onPressed: () {
                              unawaited(
                                ref
                                    .read(addonRepositoryProvider.notifier)
                                    .refreshAll(),
                              );
                              ref
                                  .read(notificationServiceProvider)
                                  .showInfo('Refreshing manifests...');
                            },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Refresh manifests'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        Text(
          'Quick Install',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),

        // <--- FIXED: Replaced Wrap with a horizontal ListView for perfect D-pad traversal
        SizedBox(
          height: 50,
          child: FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kAddonPresets.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final preset = kAddonPresets[index];
                return Center(
                  child: DpadFocusable(
                    onSelect: _busy.contains(preset.url)
                        ? null
                        : () => unawaited(
                            _install(preset.url, label: preset.name),
                          ),
                    child: const SizedBox.shrink(),
                    builder: (context, focusState, _) {
                      final isFocused = focusState.focused;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isFocused
                                ? Colors.white
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ActionChip(
                          avatar: _busy.contains(preset.url)
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(preset.icon, size: 18),
                          label: Text(preset.name),
                          tooltip: preset.description,
                          onPressed: _busy.contains(preset.url)
                              ? null
                              : () => unawaited(
                                  _install(preset.url, label: preset.name),
                                ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 20),

        const _DebridCard(),
        const SizedBox(height: 20),

        Row(
          children: [
            Text(
              'Installed (${state.addons.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (state.isLoading && state.addons.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!state.isLoading && state.addons.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'Nothing installed yet. Cinemeta gives you catalogs, Torrentio gives you streams.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        for (int i = 0; i < state.addons.length; i++) ...[
          _AddonTile(
            key: ValueKey(state.addons[i].manifestUrl),
            addon: state.addons[i],
            index: i,
            isFirst: i == 0,
            isLast: i == state.addons.length - 1,
            onToggle: (value) => unawaited(
              ref
                  .read(addonRepositoryProvider.notifier)
                  .setEnabled(state.addons[i].manifestUrl, value),
            ),
            onRemove: () => unawaited(_confirmRemove(state.addons[i])),
            onMoveUp: i > 0
                ? () => unawaited(
                    ref
                        .read(addonRepositoryProvider.notifier)
                        .reorder(i, i - 1),
                  )
                : null,
            onMoveDown: i < state.addons.length - 1
                ? () => unawaited(
                    ref
                        .read(addonRepositoryProvider.notifier)
                        .reorder(i, i + 2),
                  )
                : null,
            onConfigure: () async {
              final configureUrl = AddonTransport.baseUrl(
                state.addons[i].manifestUrl,
              );
              final uri = Uri.tryParse('$configureUrl/configure');
              if (uri == null) return;
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ],
    );
  }
}

class _AddonTile extends StatefulWidget {
  final ManagedAddon addon;
  final int index;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;
  final Future<void> Function() onConfigure;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _AddonTile({
    super.key,
    required this.addon,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.onToggle,
    required this.onRemove,
    required this.onConfigure,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  State<_AddonTile> createState() => _AddonTileState();
}

class _AddonTileState extends State<_AddonTile> {
  late final FocusNode _tileFocusNode;

  @override
  void initState() {
    super.initState();
    _tileFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _tileFocusNode.dispose();
    super.dispose();
  }

  Future<void> _showOptionsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.addon.displayName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              autofocus: true,
              leading: Icon(
                widget.addon.enabled ? Icons.toggle_on : Icons.toggle_off,
                color: widget.addon.enabled ? Colors.green : null,
              ),
              title: Text(widget.addon.enabled ? 'Disable' : 'Enable'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onToggle(!widget.addon.enabled);
              },
            ),
            if (widget.onMoveUp != null)
              ListTile(
                leading: const Icon(Icons.arrow_upward_rounded),
                title: const Text('Move Priority Up'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onMoveUp!();
                },
              ),
            if (widget.onMoveDown != null)
              ListTile(
                leading: const Icon(Icons.arrow_downward_rounded),
                title: const Text('Move Priority Down'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onMoveDown!();
                },
              ),
            if (widget.addon.manifest?.behaviorHints.configurable ?? false)
              ListTile(
                leading: const Icon(Icons.open_in_browser_rounded),
                title: const Text('Configure in Browser'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onConfigure();
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
              ),
              title: const Text(
                'Uninstall',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(ctx);
                widget.onRemove();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final manifest = widget.addon.manifest;
    final resources =
        manifest?.resources.map((r) => r.name).toList() ?? const [];

    return DpadFocusable(
      focusNode: _tileFocusNode,
      onSelect: _showOptionsDialog,
      child: const SizedBox.shrink(),
      builder: (context, focusState, _) {
        final isTileFocused = focusState.focused;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isTileFocused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _showOptionsDialog,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(
                  children: [
                    if (manifest?.logoUrl != null &&
                        manifest!.logoUrl!.startsWith('http'))
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            manifest.logoUrl!,
                            width: 42,
                            height: 42,
                            fit: BoxFit.cover,
                            cacheWidth: 96,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.extension_rounded, size: 32),
                          ),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(right: 14),
                        child: Icon(Icons.extension_rounded, size: 32),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.addon.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'v${manifest?.version ?? '?'}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          if ((manifest?.description ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                manifest!.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          if (widget.addon.errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                widget.addon.errorMessage!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.error,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final resource in resources)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer.withValues(
                                      alpha: 0.6,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    resource,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: cs.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Switch(
                          value: widget.addon.enabled,
                          onChanged: (v) => widget.onToggle(v),
                        ),
                        if (isTileFocused)
                          const Padding(
                            padding: EdgeInsets.only(top: 4.0, right: 8.0),
                            child: Text(
                              'Press A for Options',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DebridApiKeyDialog extends StatefulWidget {
  final DebridProvider provider;
  final String initialKey;

  const _DebridApiKeyDialog({required this.provider, required this.initialKey});

  @override
  State<_DebridApiKeyDialog> createState() => _DebridApiKeyDialogState();
}

class _DebridApiKeyDialogState extends State<_DebridApiKeyDialog> {
  late final TextEditingController _controller;
  late final FocusNode _textFocusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialKey);
    _textFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.key_rounded),
          const SizedBox(width: 8),
          Text('${widget.provider.label} API Key'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paste your ${widget.provider.label} API key / token to enable instant debrid link resolving.',
          ),
          const SizedBox(height: 14),
          Actions(
            actions: {
              GamepadDirectionalIntent:
                  CallbackAction<GamepadDirectionalIntent>(
                    onInvoke: (intent) {
                      if (intent.direction == TraversalDirection.down) {
                        FocusManager.instance.primaryFocus?.nextFocus();
                        return null;
                      }
                      return null;
                    },
                  ),
            },
            child: TextField(
              controller: _controller,
              focusNode: _textFocusNode,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'API Key / Token',
                suffixIcon: IconButton(
                  tooltip: 'Paste from clipboard',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    final text = data?.text;
                    if (text != null && mounted) {
                      _controller.text = text.trim();
                    }
                  },
                ),
              ),
              onSubmitted: (text) => Navigator.pop(context, text.trim()),
            ),
          ),
        ],
      ),
      actions: [
        _DpadDialogButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
          isPrimary: false,
        ),
        _DpadDialogButton(
          label: 'Paste',
          icon: Icons.content_paste_rounded,
          onPressed: () async {
            final data = await Clipboard.getData('text/plain');
            final text = data?.text;
            if (text != null && mounted) {
              _controller.text = text.trim();
            }
          },
          isPrimary: false,
        ),
        _DpadDialogButton(
          label: 'Save Key',
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          isPrimary: true,
        ),
      ],
    );
  }
}

class _DebridCard extends ConsumerStatefulWidget {
  const _DebridCard();

  @override
  ConsumerState<_DebridCard> createState() => _DebridCardState();
}

class _DebridCardState extends ConsumerState<_DebridCard> {
  final TextEditingController _keyController = TextEditingController();
  DebridProvider _provider = DebridProvider.none;
  bool _saving = false;
  bool _initialised = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _showProviderDialog() async {
    final selected = await showDialog<DebridProvider>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Debrid Provider'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: DebridProvider.values.length,
              itemBuilder: (context, index) {
                final provider = DebridProvider.values[index];
                return ListTile(
                  autofocus:
                      _provider == provider, // Auto-focuses the current one!
                  title: Text(provider.label),
                  onTap: () => Navigator.pop(context, provider),
                  trailing: _provider == provider
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.green,
                        )
                      : null,
                );
              },
            ),
          ),
          actions: [
            _DpadDialogButton(
              label: 'Cancel',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => _provider = selected);
    }
  }

  Future<void> _openApiKeyDialog() async {
    final key = await showDialog<String>(
      context: context,
      builder: (context) => _DebridApiKeyDialog(
        provider: _provider,
        initialKey: _keyController.text,
      ),
    );

    if (key != null && mounted) {
      setState(() {
        _keyController.text = key;
      });
      if (key.isNotEmpty) {
        await _save();
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final username = await ref
          .read(debridSettingsProvider.notifier)
          .save(_provider, _keyController.text);
      ref
          .read(notificationServiceProvider)
          .showSuccess(
            _provider == DebridProvider.none
                ? 'Debrid disabled'
                : 'Connected to ${_provider.label}${username == null ? '' : ' as $username'}',
          );
    } catch (error) {
      ref.read(notificationServiceProvider).showError('Debrid error: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(debridSettingsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!_initialised && !config.isLoading) {
      _initialised = true;
      _provider = config.provider;
      _keyController.text = config.apiKey;
    }

    final hasKey = _keyController.text.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flash_on_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Debrid Service (Optional)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (config.username != null)
                  Chip(
                    avatar: const Icon(Icons.check_rounded, size: 16),
                    label: Text(config.username!),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Play torrent results as instant direct links without peer-to-peer wait times.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            DpadFocusable(
              onSelect: _showProviderDialog,
              child: const SizedBox.shrink(),
              builder: (context, focusState, _) {
                final isFocused = focusState.focused;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isFocused ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: OutlinedButton.icon(
                    onPressed: _showProviderDialog,
                    icon: const Icon(Icons.dns_rounded),
                    label: Text(_provider.label),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                  ),
                );
              },
            ),

            if (_provider != DebridProvider.none) ...[
              const SizedBox(height: 12),
              DpadFocusable(
                onSelect: _openApiKeyDialog,
                child: const SizedBox.shrink(),
                builder: (context, focusState, _) {
                  final isFocused = focusState.focused;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isFocused ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: OutlinedButton.icon(
                      onPressed: _openApiKeyDialog,
                      icon: Icon(
                        hasKey
                            ? Icons.check_circle_outline_rounded
                            : Icons.key_rounded,
                        color: hasKey ? Colors.green : cs.primary,
                      ),
                      label: Text(
                        hasKey
                            ? 'API Key Configured (Tap to change)'
                            : 'Enter API Key',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: hasKey ? cs.onSurface : cs.primary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
            if (config.error != null) ...[
              const SizedBox(height: 8),
              Text(
                config.error!,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                DpadFocusable(
                  onSelect: _saving ? null : () => unawaited(_save()),
                  child: const SizedBox.shrink(),
                  builder: (context, focusState, _) {
                    final isFocused = focusState.focused;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isFocused ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: FilledButton.icon(
                        onPressed: _saving ? null : () => unawaited(_save()),
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.link_rounded),
                        label: Text(
                          _provider == DebridProvider.none
                              ? 'Disable'
                              : 'Connect',
                        ),
                      ),
                    );
                  },
                ),
                if (config.isConfigured) ...[
                  const SizedBox(width: 10),
                  DpadFocusable(
                    onSelect: _saving
                        ? null
                        : () async {
                            await ref
                                .read(debridSettingsProvider.notifier)
                                .clear();
                            if (!context.mounted) return;
                            setState(() {
                              _provider = DebridProvider.none;
                              _keyController.clear();
                            });
                          },
                    child: const SizedBox.shrink(),
                    builder: (context, focusState, _) {
                      final isFocused = focusState.focused;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isFocused
                                ? Colors.white
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: TextButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  await ref
                                      .read(debridSettingsProvider.notifier)
                                      .clear();
                                  if (!context.mounted) return;
                                  setState(() {
                                    _provider = DebridProvider.none;
                                    _keyController.clear();
                                  });
                                },
                          icon: const Icon(
                            Icons.link_off_rounded,
                            color: Colors.redAccent,
                          ),
                          label: const Text(
                            'Disconnect',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DpadDialogButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final IconData? icon;

  const _DpadDialogButton({
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DpadFocusable(
      onSelect: onPressed,
      child: const SizedBox.shrink(),
      builder: (context, state, _) {
        final isFocused = state.focused;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isFocused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: isPrimary
              ? (icon != null
                    ? FilledButton.icon(
                        onPressed: onPressed,
                        icon: Icon(icon, size: 18),
                        label: Text(label),
                        style: FilledButton.styleFrom(
                          backgroundColor: isFocused ? cs.primary : null,
                        ),
                      )
                    : FilledButton(
                        onPressed: onPressed,
                        style: FilledButton.styleFrom(
                          backgroundColor: isFocused ? cs.primary : null,
                        ),
                        child: Text(label),
                      ))
              : (icon != null
                    ? TextButton.icon(
                        onPressed: onPressed,
                        icon: Icon(icon, size: 18),
                        label: Text(label),
                        style: TextButton.styleFrom(
                          backgroundColor: isFocused
                              ? cs.surfaceContainerHighest
                              : Colors.transparent,
                        ),
                      )
                    : TextButton(
                        onPressed: onPressed,
                        style: TextButton.styleFrom(
                          backgroundColor: isFocused
                              ? cs.surfaceContainerHighest
                              : Colors.transparent,
                        ),
                        child: Text(label),
                      )),
        );
      },
    );
  }
}
