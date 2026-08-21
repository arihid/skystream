import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import '../../../core/storage/storage_service.dart';

part 'big_picture_provider.g.dart';

class BigPictureState {
  final bool isEnabled;
  final bool keepAcrossRestarts;
  final String? targetDisplayId;

  BigPictureState({
    required this.isEnabled,
    required this.keepAcrossRestarts,
    this.targetDisplayId,
  });

  BigPictureState copyWith({
    bool? isEnabled,
    bool? keepAcrossRestarts,
    String? targetDisplayId,
  }) {
    return BigPictureState(
      isEnabled: isEnabled ?? this.isEnabled,
      keepAcrossRestarts: keepAcrossRestarts ?? this.keepAcrossRestarts,
      targetDisplayId: targetDisplayId ?? this.targetDisplayId,
    );
  }
}

@Riverpod(keepAlive: true)
class BigPictureMode extends _$BigPictureMode {
  @override
  BigPictureState build() {
    final storage = ref.read(storageServiceProvider);
    
    // Default to true if TV profile is detected, otherwise read storage
    return BigPictureState(
      isEnabled: storage.getBigPictureMode() ?? false,
      keepAcrossRestarts: storage.getKeepBigPicture() ?? false,
      targetDisplayId: storage.getTargetDisplayId(),
    );
  }

  /// Initialize window state on boot
  Future<void> initialize(List<String> launchArgs) async {
    final storage = ref.read(storageServiceProvider);
    
    bool shouldEnable = state.isEnabled;

    // Launch arg overrides everything
    if (launchArgs.contains('--big-picture')) {
      shouldEnable = true;
    } else if (!state.keepAcrossRestarts) {
      // If we didn't want to keep it across restarts, disable it now.
      shouldEnable = false;
      await storage.setBigPictureMode(false);
    }

    if (shouldEnable) {
      await enableBigPicture();
    }
  }

  Future<void> toggleBigPicture(bool enable) async {
    if (enable == state.isEnabled) return;
    
    if (enable) {
      await enableBigPicture();
    } else {
      await disableBigPicture();
    }
  }

  Future<void> enableBigPicture() async {
    state = state.copyWith(isEnabled: true);
    await ref.read(storageServiceProvider).setBigPictureMode(true);

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      if (state.targetDisplayId != null) {
        try {
          List<Display> displays = await screenRetriever.getAllDisplays();
          Display target = displays.firstWhere((d) => d.id == state.targetDisplayId);
          if (target.visiblePosition != null) {
             await windowManager.setPosition(target.visiblePosition!);
          }
        } catch (_) {
          // Display unplugged/not found, defaults to current monitor
        }
      }
      await windowManager.setFullScreen(true);
    }
  }

  Future<void> disableBigPicture() async {
    state = state.copyWith(isEnabled: false);
    await ref.read(storageServiceProvider).setBigPictureMode(false);

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.setFullScreen(false);
      await windowManager.center(); // Bring it back gracefully to center
    }
  }

  Future<void> updateSettings({bool? keepAcrossRestarts, String? targetDisplayId}) async {
    final storage = ref.read(storageServiceProvider);

    if (keepAcrossRestarts != null) {
      await storage.setKeepBigPicture(keepAcrossRestarts);
    }
    if (targetDisplayId != null) {
      await storage.setTargetDisplayId(targetDisplayId);
    }

    state = state.copyWith(
      keepAcrossRestarts: keepAcrossRestarts,
      targetDisplayId: targetDisplayId ?? state.targetDisplayId,
    );
  }
}