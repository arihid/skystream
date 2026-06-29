import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/storage/settings_repository.dart';

part 'general_settings_provider.g.dart';

class GeneralSettings {
  final bool watchHistoryEnabled;
  final String defaultHomeScreen;
  final bool githubProxyEnabled;
  final bool isFullscreenEnabled;
  final String? targetDisplayId;

  const GeneralSettings({
    this.watchHistoryEnabled = true,
    this.defaultHomeScreen = '/home',
    this.githubProxyEnabled = false,
    this.isFullscreenEnabled = false,
    this.targetDisplayId,
  });

  
  GeneralSettings copyWith({
    bool? watchHistoryEnabled,
    String? defaultHomeScreen,
    bool? githubProxyEnabled, 
    bool? isFullscreenEnabled,
    String? targetDisplayId,
  }) {
    return GeneralSettings(
      watchHistoryEnabled: watchHistoryEnabled ?? this.watchHistoryEnabled,
      defaultHomeScreen: defaultHomeScreen ?? this.defaultHomeScreen,
      githubProxyEnabled: githubProxyEnabled ?? this.githubProxyEnabled,
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
      isFullscreenEnabled: repository.isFullscreenEnabled(),
      targetDisplayId: repository.getTargetDisplayId(),
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

  void setFullscreenEnabled(bool val) {
    state = state.copyWith(isFullscreenEnabled: val);
    final repository = ref.read(settingsRepositoryProvider);
    repository.setFullscreenEnabled(val);
  }

  void setTargetDisplayId(String? id) {
    state = state.copyWith(targetDisplayId: id);
    final repository = ref.read(settingsRepositoryProvider);
    repository.setTargetDisplayId(id);
  }
}
