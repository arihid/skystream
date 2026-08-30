import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../shared/widgets/custom_widgets.dart';
import '../../../../core/services/external_player_service.dart';
import '../../../../core/config/tmdb_config.dart';
import '../../../../core/network/dio_client_provider.dart';
import '../../../../core/network/doh_service.dart';
import '../../../stream/data/stream_browser_provider.dart';
import '../../../../core/storage/settings_repository.dart';
import '../../../../core/services/download_service.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../player_settings_provider.dart';
import '../../../../core/utils/stream_quality_sorter.dart';
import '../general_settings_provider.dart';
import '../../../../core/providers/locale_provider.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import '../../../../core/services/notification_service.dart';
import '../cache_provider.dart';

/// Returns a localized label for a player gesture.
String getGestureLabel(PlayerGesture gesture, AppLocalizations l10n) {
  switch (gesture) {
    case PlayerGesture.volume:
      return l10n.volume;
    case PlayerGesture.brightness:
      return l10n.brightness;
    case PlayerGesture.none:
      return l10n.none;
  }
}

/// Returns a localized label for a resize mode string.
String getResizeModeLabel(String mode, AppLocalizations l10n) {
  switch (mode.toLowerCase()) {
    case 'fit':
      return l10n.fit;
    case 'zoom':
      return l10n.zoom;
    case 'stretch':
      return l10n.stretch;
    default:
      return mode;
  }
}

/// Returns a human-readable label for a home screen route.
String getHomeScreenLabel(String route, AppLocalizations l10n) {
  switch (route) {
    case '/home':
      return l10n.home;
    case '/explore':
      return l10n.explore;
    case '/search':
      return l10n.search;
    case '/library':
      return l10n.library;
    default:
      return l10n.home;
  }
}

/// Shows a dialog to pick the default home screen.
void showDefaultHomeScreenDialog(
  BuildContext context,
  WidgetRef ref,
  String current,
) {
  final l10n = AppLocalizations.of(context)!;
  final options = <Map<String, String>>[
    {'label': l10n.home, 'route': '/home'},
    {'label': l10n.explore, 'route': '/explore'},
    {'label': l10n.search, 'route': '/search'},
    {'label': l10n.library, 'route': '/library'},
  ];

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.defaultHomeScreen),
      content: RadioGroup<String>(
        groupValue: current,
        onChanged: (val) {
          if (val == null) return;
          ref.read(generalSettingsProvider.notifier).setDefaultHomeScreen(val);
          Navigator.pop<void>(context);
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              return ListTile(
                autofocus: current == opt['route'],
                title: Text(opt['label']!),
                leading: Radio<String>(value: opt['route']!),
                onTap: () {
                  ref
                      .read(generalSettingsProvider.notifier)
                      .setDefaultHomeScreen(opt['route']!);
                  Navigator.pop<void>(context);
                },
              );
            }).toList(),
          ),
        ),
      ),
    ),
  );
}

/// Returns a localized label for a title position.
String getTitlePositionLabel(String position, AppLocalizations l10n) {
  switch (position) {
    case 'inside':
      return l10n.titlePositionInsidePoster;
    case 'below':
    default:
      return l10n.titlePositionBelowPoster;
  }
}

/// Shows a dialog to pick the title position on poster cards.
void showTitlePositionDialog(
  BuildContext context,
  WidgetRef ref,
  String current,
) {
  final l10n = AppLocalizations.of(context)!;
  final options = <Map<String, String>>[
    {'label': l10n.titlePositionBelowPoster, 'value': 'below'},
    {'label': l10n.titlePositionInsidePoster, 'value': 'inside'},
  ];

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.titlePosition),
      content: RadioGroup<String>(
        groupValue: current,
        onChanged: (val) {
          if (val == null) return;
          ref.read(generalSettingsProvider.notifier).setTitlePosition(val);
          Navigator.pop<void>(context);
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              return ListTile(
                autofocus: current == opt['value'],
                title: Text(opt['label']!),
                leading: Radio<String>(value: opt['value']!),
                onTap: () {
                  ref
                      .read(generalSettingsProvider.notifier)
                      .setTitlePosition(opt['value']!);
                  Navigator.pop<void>(context);
                },
              );
            }).toList(),
          ),
        ),
      ),
    ),
  );
}

Future<void> showDownloadSettingsDialog(
  BuildContext context,
  WidgetRef ref,
  GeneralSettings settings,
) async {
  int concurrency = settings.downloadConcurrency;
  int chunks = settings.downloadChunks;
  String? directory = settings.downloadDirectory;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Downloads'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.folder_open_rounded),
                      title: const Text('Download location'),
                      subtitle: Text(
                        directory ?? 'System Downloads/Skystream',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.edit),
                      onTap: () async {
                        final picked = await ref
                            .read(downloadServiceProvider)
                            .pickDownloadDirectory();
                        if (picked != null) {
                          setDialogState(() => directory = picked);
                        }
                      },
                    ),
                    if (directory != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            ref
                                .read(generalSettingsProvider.notifier)
                                .setDownloadDirectory(null);
                            setDialogState(() => directory = null);
                          },
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset to default'),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text('Queue limit: $concurrency at once'),
                    Slider(
                      value: concurrency.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: concurrency.toString(),
                      onChanged: (v) =>
                          setDialogState(() => concurrency = v.round()),
                    ),
                    Text('Segments per file: $chunks'),
                    Slider(
                      value: chunks.toDouble(),
                      min: 1,
                      max: 8,
                      divisions: 7,
                      label: chunks == 1 ? 'Off' : chunks.toString(),
                      onChanged: (v) =>
                          setDialogState(() => chunks = v.round()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final notifier = ref.read(generalSettingsProvider.notifier);
                  await notifier.setDownloadDirectory(directory);
                  await notifier.setDownloadConcurrency(concurrency);
                  await notifier.setDownloadChunks(chunks);
                  await ref
                      .read(downloadServiceProvider)
                      .applyQueueSettings(
                        maxConcurrent: concurrency,
                        chunks: chunks,
                      );
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}

// Must be used inside a RadioGroup<ThemeMode> ancestor.
Widget _buildThemeOption(
  String title,
  ThemeMode value,
  ThemeMode currentTheme,
  VoidCallback onSelect,
) {
  return ListTile(
    autofocus: currentTheme == value,
    title: Text(title),
    leading: Radio<ThemeMode>(value: value),
    onTap: onSelect,
  );
}

/// Shows a dialog to pick the app theme mode.
void showThemeDialog(
  BuildContext context,
  WidgetRef ref,
  ThemeMode currentTheme,
) {
  final l10n = AppLocalizations.of(context)!;
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.chooseTheme),
      content: RadioGroup<ThemeMode>(
        groupValue: currentTheme,
        onChanged: (val) {
          if (val == null) return;
          ref.read(appThemeModeProvider.notifier).setThemeMode(val);
          Navigator.pop<void>(context);
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildThemeOption(
                l10n.system,
                ThemeMode.system,
                currentTheme,
                () {
                  ref
                      .read(appThemeModeProvider.notifier)
                      .setThemeMode(ThemeMode.system);
                  Navigator.pop<void>(context);
                },
              ),
              _buildThemeOption(l10n.dark, ThemeMode.dark, currentTheme, () {
                ref
                    .read(appThemeModeProvider.notifier)
                    .setThemeMode(ThemeMode.dark);
                Navigator.pop<void>(context);
              }),
              _buildThemeOption(l10n.light, ThemeMode.light, currentTheme, () {
                ref
                    .read(appThemeModeProvider.notifier)
                    .setThemeMode(ThemeMode.light);
                Navigator.pop<void>(context);
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<void>(context),
          child: Text(
            l10n.cancel,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Formats seek duration for display (e.g. "10 sec", "2 min").
String formatSeekDuration(int seconds, AppLocalizations l10n) {
  if (seconds >= 60) {
    return '${seconds ~/ 60} ${l10n.min}';
  }
  return '$seconds ${l10n.sec}';
}

/// Formats readahead seconds for display (e.g. "5 min", "10 min").
String formatReadahead(int seconds, AppLocalizations l10n) {
  return '${seconds ~/ 60} ${l10n.min}';
}

/// Returns a human-readable name for a player ID.
String getPlayerDisplayName(String? playerId, AppLocalizations l10n) {
  if (playerId == null) return l10n.internalPlayer;
  final player = ExternalPlayerService.instance.getPlayerById(playerId);
  return player?.displayName ?? playerId;
}

/// Returns a human-readable label for a DoH provider.
String getDohProviderLabel(
  DohProvider provider,
  String customUrl,
  AppLocalizations l10n,
) {
  switch (provider) {
    case DohProvider.cloudflare:
      return l10n.cloudflare;
    case DohProvider.google:
      return l10n.google;
    case DohProvider.adguard:
      return l10n.adguard;
    case DohProvider.dnsWatch:
      return l10n.dnsWatch;
    case DohProvider.quad9:
      return l10n.quad9;
    case DohProvider.dnsSb:
      return l10n.dnsSb;
    case DohProvider.canadianShield:
      return l10n.canadianShield;
    case DohProvider.custom:
      return customUrl.isNotEmpty ? customUrl : l10n.customNotSet;
  }
}

/// Shows a dialog to pick the default player (internal or external).
void showDefaultPlayerDialog(
  BuildContext context,
  WidgetRef ref,
  String? currentPlayerId,
) {
  final l10n = AppLocalizations.of(context)!;
  final platformPlayers = ExternalPlayerService.instance
      .getPlayersForPlatform();

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.defaultPlayer),
      content: SingleChildScrollView(
        child: RadioGroup<String?>(
          groupValue: currentPlayerId,
          onChanged: (val) {
            ref.read(playerSettingsProvider.notifier).setPreferredPlayer(val);
            Navigator.pop<void>(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                autofocus: currentPlayerId == null,
                title: Text(l10n.internalPlayer),
                subtitle: Text(l10n.builtInPlayer),
                leading: const Radio<String?>(value: null),
                trailing: const Icon(Icons.play_circle_filled_rounded),
                onTap: () {
                  ref
                      .read(playerSettingsProvider.notifier)
                      .setPreferredPlayer(null);
                  Navigator.pop<void>(context);
                },
              ),
              const Divider(),
              ...platformPlayers.map((player) {
                return ListTile(
                  autofocus: currentPlayerId == player.id,
                  title: Text(player.displayName),
                  leading: Radio<String?>(value: player.id),
                  trailing: Icon(player.icon),
                  onTap: () {
                    ref
                        .read(playerSettingsProvider.notifier)
                        .setPreferredPlayer(player.id);
                    Navigator.pop<void>(context);
                  },
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<void>(context),
          child: Text(
            l10n.cancel,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Shows a dialog to pick the DNS-over-HTTPS provider.
void showDohProviderDialog(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  final initialSettings = ref.read(dohSettingsProvider).asData?.value;
  var currentProvider = initialSettings?.provider ?? DohProvider.cloudflare;
  final controller = TextEditingController(
    text: initialSettings?.customUrl ?? '',
  );

  showDialog<void>(
    context: context,
    builder: (ctx) {
      void saveAndClose(DohProvider p, [String? customUrl]) {
        ref.read(dohSettingsProvider.notifier).setProvider(p);
        if (p == DohProvider.custom && customUrl != null) {
          ref.read(dohSettingsProvider.notifier).setCustomUrl(customUrl);
        }
        ref.read(dohSettingsProvider.notifier).clearCache();
        Navigator.pop<void>(ctx);
      }

      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            surfaceTintColor: Colors.transparent,
            title: Text(l10n.dohProvider),
            content: SingleChildScrollView(
              child: RadioGroup<DohProvider>(
                groupValue: currentProvider,
                onChanged: (val) {
                  if (val == null) return;
                  if (val == DohProvider.custom) {
                    setState(() => currentProvider = val);
                  } else {
                    saveAndClose(val);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      autofocus: currentProvider == DohProvider.cloudflare,
                      title: Text(l10n.cloudflare),
                      subtitle: const Text('1.1.1.1'),
                      leading: const Radio<DohProvider>(
                        value: DohProvider.cloudflare,
                      ),
                      onTap: () => saveAndClose(DohProvider.cloudflare),
                    ),
                    ListTile(
                      autofocus: currentProvider == DohProvider.google,
                      title: Text(l10n.google),
                      subtitle: const Text('8.8.8.8'),
                      leading: const Radio<DohProvider>(
                        value: DohProvider.google,
                      ),
                      onTap: () => saveAndClose(DohProvider.google),
                    ),
                    ListTile(
                      autofocus: currentProvider == DohProvider.adguard,
                      title: Text(l10n.adguard),
                      subtitle: const Text('dns.adguard.com'),
                      leading: const Radio<DohProvider>(
                        value: DohProvider.adguard,
                      ),
                      onTap: () => saveAndClose(DohProvider.adguard),
                    ),
                    ListTile(
                      autofocus: currentProvider == DohProvider.dnsWatch,
                      title: Text(l10n.dnsWatch),
                      subtitle: const Text('resolver2.dns.watch'),
                      leading: const Radio<DohProvider>(
                        value: DohProvider.dnsWatch,
                      ),
                      onTap: () => saveAndClose(DohProvider.dnsWatch),
                    ),
                    ListTile(
                      autofocus: currentProvider == DohProvider.quad9,
                      title: Text(l10n.quad9),
                      subtitle: const Text('9.9.9.9'),
                      leading: const Radio<DohProvider>(
                        value: DohProvider.quad9,
                      ),
                      onTap: () => saveAndClose(DohProvider.quad9),
                    ),
                    ListTile(
                      autofocus: currentProvider == DohProvider.dnsSb,
                      title: Text(l10n.dnsSb),
                      subtitle: const Text('doh.dns.sb'),
                      leading: const Radio<DohProvider>(
                        value: DohProvider.dnsSb,
                      ),
                      onTap: () => saveAndClose(DohProvider.dnsSb),
                    ),
                    ListTile(
                      autofocus: currentProvider == DohProvider.canadianShield,
                      title: Text(l10n.canadianShield),
                      subtitle: const Text('private.canadianshield.cira.ca'),
                      leading: const Radio<DohProvider>(
                        value: DohProvider.canadianShield,
                      ),
                      onTap: () => saveAndClose(DohProvider.canadianShield),
                    ),
                    ListTile(
                      autofocus: currentProvider == DohProvider.custom,
                      title: Text(l10n.custom),
                      subtitle: Text(l10n.enterCustomDohUrl),
                      leading: const Radio<DohProvider>(
                        value: DohProvider.custom,
                      ),
                      onTap: () =>
                          setState(() => currentProvider = DohProvider.custom),
                    ),
                    if (currentProvider == DohProvider.custom)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: CustomTextField(
                          controller: controller,
                          // No autofocus here! Keeps TV keyboard from popping up instantly.
                          decoration: InputDecoration(
                            labelText: l10n.customDohUrlLabel,
                            hintText: 'https://...',
                            prefixIcon: const Icon(
                              Icons.link_rounded,
                              size: 20,
                            ),
                          ),
                          keyboardType: TextInputType.url,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop<void>(ctx),
                child: Text(
                  l10n.cancel,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (currentProvider == DohProvider.custom)
                CustomButton(
                  isPrimary: true,
                  onPressed: () {
                    final url = controller.text.trim();
                    if (url.isNotEmpty) {
                      saveAndClose(DohProvider.custom, url);
                    }
                  },
                  child: Text(l10n.save),
                ),
            ],
          );
        },
      );
    },
  );
}

/// Shows a dialog to pick the left/right swipe gesture.
void showGestureDialog(
  BuildContext context,
  WidgetRef ref,
  bool isLeft,
  PlayerGesture current,
) {
  final l10n = AppLocalizations.of(context)!;
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.selectGesture(isLeft ? l10n.left : l10n.right)),
      content: RadioGroup<PlayerGesture>(
        groupValue: current,
        onChanged: (val) {
          if (val == null) return;
          if (isLeft) {
            ref.read(playerSettingsProvider.notifier).setLeftGesture(val);
          } else {
            ref.read(playerSettingsProvider.notifier).setRightGesture(val);
          }
          Navigator.pop<void>(context);
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: PlayerGesture.values.map((g) {
              final String label = getGestureLabel(g, l10n);
              return ListTile(
                autofocus: current == g,
                title: Text(label),
                leading: Radio<PlayerGesture>(value: g),
                onTap: () {
                  if (isLeft) {
                    ref.read(playerSettingsProvider.notifier).setLeftGesture(g);
                  } else {
                    ref
                        .read(playerSettingsProvider.notifier)
                        .setRightGesture(g);
                  }
                  Navigator.pop<void>(context);
                },
              );
            }).toList(),
          ),
        ),
      ),
    ),
  );
}

/// Shows a dialog to pick the seek duration.
void showDurationDialog(BuildContext context, WidgetRef ref, int current) {
  final l10n = AppLocalizations.of(context)!;
  final options = <int>[5, 10, 15, 20, 30, 60, 120];

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.selectSeekDuration),
      content: RadioGroup<int>(
        groupValue: current,
        onChanged: (val) {
          if (val == null) return;
          ref.read(playerSettingsProvider.notifier).setSeekDuration(val);
          Navigator.pop<void>(context);
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((sec) {
              return ListTile(
                autofocus: current == sec,
                title: Text(formatSeekDuration(sec, l10n)),
                leading: Radio<int>(value: sec),
                onTap: () {
                  ref
                      .read(playerSettingsProvider.notifier)
                      .setSeekDuration(sec);
                  Navigator.pop<void>(context);
                },
              );
            }).toList(),
          ),
        ),
      ),
    ),
  );
}

/// Shows a dialog to reset data.
void showResetDataDialog(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  final callerContext = context;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.resetDataDialogTitle),
      content: Text(l10n.resetDataDialogContent),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop<void>(dialogContext),
          child: Text(
            l10n.cancel,
            style: TextStyle(
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop<void>(dialogContext);

            // Clear Preferences ONLY
            await ref.read(settingsRepositoryProvider).clearPreferences();

            // Restart App - use caller's context; dialog context may be disposed after pop
            if (callerContext.mounted) {
              await AppUtils.restartApp(callerContext);
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.tertiary,
          ),
          child: Text(l10n.resetDataKeepExtensions),
        ),
      ],
    ),
  );
}

/// Shows a dialog to factory reset.
void showFactoryResetDialog(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  final callerContext = context;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.factoryResetDialogTitle),
      content: Text(l10n.factoryResetDialogContent),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop<void>(dialogContext),
          child: Text(
            l10n.cancel,
            style: TextStyle(
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop<void>(dialogContext);
            // Deep Clean (Extensions, Prefs, Hive)
            await ref.read(settingsRepositoryProvider).deleteAllData();

            // Restart App - use caller's context; dialog context may be disposed after pop
            if (callerContext.mounted) {
              await AppUtils.restartApp(callerContext);
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          child: Text(l10n.factoryReset),
        ),
      ],
    ),
  );
}

/// Shows a dialog to clear the image & video cache.
void showClearCacheDialog(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.clearCacheDialogTitle),
      content: Text(l10n.clearCacheDialogContent),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop<void>(dialogContext),
          child: Text(
            l10n.cancel,
            style: TextStyle(
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop<void>(dialogContext);
            await ref.read(settingsRepositoryProvider).clearImageVideoCache();
            ref.invalidate(cacheSizeProvider);
            
            ref
                .read(notificationServiceProvider)
                .showSuccess(
                  l10n.cacheCleared,
                  title: 'Storage',
                  icon: Icons.cleaning_services_rounded,
                );
          },
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          child: Text(l10n.clearCacheNow),
        ),
      ],
    ),
  );
}

/// Shows a dialog to pick the application language.
void showLanguageDialog(
  BuildContext context,
  WidgetRef ref,
  Locale currentLocale,
) {
  final l10n = AppLocalizations.of(context)!;

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Text(l10n.selectLanguage),
      content: FutureBuilder<List<Map<String, dynamic>>>(
        future: Future.wait(
          AppLocalizations.supportedLocales.map((locale) async {
            final localL10n = await AppLocalizations.delegate.load(locale);
            return {'label': localL10n.languageName, 'locale': locale};
          }),
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 100,
              child: Center(child: AppLoadingIndicator()),
            );
          }

          final options = snapshot.data!;

          return RadioGroup<Locale>(
            groupValue: currentLocale,
            onChanged: (val) {
              if (val == null) return;
              ref.read(localeProvider.notifier).setLocale(val);
              Navigator.pop<void>(context);
            },
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: options.map((opt) {
                  final locale = opt['locale'] as Locale;
                  return ListTile(
                    autofocus: currentLocale == locale,
                    title: Text(opt['label'] as String),
                    leading: Radio<Locale>(value: locale),
                    onTap: () {
                      ref.read(localeProvider.notifier).setLocale(locale);
                      Navigator.pop<void>(context);
                    },
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<void>(context),
          child: Text(
            l10n.cancel,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// HDR / tone-mapping + volume boost
// ---------------------------------------------------------------------------

String hdrModeLabel(HdrMode mode) => switch (mode) {
  HdrMode.auto => 'Auto',
  HdrMode.passthrough => 'HDR passthrough',
  HdrMode.toneMapSdr => 'Tone-map to SDR',
};

String hdrModeDescription(HdrMode mode) => switch (mode) {
  HdrMode.auto => 'Let the player decide. Safest default.',
  HdrMode.passthrough =>
    'Send HDR metadata straight to the screen so an HDR display switches into '
        'HDR mode. Use on phones/TVs with a real HDR panel.',
  HdrMode.toneMapSdr =>
    'Convert HDR into SDR. Use this if HDR videos look washed out, grey or '
        'too dark on a normal (SDR) screen.',
};

void showHdrModeDialog(
  BuildContext context,
  WidgetRef ref,
  PlayerSettings settings,
) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('HDR mode'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<HdrMode>(
              groupValue: settings.hdrMode,
              onChanged: (val) {
                if (val == null) return;
                ref.read(playerSettingsProvider.notifier).setHdrMode(val);
                Navigator.pop<void>(ctx);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: HdrMode.values.map((m) {
                  return ListTile(
                    title: Text(hdrModeLabel(m)),
                    subtitle: Text(hdrModeDescription(m)),
                    isThreeLine: m != HdrMode.auto,
                    leading: Radio<HdrMode>(value: m),
                    onTap: () {
                      ref.read(playerSettingsProvider.notifier).setHdrMode(m);
                      Navigator.pop<void>(ctx);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void showToneMapDialog(
  BuildContext context,
  WidgetRef ref,
  PlayerSettings settings,
) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Tone-mapping curve'),
      content: SingleChildScrollView(
        child: RadioGroup<ToneMapCurve>(
          groupValue: settings.toneMapCurve,
          onChanged: (val) {
            if (val == null) return;
            ref.read(playerSettingsProvider.notifier).setToneMapCurve(val);
            Navigator.pop<void>(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ToneMapCurve.values.map((c) {
              return ListTile(
                title: Text(c.label),
                leading: Radio<ToneMapCurve>(value: c),
                onTap: () {
                  ref.read(playerSettingsProvider.notifier).setToneMapCurve(c);
                  Navigator.pop<void>(ctx);
                },
              );
            }).toList(),
          ),
        ),
      ),
    ),
  );
}

void showTargetPeakDialog(
  BuildContext context,
  WidgetRef ref,
  PlayerSettings settings,
) {
  // 0 is a sentinel for "auto-detect from the display".
  const presets = <int, String>{
    0: 'Auto-detect (recommended)',
    203: '203 nits — SDR reference',
    400: '400 nits — entry HDR',
    600: '600 nits — HDR600',
    1000: '1000 nits — typical HDR10',
    1500: '1500 nits — high-end',
    4000: '4000 nits — mastering',
  };

  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Display peak brightness'),
      content: SingleChildScrollView(
        child: RadioGroup<int>(
          groupValue: presets.containsKey(settings.hdrTargetPeak)
              ? settings.hdrTargetPeak
              : 0,
          onChanged: (val) {
            if (val == null) return;
            ref.read(playerSettingsProvider.notifier).setHdrTargetPeak(val);
            Navigator.pop<void>(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: presets.entries.map((e) {
              return ListTile(
                title: Text(e.value),
                leading: Radio<int>(value: e.key),
                onTap: () {
                  ref
                      .read(playerSettingsProvider.notifier)
                      .setHdrTargetPeak(e.key);
                  Navigator.pop<void>(ctx);
                },
              );
            }).toList(),
          ),
        ),
      ),
    ),
  );
}

void showMaxVolumeDialog(
  BuildContext context,
  WidgetRef ref,
  PlayerSettings settings,
) {
  showDialog<void>(
    context: context,
    builder: (ctx) {
      var value = settings.maxVolumePercent.toDouble().clamp(100.0, 200.0);
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          surfaceTintColor: Colors.transparent,
          title: const Text('Maximum volume'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${value.round()}%',
                style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Slider(
                value: value,
                min: 100,
                max: 200,
                divisions: 10,
                label: '${value.round()}%',
                onChanged: (v) => setState(() => value = v),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Above 100% the built-in player amplifies the audio. '
                      'Loud settings can distort quiet recordings and are not '
                      'available on the ExoPlayer/AVPlayer engine.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop<void>(ctx),
              child: Text(AppLocalizations.of(ctx)!.cancel),
            ),
            FilledButton(
              onPressed: () {
                ref
                    .read(playerSettingsProvider.notifier)
                    .setMaxVolumePercent(value.round());
                Navigator.pop<void>(ctx);
              },
              child: Text(AppLocalizations.of(ctx)!.save),
            ),
          ],
        ),
      );
    },
  );
}

/// Lets the user paste their own TMDB API key.
///
/// Why this exists: the key is normally baked in at build time via
/// `--dart-define=TMDB_API_KEY`, which comes from a CI secret. When that
/// secret is unset the APK ships with an empty key and every TMDB-backed
/// screen (Stream, Explore, Details) silently has nothing to show. This
/// dialog gives users a way out without rebuilding the app.
///
/// The key is validated against the live API before saving so a typo is
/// caught here rather than surfacing as an empty grid later.
void showTmdbApiKeyDialog(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  final current = ref.read(generalSettingsProvider).tmdbApiKey;
  final controller = TextEditingController(text: current);

  showDialog<void>(
    context: context,
    builder: (ctx) {
      var isChecking = false;
      String? errorText;

      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> save() async {
            final key = controller.text.trim();

            // Empty is a legitimate input: it clears the override and falls
            // back to the build-time key.
            if (key.isEmpty) {
              await ref
                  .read(generalSettingsProvider.notifier)
                  .setTmdbApiKey('');
              if (ctx.mounted) Navigator.pop<void>(ctx);
              return;
            }

            setState(() {
              isChecking = true;
              errorText = null;
            });

            var valid = false;
            try {
              final dio = ref.read(dioClientProvider);
              final res = await dio.get<Map<String, dynamic>>(
                '${TmdbConfig.baseUrl}/authentication',
                queryParameters: {'api_key': key},
                options: Options(
                  validateStatus: (s) => s != null && s < 500,
                  receiveTimeout: const Duration(seconds: 15),
                ),
              );
              valid = res.statusCode == 200;
            } catch (_) {
              // Network failure is not the same as a bad key; fall through to
              // the generic message so an offline user isn't told their key
              // is wrong.
              valid = false;
            }

            if (!ctx.mounted) return;

            if (!valid) {
              setState(() {
                isChecking = false;
                errorText =
                    'Could not verify this key. Check the key and your '
                    'connection, then try again.';
              });
              return;
            }

            await ref.read(generalSettingsProvider.notifier).setTmdbApiKey(key);

            // Force the TMDB-backed screens to refetch with the new key.
            ref.invalidate(streamBrowserProvider);

            if (ctx.mounted) Navigator.pop<void>(ctx);
          }

          return AlertDialog(
            surfaceTintColor: Colors.transparent,
            title: const Text('TMDB API key'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Stream and Explore use TMDB for posters, titles and '
                    'search. Paste a free API key to enable them.',
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'API key (v3 auth)',
                      hintText: 'e.g. 0123456789abcdef0123456789abcdef',
                      errorText: errorText,
                      prefixIcon: const Icon(Icons.vpn_key_rounded, size: 20),
                    ),
                    keyboardType: TextInputType.text,
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => launchUrl(
                      Uri.parse('https://www.themoviedb.org/settings/api'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.open_in_new_rounded, size: 16),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Get a free key from themoviedb.org',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isChecking) ...[
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Verifying key...'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isChecking ? null : () => Navigator.pop<void>(ctx),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: isChecking ? null : save,
                child: Text(l10n.save),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Shows a beautiful dialog with information about the developer.
void showDeveloperDialog(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      contentPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Profile Picture
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                  width: 4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.network(
                  'https://avatars.githubusercontent.com/u/74624467?v=4',
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: AppLoadingIndicator());
                  },
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.person_rounded, size: 50),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Name and Title
            Text(
              'Akash',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Fullstack & Flutter Developer',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            // Social Links
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                _SocialButton(
                  svgUrl:
                      'https://raw.githubusercontent.com/simple-icons/simple-icons/11.10.0/icons/github.svg',
                  color: const Color(0xFF909692),
                  onTap: () => launchUrl(
                    Uri.parse('https://github.com/akashdh11'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                _SocialButton(
                  svgUrl:
                      'https://raw.githubusercontent.com/simple-icons/simple-icons/11.10.0/icons/linkedin.svg',
                  color: const Color(0xFF2d65bc),
                  onTap: () => launchUrl(
                    Uri.parse('https://www.linkedin.com/in/akashdh11'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                _SocialButton(
                  svgUrl:
                      'https://raw.githubusercontent.com/simple-icons/simple-icons/11.10.0/icons/discord.svg',
                  color: const Color(0xFF5865F2),
                  onTap: () => launchUrl(
                    Uri.parse('https://discord.gg/73XGA8Mxn9'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                _SocialButton(
                  svgUrl:
                      'https://raw.githubusercontent.com/simple-icons/simple-icons/11.10.0/icons/telegram.svg',
                  color: const Color(0xFF5baae3),
                  onTap: () => launchUrl(
                    Uri.parse('https://t.me/+Ez5Vsv2pUUFjZmNl'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop<void>(context),
          child: Text(AppLocalizations.of(context)!.close),
        ),
      ],
    ),
  );
}

class _SocialButton extends StatelessWidget {
  final String svgUrl;
  final Color color;
  final VoidCallback onTap;

  const _SocialButton({
    required this.svgUrl,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: color.withValues(alpha: 0.15),
      shape: const CircleBorder(),
      child: IconButton(
        icon: SvgPicture.network(
          svgUrl,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          width: 24,
          height: 24,
          placeholderBuilder: (context) => AppLoadingIndicator(
            color: color.withValues(alpha: 0.5),
            constraints: BoxConstraints.tight(const Size(24, 24)),
          ),
        ),
        onPressed: onTap,
        tooltip: l10n.openLink,
      ),
    );
  }
}