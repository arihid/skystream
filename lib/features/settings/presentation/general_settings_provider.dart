import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/storage/settings_repository.dart';

part 'general_settings_provider.g.dart';

class GeneralSettings {
  final bool watchHistoryEnabled;
  final String defaultHomeScreen;
  final bool githubProxyEnabled;
  final bool alwaysOnTop;
  final String titlePosition;
  final bool isFullscreenEnabled;
  final String? targetDisplayId;

  const GeneralSettings({
    this.watchHistoryEnabled = true,
    this.defaultHomeScreen = '/home',
    this.githubProxyEnabled = false,
    this.alwaysOnTop = false,
    this.titlePosition = 'below',
    this.isFullscreenEnabled = false,
    this.targetDisplayId,
  });

  GeneralSettings copyWith({
    bool? watchHistoryEnabled,
    String? defaultHomeScreen,
    bool? githubProxyEnabled,
    bool? alwaysOnTop,
    String? titlePosition,
    bool? isFullscreenEnabled,
    String? targetDisplayId,
  }) {
    return GeneralSettings(
      watchHistoryEnabled: watchHistoryEnabled ?? this.watchHistoryEnabled,
      defaultHomeScreen: defaultHomeScreen ?? this.defaultHomeScreen,
      githubProxyEnabled: githubProxyEnabled ?? this.githubProxyEnabled,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      titlePosition: titlePosition ?? this.titlePosition,
      isFullscreenEnabled: isFullscreenEnabled ?? this.isFullscreenEnabled,
      targetDisplayId: targetDisplayId ?? this.targetDisplayId,
    );
  }
}

@Riverpod(keepAlive: true)
class GeneralSettingsNotifier extends _$GeneralSettingsNotifier {
  @override
  GeneralSettings build() {
    final repository = ref.watch(settingsRepositoryProvider);
    return GeneralSettings(
      watchHistoryEnabled: repository.isWatchHistoryEnabled(),
      defaultHomeScreen: repository.getDefaultHomeScreen(),
      githubProxyEnabled: repository.isGithubProxyEnabled(),
      alwaysOnTop: repository.isAlwaysOnTop(),
      titlePosition: repository.getTitlePosition(),
      isFullscreenEnabled: false,
      targetDisplayId: null,
    );
  }

  Future<void> setWatchHistoryEnabled(bool enabled) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setWatchHistoryEnabled(enabled);
    state = state.copyWith(watchHistoryEnabled: enabled);
  }

  Future<void> setDefaultHomeScreen(String path) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setDefaultHomeScreen(path);
    state = state.copyWith(defaultHomeScreen: path);
  }

  Future<void> setGithubProxyEnabled(bool enabled) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setGithubProxyEnabled(enabled);
    state = state.copyWith(githubProxyEnabled: enabled);
  }

  Future<void> setAlwaysOnTop(bool enabled) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setAlwaysOnTop(enabled);
    state = state.copyWith(alwaysOnTop: enabled);
  }

  Future<void> setTitlePosition(String position) async {
    final repository = ref.read(settingsRepositoryProvider);
    await repository.setTitlePosition(position);
    state = state.copyWith(titlePosition: position);
  }
  
  Future<void> setFullscreenEnabled(bool enabled) async {
    state = state.copyWith(isFullscreenEnabled: enabled);
  }

  Future<void> setTargetDisplayId(String? displayId) async {
    state = state.copyWith(targetDisplayId: displayId);
  }
  
}
