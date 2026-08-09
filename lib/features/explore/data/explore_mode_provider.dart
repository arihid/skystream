import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'explore_mode_provider.g.dart';

const String _kExploreModeKey = 'explore_mode_is_anime';

@riverpod
class ExploreMode extends _$ExploreMode {
  @override
  bool build() {
    _loadPersistedMode();
    return false; // false = Movies & Shows, true = Anime
  }

  Future<void> _loadPersistedMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getBool(_kExploreModeKey);
      if (savedMode != null && state != savedMode) {
        state = savedMode;
      }
    } catch (_) {}
  }

  void setAnimeMode(bool isAnime) {
    state = isAnime;
    _persistMode(isAnime);
  }

  Future<void> _persistMode(bool isAnime) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kExploreModeKey, isAnime);
    } catch (_) {}
  }
}
