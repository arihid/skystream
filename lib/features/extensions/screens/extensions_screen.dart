import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/utils/responsive_breakpoints.dart';
import '../../../core/utils/layout_constants.dart';
import '../../../core/providers/device_info_provider.dart';
import '../../../core/extensions/models/extension_plugin.dart';
import '../../../core/extensions/models/extension_repository.dart';
import '../../../core/extensions/extension_manager.dart';
import '../../../shared/widgets/custom_widgets.dart';
import '../providers/extensions_controller.dart';
import 'plugin_settings_screen.dart';
import '../../../shared/widgets/loading_indicator.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

import '../../../shared/widgets/gamepad_hints_overlay.dart';
import 'package:skystream/core/input/gamepad_actions.dart'; 

class ExtensionsScreen extends ConsumerStatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  ConsumerState<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends ConsumerState<ExtensionsScreen> with TickerProviderStateMixin {
  bool _didEnsureInit = false;
  late TabController _tabController;
  
  final FocusNode _installedFocusNode = FocusNode();
  final FocusNode _reposFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (_tabController.index == 0) {
          _installedFocusNode.requestFocus();
        } else {
          _reposFocusNode.requestFocus();
        }
      }
    });
  }

  void _switchTab(int index) {
    _tabController.animateTo(index);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (index == 0) {
        _installedFocusNode.requestFocus();
      } else {
        _reposFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _installedFocusNode.dispose();
    _reposFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!_didEnsureInit) {
      _didEnsureInit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(extensionsControllerProvider.notifier).ensureInitialized();
      });
    }

    ref.listen(extensionsControllerProvider, (previous, next) {
      if (next is ExtensionsError && (previous is! ExtensionsError || previous.message != next.message)) {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.error),
            content: Text(next.message),
            actions: [
              TextButton(
                autofocus: true, 
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.ok),
              ),
            ],
          ),
        );
      }
    });

    final state = ref.watch(extensionsControllerProvider);

    return switch (state) {
      ExtensionsLoading(repositories: []) => Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false, 
            title: Text(l10n.extensions)
          ),
          body: const Center(child: AppLoadingIndicator()),
        ),
      _ => Actions(
            actions: <Type, Action<Intent>>{
              AppLeftBumperIntent: CallbackAction<AppLeftBumperIntent>(
                onInvoke: (_) {
                  _switchTab(_tabController.index == 0 ? 1 : 0);
                  return null;
                }
              ),
              AppRightBumperIntent: CallbackAction<AppRightBumperIntent>(
                onInvoke: (_) {
                  _switchTab(_tabController.index == 1 ? 0 : 1);
                  return null;
                }
              ),
            },
            child: Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                title: Text(l10n.extensions),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: ExcludeFocus(
                    child: TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.label,
                      indicatorWeight: 3,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                      labelColor: Theme.of(context).colorScheme.primary,
                      unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      indicatorColor: Theme.of(context).colorScheme.primary,
                      dividerColor: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                      tabs: [
                        Tab(text: l10n.installed),
                        Tab(text: l10n.repositories),
                      ],
                    ),
                  ),
                ),
              ),
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: TabBarView(
                    controller: _tabController,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildInstalledTab(context, ref, state),
                      _buildRepositoriesTab(context, ref, state),
                    ],
                  ),
                ),
              ),
            ),
          ),
    };
  }

  Widget _buildInstalledTab(BuildContext context, WidgetRef ref, ExtensionsState state) {
    final l10n = AppLocalizations.of(context)!;
    final debugPlugins = state.installedPlugins.where((p) => p.isDebug).toList();
    final hasDebug = debugPlugins.isNotEmpty;

    final allAvailablePackageNames = state.availablePlugins.values.expand((list) => list).map((p) => p.packageName).toSet();

    final installedPlugins = state.installedPlugins
        .where((p) => !p.isDebug && (state.availablePlugins.isEmpty || allAvailablePackageNames.contains(p.packageName)))
        .toList();

    final installedOnlyPlugins = state.installedPlugins
        .where((p) => !p.isDebug && state.availablePlugins.isNotEmpty && !allAvailablePackageNames.contains(p.packageName))
        .toList();
    final hasInstalledOnly = installedOnlyPlugins.isNotEmpty;

    if (state.installedPlugins.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(LayoutConstants.spacingLg),
        children: [
          const SizedBox(height: LayoutConstants.spacingLg),
          _SectionCard(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(LayoutConstants.spacingLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.extension_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: LayoutConstants.spacingMd),
                  Text(l10n.noExtensionsInstalled, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: LayoutConstants.spacingSm),
                  Text(l10n.browseRepositoriesToInstall, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                  const SizedBox(height: LayoutConstants.spacingLg),
                  FilledButton.icon(
                    focusNode: _installedFocusNode,
                    onFocusChange: (f) {
                      if (f && mounted) {
                        ref.read(focusedGamepadHintsProvider.notifier).state = [
                          GamepadHint(buttonLabel: 'LB', actionLabel: 'Prev Tab', buttonColor: Colors.grey.shade400),
                          GamepadHint(buttonLabel: 'RB', actionLabel: 'Next Tab', buttonColor: Colors.grey.shade400),
                          GamepadHint(buttonLabel: 'A', actionLabel: 'Browse', buttonColor: Colors.greenAccent.shade400),
                        ];
                      }
                    },
                    icon: const Icon(Icons.explore_outlined),
                    label: Text(l10n.browseRepositories),
                    onPressed: () => _switchTab(1),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    ExtensionPlugin? firstPlugin;
    if (hasDebug) firstPlugin = debugPlugins.first;
    else if (installedPlugins.isNotEmpty) firstPlugin = installedPlugins.first;
    else if (installedOnlyPlugins.isNotEmpty) firstPlugin = installedOnlyPlugins.first;

    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(), 
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24, top: LayoutConstants.spacingMd),
        addAutomaticKeepAlives: false,
        children: [
          if (hasDebug) _buildDebugSection(context, debugPlugins, firstPlugin),
          _buildInstalledSection(context, ref, installedPlugins, firstPlugin),
          if (hasInstalledOnly)
            _buildInstalledOnlySection(context, ref, installedOnlyPlugins, state.repositories.isNotEmpty, firstPlugin),
        ],
      ),
    );
  }

  Widget _buildRepositoriesTab(BuildContext context, WidgetRef ref, ExtensionsState state) {
    final l10n = AppLocalizations.of(context)!;
    final isEmpty = state.repositories.isEmpty;

    if (isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(LayoutConstants.spacingLg),
        children: [
          const SizedBox(height: LayoutConstants.spacingLg),
          _SectionCard(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(LayoutConstants.spacingLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.snippet_folder_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: LayoutConstants.spacingMd),
                  Text(l10n.noReposFound, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: LayoutConstants.spacingSm),
                  Text(l10n.addRepoDescription, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                  const SizedBox(height: LayoutConstants.spacingLg),
                  FilledButton.icon(
                    focusNode: _reposFocusNode,
                    onFocusChange: (f) {
                      if (f && mounted) {
                        ref.read(focusedGamepadHintsProvider.notifier).state = [
                          GamepadHint(buttonLabel: 'LB', actionLabel: 'Prev Tab', buttonColor: Colors.grey.shade400),
                          GamepadHint(buttonLabel: 'RB', actionLabel: 'Next Tab', buttonColor: Colors.grey.shade400),
                          GamepadHint(buttonLabel: 'A', actionLabel: 'Add Repo', buttonColor: Colors.greenAccent.shade400),
                        ];
                      }
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(l10n.addRepository),
                    onPressed: () => _showAddRepoDialog(context, ref),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24, top: LayoutConstants.spacingMd),
        addAutomaticKeepAlives: false,
        itemCount: state.repositories.length + 1,
        itemBuilder: (context, index) {
          if (index < state.repositories.length) {
            final repo = state.repositories[index];
            final plugins = state.availablePlugins[repo.url] ?? [];
            return _RepoTile(
              repo: repo, 
              plugins: plugins, 
              state: state,
              focusNode: index == 0 ? _reposFocusNode : null, 
            ); 
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: LayoutConstants.spacingMd, vertical: LayoutConstants.spacingSm),
            child: _AddRepoTile(
              onTap: () => _showAddRepoDialog(context, ref),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInstalledSection(BuildContext context, WidgetRef ref, List<ExtensionPlugin> plugins, ExtensionPlugin? firstPlugin) {
    if (plugins.isEmpty) return const SizedBox.shrink();

    return _SectionCard(
      margin: const EdgeInsets.symmetric(horizontal: LayoutConstants.spacingMd, vertical: LayoutConstants.spacingXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LayoutConstants.spacingMd, vertical: LayoutConstants.spacingSm + 4),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Theme.of(context).colorScheme.primary, size: 22),
                const SizedBox(width: LayoutConstants.spacingSm),
                Text('Installed Extensions', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
          for (int i = 0; i < plugins.length; i++) ...[
            _PluginTile(
              plugin: plugins[i],
              focusNode: plugins[i] == firstPlugin ? _installedFocusNode : null, 
            ),
            if (i < plugins.length - 1)
              Divider(height: 1, indent: 56, endIndent: 16, color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
          ],
        ],
      ),
    );
  }

  Widget _buildInstalledOnlySection(BuildContext context, WidgetRef ref, List<ExtensionPlugin> plugins, bool hasRepos, ExtensionPlugin? firstPlugin) {
    if (plugins.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return _SectionCard(
      margin: const EdgeInsets.symmetric(horizontal: LayoutConstants.spacingMd, vertical: LayoutConstants.spacingXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LayoutConstants.spacingMd, vertical: LayoutConstants.spacingSm + 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.extension_outlined, color: Theme.of(context).colorScheme.primary, size: 22),
                    const SizedBox(width: LayoutConstants.spacingSm),
                    Text(l10n.extensionsNotInRepos, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(hasRepos ? l10n.noLongerInRepo : l10n.addRepoToBrowse, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
          for (int i = 0; i < plugins.length; i++) ...[
            _PluginTile(
              plugin: plugins[i],
              focusNode: plugins[i] == firstPlugin ? _installedFocusNode : null, 
            ),
            if (i < plugins.length - 1)
              Divider(height: 1, indent: 56, endIndent: 16, color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
          ],
        ],
      ),
    );
  }

  Widget _buildDebugSection(BuildContext context, List<ExtensionPlugin> debugPlugins, ExtensionPlugin? firstPlugin) {
    if (debugPlugins.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return _SectionCard(
      margin: const EdgeInsets.symmetric(horizontal: LayoutConstants.spacingMd, vertical: LayoutConstants.spacingXs),
      borderColor: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LayoutConstants.spacingMd, vertical: LayoutConstants.spacingSm + 4),
            child: Text(l10n.debugExtensions, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.tertiary, fontWeight: FontWeight.bold)),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
          for (int i = 0; i < debugPlugins.length; i++) ...[
            _PluginTile(
              plugin: debugPlugins[i], 
              isDebugSection: true,
              focusNode: debugPlugins[i] == firstPlugin ? _installedFocusNode : null, 
            ),
            if (i < debugPlugins.length - 1)
              Divider(height: 1, indent: 16, endIndent: 16, color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
          ],
        ],
      ),
    );
  }

  void _showAddRepoDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: Text(l10n.addRepository),
        content: CustomTextField(
          controller: controller,
          hintText: l10n.repoUrlOrShortcode,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              ref.read(extensionsControllerProvider.notifier).addRepository(value);
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          CustomButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: LayoutConstants.spacingXs),
          CustomButton(
            isPrimary: true,
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref.read(extensionsControllerProvider.notifier).addRepository(controller.text);
                Navigator.pop(context);
              }
            },
            child: Text(l10n.addRepo),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dedicated Add Repo Tile Widget 
// ---------------------------------------------------------------------------
class _AddRepoTile extends ConsumerStatefulWidget {
  final VoidCallback onTap;
  const _AddRepoTile({required this.onTap});

  @override
  ConsumerState<_AddRepoTile> createState() => _AddRepoTileState();
}

class _AddRepoTileState extends ConsumerState<_AddRepoTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return _SectionCard(
      margin: EdgeInsets.zero,
      borderColor: theme.colorScheme.primary.withValues(alpha: 0.3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _isFocused ? theme.colorScheme.primary.withValues(alpha: 0.15) : Colors.transparent,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            onFocusChange: (f) {
              setState(() => _isFocused = f);
              if (f && mounted) {
                ref.read(focusedGamepadHintsProvider.notifier).state = [
                  GamepadHint(buttonLabel: 'LB', actionLabel: 'Prev Tab', buttonColor: Colors.grey.shade400),
                  GamepadHint(buttonLabel: 'RB', actionLabel: 'Next Tab', buttonColor: Colors.grey.shade400),
                  GamepadHint(buttonLabel: 'A', actionLabel: 'Add Repo', buttonColor: Colors.greenAccent.shade400),
                ];
              }
            },
            leading: Icon(Icons.add_circle_outline, color: theme.colorScheme.primary),
            title: Text(l10n.addRepo, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
            onTap: widget.onTap,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Repo Tile Widget 
// ---------------------------------------------------------------------------
class _RepoTile extends ConsumerStatefulWidget {
  final ExtensionRepository repo;
  final List<ExtensionPlugin> plugins;
  final ExtensionsState state;
  final FocusNode? focusNode;

  const _RepoTile({
    required this.repo, 
    required this.plugins, 
    required this.state, 
    this.focusNode, 
  });

  @override
  ConsumerState<_RepoTile> createState() => _RepoTileState();
}

class _RepoTileState extends ConsumerState<_RepoTile> {
  late FocusNode _repoFocusNode;
  bool _ownsFocusNode = false;
  
  bool _isFocused = false;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _repoFocusNode = widget.focusNode!;
    } else {
      _repoFocusNode = FocusNode();
      _ownsFocusNode = true;
    }
  }

  void _updateHints(bool hasFocus) {
    if (!mounted) return;
    if (hasFocus) {
      final allInstalled = widget.plugins.isNotEmpty && widget.plugins.every((p) => widget.state.installedPlugins.any((i) => !i.isDebug && i.packageName == p.packageName));
      ref.read(focusedGamepadHintsProvider.notifier).state = [
        GamepadHint(buttonLabel: 'LB', actionLabel: 'Prev Tab', buttonColor: Colors.grey.shade400),
        GamepadHint(buttonLabel: 'RB', actionLabel: 'Next Tab', buttonColor: Colors.grey.shade400),
        GamepadHint(buttonLabel: 'A', actionLabel: _isExpanded ? 'Collapse' : 'Expand', buttonColor: Colors.greenAccent.shade400),
        if (!allInstalled && widget.plugins.isNotEmpty)
          GamepadHint(buttonLabel: 'X', actionLabel: 'Download All', buttonColor: Colors.blueAccent.shade400),
        GamepadHint(buttonLabel: 'Y', actionLabel: 'Delete Repo', buttonColor: Colors.redAccent.shade400),
      ];
    } else {
      final currentHints = ref.read(focusedGamepadHintsProvider);
      if (currentHints?.any((h) => h.actionLabel == 'Delete Repo') == true) {
        ref.read(focusedGamepadHintsProvider.notifier).state = null;
      }
    }
  }

  void _confirmDeleteRepo(BuildContext context, WidgetRef ref, ExtensionRepository repo) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.removeRepoConfirm(repo.name)),
        content: Text(l10n.removeRepoWarning),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(extensionsControllerProvider.notifier).removeRepository(repo.url);
              Navigator.of(context).pop();
            },
            child: Text(l10n.delete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (_ownsFocusNode) _repoFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isBigPicture = profile?.isTv == true || context.isDesktop || context.isTv;

    final allInstalled = widget.plugins.isNotEmpty && widget.plugins.every((p) => widget.state.installedPlugins.any((i) => !i.isDebug && i.packageName == p.packageName));
    final isRepoInstalling = widget.plugins.any((p) => widget.state.installingPlugins.contains(p.packageName));

    return _SectionCard(
      margin: const EdgeInsets.only(bottom: LayoutConstants.spacingMd, left: LayoutConstants.spacingMd, right: LayoutConstants.spacingMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Actions(
            actions: <Type, Action<Intent>>{
              AppSecondaryIntent: CallbackAction<AppSecondaryIntent>(
                onInvoke: (_) {
                  if (!allInstalled && widget.plugins.isNotEmpty) {
                    final pluginsToInstall = widget.plugins.where((p) {
                      final installed = widget.state.installedPlugins.cast<ExtensionPlugin?>().firstWhere((inst) => inst?.packageName == p.packageName, orElse: () => null);
                      return installed == null || p.version > installed.version;
                    }).toList();
                    if (pluginsToInstall.isNotEmpty) {
                      ref.read(extensionsControllerProvider.notifier).installPlugins(pluginsToInstall);
                    }
                  }
                  return null;
                }
              ),
              AppTertiaryIntent: CallbackAction<AppTertiaryIntent>(
                onInvoke: (_) {
                  _confirmDeleteRepo(context, ref, widget.repo);
                  return null;
                }
              ),
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: _isFocused ? theme.colorScheme.primary.withValues(alpha: 0.22) : Colors.transparent,
                border: Border.all(
                  color: _isFocused ? theme.colorScheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  focusNode: _repoFocusNode,
                  onFocusChange: (f) {
                    setState(() => _isFocused = f);
                    _updateHints(f);
                  },
                  onTap: () {
                    setState(() => _isExpanded = !_isExpanded);
                    if (_repoFocusNode.hasPrimaryFocus) _updateHints(true); 
                  },
                  contentPadding: const EdgeInsets.symmetric(horizontal: LayoutConstants.spacingMd, vertical: LayoutConstants.spacingXs),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.repo.name, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                      if (widget.repo.description?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 2),
                        Text(widget.repo.description!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isBigPicture) ...[
                        if (!allInstalled && widget.plugins.isNotEmpty)
                          const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.download, color: Colors.blueAccent)),
                        const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.delete_outline, color: Colors.redAccent)),
                      ],
                      Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          if (_isExpanded) ...[
            if (!isBigPicture)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: LayoutConstants.spacingMd, vertical: LayoutConstants.spacingXs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isRepoInstalling)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: AppLoadingIndicator(constraints: BoxConstraints(minWidth: 24, minHeight: 24, maxWidth: 24, maxHeight: 24)),
                      )
                    else ...[
                      TextButton.icon(
                        icon: Icon(allInstalled ? Icons.check_circle_outline : Icons.download, color: allInstalled ? theme.colorScheme.primary : null),
                        label: Text(allInstalled ? 'All installed' : l10n.downloadAllProviders),
                        onPressed: allInstalled || widget.plugins.isEmpty ? null : () {
                          final pluginsToInstall = widget.plugins.where((p) {
                            final installed = widget.state.installedPlugins.cast<ExtensionPlugin?>().firstWhere((inst) => inst?.packageName == p.packageName, orElse: () => null);
                            return installed == null || p.version > installed.version;
                          }).toList();
                          if (pluginsToInstall.isNotEmpty) {
                            ref.read(extensionsControllerProvider.notifier).installPlugins(pluginsToInstall);
                          }
                        },
                      ),
                      const SizedBox(width: LayoutConstants.spacingSm),
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        label: Text(l10n.delete),
                        onPressed: () => _confirmDeleteRepo(context, ref, widget.repo),
                      ),
                    ],
                  ],
                ),
              ),
            if (!isBigPicture) const Divider(height: 1),
            ...widget.plugins.asMap().entries.map((entry) {
              final isLast = entry.key == widget.plugins.length - 1;
              return Column(
                children: [
                  _PluginTile(plugin: entry.value),
                  if (!isLast)
                    Divider(height: 1, indent: 56, endIndent: 16, color: theme.dividerColor.withValues(alpha: 0.5)),
                ],
              );
            }),
          ]
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plugin Tile Widget
// ---------------------------------------------------------------------------

class _PluginTile extends ConsumerStatefulWidget {
  final ExtensionPlugin plugin;
  final bool isDebugSection;
  final FocusNode? focusNode;

  const _PluginTile({
    required this.plugin, 
    this.isDebugSection = false, 
    this.focusNode, 
  });

  @override
  ConsumerState<_PluginTile> createState() => _PluginTileState();
}

class _PluginTileState extends ConsumerState<_PluginTile> {
  late FocusNode _tileFocusNode;
  bool _ownsFocusNode = false;
  bool _isFocused = false;

  Future<List<PluginSettingDefinition>>? _settingsFuture;
  String? _settingsFutureIdentity;

  String _settingsIdentity(ExtensionPlugin plugin) => '${plugin.packageName}:${plugin.version}:${plugin.sourceUrl}';

  Future<List<PluginSettingDefinition>> _settingsFor(ExtensionPlugin plugin) {
    final identity = _settingsIdentity(plugin);
    if (_settingsFuture == null || _settingsFutureIdentity != identity) {
      _settingsFutureIdentity = identity;
      _settingsFuture = ref.read(extensionManagerProvider.notifier).getSettingsForPlugin(plugin);
    }
    return _settingsFuture!;
  }

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _tileFocusNode = widget.focusNode!;
    } else {
      _tileFocusNode = FocusNode();
      _ownsFocusNode = true;
    }
  }

  void _updateHints(bool hasFocus, bool isInstalled, bool hasSettings, dynamic updateAvailable) {
    if (!mounted) return;

    if (hasFocus) {
      final bool showA = !isInstalled || (isInstalled && hasSettings);

      ref.read(focusedGamepadHintsProvider.notifier).state = [
        GamepadHint(buttonLabel: 'LB', actionLabel: 'Prev Tab', buttonColor: Colors.grey.shade400),
        GamepadHint(buttonLabel: 'RB', actionLabel: 'Next Tab', buttonColor: Colors.grey.shade400),
        if (showA) GamepadHint(
          buttonLabel: 'A', 
          actionLabel: isInstalled ? 'Settings' : 'Install', 
          buttonColor: Colors.greenAccent.shade400
        ),
        if (isInstalled && updateAvailable != null) GamepadHint(buttonLabel: 'X', actionLabel: 'Update', buttonColor: Colors.blueAccent.shade400),
        if (isInstalled) GamepadHint(buttonLabel: 'Y', actionLabel: 'Delete', buttonColor: Colors.redAccent.shade400),
      ];
    } else {
      final currentHints = ref.read(focusedGamepadHintsProvider);
      if (currentHints?.any((h) => h.actionLabel == 'Delete' || h.actionLabel == 'Settings' || h.actionLabel == 'Install') == true) {
        ref.read(focusedGamepadHintsProvider.notifier).state = null;
      }
    }
  }

  void _confirmDeletePlugin(BuildContext context, WidgetRef ref, ExtensionPlugin plugin) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${plugin.name}'),
        content: const Text('Are you sure you want to delete this extension?'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(extensionsControllerProvider.notifier).uninstallPlugin(plugin);
              Navigator.of(context).pop();
            },
            child: Text(l10n.delete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _PluginTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_settingsIdentity(oldWidget.plugin) != _settingsIdentity(widget.plugin)) {
      _settingsFuture = null;
      _settingsFutureIdentity = null;
    }
  }

  @override
  void dispose() {
    if (_ownsFocusNode) _tileFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final profile = ref.watch(deviceProfileProvider).asData?.value;
    final isBigPicture = profile?.isTv == true || context.isDesktop || context.isTv;

    if (widget.isDebugSection) {
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(LayoutConstants.spacingXs),
          decoration: BoxDecoration(color: theme.colorScheme.tertiary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.bug_report, color: theme.colorScheme.tertiary, size: 20),
        ),
        title: Row(
          children: [
            Expanded(child: Text(widget.plugin.name, style: const TextStyle(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: LayoutConstants.spacingXs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
              child: Text(l10n.debug, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        subtitle: Text("v${widget.plugin.version} • ${l10n.assetPlugin}", style: TextStyle(color: theme.textTheme.bodySmall?.color)),
      );
    }

    final state = ref.watch(extensionsControllerProvider);

    final installedPlugin = state.installedPlugins.cast<ExtensionPlugin?>().firstWhere((p) {
      if (p == null) return false;
      if (p.isDebug) return false;
      return p.packageName == widget.plugin.packageName;
    }, orElse: () => null);

    final isInstalled = installedPlugin != null;
    final updateAvailable = state.availableUpdates[widget.plugin.packageName];
    final isInstalling = state.installingPlugins.contains(widget.plugin.packageName);

    return FutureBuilder<List<PluginSettingDefinition>>(
      future: isInstalled ? _settingsFor(installedPlugin) : Future.value([]),
      builder: (context, snapshot) {
        bool hasSettings = false;
        if (isInstalled) {
          final manifestSettings = installedPlugin.manifest['settings'];
          final hasManifestSettings = manifestSettings is List && manifestSettings.isNotEmpty;
          final hasScriptSettings = snapshot.data?.isNotEmpty ?? false;
          final declaresScriptSettings = installedPlugin.manifest['hasSettings'] == true;
          final hasDomains = installedPlugin.domains?.isNotEmpty ?? false;
          final hasStaticProviders = installedPlugin.providers?.isNotEmpty ?? false;
          final loadedProviders = ref.watch(extensionManagerProvider);
          final hasLoadedSubProviders = loadedProviders.any((provider) => provider.packageName.startsWith('${installedPlugin.packageName}::'));
          final hasDynamicProviders = ref.read(extensionManagerProvider.notifier).getProvidersForPlugin(installedPlugin).isNotEmpty;
          
          hasSettings = hasManifestSettings || hasScriptSettings || declaresScriptSettings || hasDomains || hasStaticProviders || hasDynamicProviders || hasLoadedSubProviders;
        }

        if (_tileFocusNode.hasFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _updateHints(true, isInstalled, hasSettings, updateAvailable);
          });
        }

        return Actions(
          actions: <Type, Action<Intent>>{
            AppSecondaryIntent: CallbackAction<AppSecondaryIntent>(
              onInvoke: (_) {
                if (isInstalled && updateAvailable != null) {
                  ref.read(extensionsControllerProvider.notifier).updatePlugin(updateAvailable);
                }
                return null;
              }
            ),
            AppTertiaryIntent: CallbackAction<AppTertiaryIntent>(
              onInvoke: (_) {
                if (isInstalled) {
                  _confirmDeletePlugin(context, ref, installedPlugin);
                }
                return null;
              }
            ),
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: _isFocused ? theme.colorScheme.primary.withValues(alpha: 0.22) : Colors.transparent,
              border: Border.all(
                color: _isFocused ? theme.colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                focusNode: _tileFocusNode,
                onFocusChange: (f) {
                  setState(() => _isFocused = f);
                  _updateHints(f, isInstalled, hasSettings, updateAvailable);
                },
                onTap: () async {
                  if (isInstalled) {
                    if (hasSettings) {
                      await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (context) => PluginSettingsScreen(plugin: installedPlugin)));
                      if (context.mounted) _tileFocusNode.requestFocus();
                    }
                  } else if (!isInstalling) {
                    await ref.read(extensionsControllerProvider.notifier).installPlugin(widget.plugin);
                  }
                },
                leading: Container(
                  width: 44, height: 44, alignment: Alignment.center,
                  decoration: BoxDecoration(color: isInstalled ? Colors.green.withValues(alpha: 0.15) : theme.colorScheme.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
                  child: Icon(
                    isInstalled ? Icons.check_circle_rounded : Icons.download_rounded, 
                    color: isInstalled ? Colors.green : theme.colorScheme.primary, 
                    size: 22
                  ),
                ),
                title: Text(widget.plugin.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                subtitle: _buildSubtitle(context, isInstalled, installedPlugin),
                
                trailing: isInstalling
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: AppLoadingIndicator(constraints: BoxConstraints(minWidth: 24, minHeight: 24, maxWidth: 24, maxHeight: 24)),
                      )
                    : isBigPicture 
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isInstalled && updateAvailable != null) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.download, color: Colors.blueAccent)),
                              if (isInstalled && hasSettings) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.settings_outlined, color: Colors.grey)),
                              if (isInstalled) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.delete_outline, color: Colors.redAccent)),
                            ],
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isInstalled && updateAvailable != null)
                                IconButton(
                                  icon: const Icon(Icons.download, color: Colors.green),
                                  tooltip: l10n.updateTo(updateAvailable.version.toString()),
                                  onPressed: () {
                                    ref.read(extensionsControllerProvider.notifier).updatePlugin(updateAvailable);
                                  },
                                ),
                              if (isInstalled && hasSettings)
                                IconButton(
                                  icon: const Icon(Icons.settings_outlined),
                                  tooltip: l10n.settings,
                                  onPressed: () async {
                                    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (context) => PluginSettingsScreen(plugin: installedPlugin)));
                                  },
                                ),
                              if (isInstalled)
                                IconButton(
                                  icon: Icon(Icons.delete, color: theme.colorScheme.error),
                                  tooltip: l10n.delete,
                                  onPressed: () => _confirmDeletePlugin(context, ref, installedPlugin),
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.download),
                                  tooltip: l10n.install,
                                  onPressed: () {
                                    ref.read(extensionsControllerProvider.notifier).installPlugin(widget.plugin);
                                  },
                                ),
                            ],
                          ),
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildSubtitle(BuildContext context, bool isInstalled, ExtensionPlugin? installedPlugin) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final descStyle = textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant);
    final metaStyle = textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant);
    final version = 'v${isInstalled ? installedPlugin!.version : widget.plugin.version}';
    final authors = widget.plugin.authors.take(2).join(', ');
    final metaParts = [version, if (authors.isNotEmpty) 'By $authors'];
    final metaLine = metaParts.join(' • ');
    final desc = widget.plugin.description;
    final hasDesc = desc != null && desc.isNotEmpty;
    final hasLanguages = widget.plugin.languages.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasDesc) Text(desc, style: descStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(metaLine, style: metaStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (hasLanguages) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4, runSpacing: 4,
            children: widget.plugin.languages.take(5).map((lang) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
                child: Text(lang.toUpperCase(), style: TextStyle(fontSize: 11, color: colorScheme.onSecondaryContainer, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final Color? borderColor;

  const _SectionCard({required this.child, this.margin, this.borderColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: margin ?? const EdgeInsets.all(LayoutConstants.spacingMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? theme.dividerColor.withValues(alpha: 0.5),
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: child,
      ),
    );
  }
}