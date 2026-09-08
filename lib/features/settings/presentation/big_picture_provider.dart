import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:window_manager/window_manager.dart';

part 'big_picture_provider.g.dart';

class BigPictureState {
  final bool isEnabled;

  BigPictureState({required this.isEnabled});
}

@Riverpod(keepAlive: true)
class BigPictureMode extends _$BigPictureMode {
  @override
  BigPictureState build() {
    return BigPictureState(isEnabled: false);
  }

  /// Initialize window state on boot (Only respects launch arguments now)
  void initialize(List<String> launchArgs) {
    if (launchArgs.contains('--big-picture') ||
        launchArgs.contains('--bigpicture')) {
      state = BigPictureState(isEnabled: true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!kIsWeb &&
            (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
          windowManager.setFullScreen(true);
        }
      });
    }
  }

  Future<void> toggleBigPicture(bool enable) async {
    if (enable == state.isEnabled) return;

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.setFullScreen(enable);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    state = BigPictureState(isEnabled: enable);
  }
}
