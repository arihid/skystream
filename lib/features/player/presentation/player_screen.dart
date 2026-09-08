import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/core/input/gamepad_actions.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_view/video_view.dart' as vv;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/providers/device_info_provider.dart';
import '../../../../features/settings/presentation/player_settings_provider.dart';
import '../../../../features/settings/presentation/general_settings_provider.dart';

// Gamepad Intents
import '../../../../features/settings/presentation/big_picture_provider.dart';

import 'widgets/skystream_player_controls.dart';
import 'widgets/hotstar_player_style.dart';
import 'player_controller.dart';
import 'player_gesture_handler.dart';

TextStyle _getSubtitleTextStyle(String? fontFamily, TextStyle baseStyle) {
  if (fontFamily == null) return baseStyle;
  switch (fontFamily.toLowerCase()) {
    case 'open sans':
      return GoogleFonts.openSans(textStyle: baseStyle);
    case 'poppins':
      return GoogleFonts.poppins(textStyle: baseStyle);
    case 'ubuntu':
      return GoogleFonts.ubuntu(textStyle: baseStyle);
    default:
      return baseStyle.copyWith(fontFamily: fontFamily);
  }
}

class PlayerScreen extends ConsumerStatefulWidget {
  final MultimediaItem item;
  final String videoUrl;
  final Episode? episode;
  final List<StreamResult>? preloadedStreams;

  const PlayerScreen({
    super.key,
    required this.item,
    required this.videoUrl,
    this.episode,
    this.preloadedStreams,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _videoController; // media_kit renderer
  late final vv.VideoController
  _videoViewController; // video_view (ExoPlayer/AVPlayer)

  final ValueNotifier<BoxFit> _videoFit = ValueNotifier(BoxFit.contain);
  final ValueNotifier<bool> _controlsVisible = ValueNotifier(false);

  final GlobalKey<SkyStreamPlayerControlsState> _controlsKeyFinal = GlobalKey();

  final FocusNode _rootFocusNode = FocusNode(debugLabel: 'player_root');
  DateTime? _lastBackAt;

  bool _isTv = false;
  bool _isTablet = false;
  bool _wasPlayingBeforeBackground = false;
  bool _spaceHeldForSpeed = false;
  double? _speedBeforeSpaceHold;
  Timer? _spaceHoldTimer;
  bool _wasFullscreen = false;

  bool _customFontLoaded = false;
  String? _lastLoadedFontPath;
  SubtitleViewConfiguration? _cachedSubtitleConfig;
  String? _cachedSubtitleKey;

  // ignore: unused_element
  SubtitleViewConfiguration _getOrCreateSubtitleConfiguration(
    PlayerSettings settings,
  ) {
    final key =
        '${settings.subTypefaceFilePath}_${settings.subTypeface}_'
        '${settings.subFixedTextSize}_${settings.subtitleSize}_'
        '${settings.subForegroundColor}_${settings.subtitleColor}_'
        '${settings.subEdgeColor}_${settings.subEdgeSize}_'
        '${settings.subEdgeType}_${settings.subBackgroundColor}_'
        '${settings.subtitleBackgroundColor}_${settings.subBackgroundOpacity}_'
        '${settings.subBold}_${settings.subItalic}_${settings.subAlignment}_$_customFontLoaded';

    if (_cachedSubtitleConfig != null && _cachedSubtitleKey == key) {
      return _cachedSubtitleConfig!;
    }
    _cachedSubtitleKey = key;
    _cachedSubtitleConfig = _buildSubtitleConfiguration(settings);
    return _cachedSubtitleConfig!;
  }

  Future<void> _loadCustomFontIfNeeded(PlayerSettings settings) async {
    final path = settings.subTypefaceFilePath;
    if (path != null && path.isNotEmpty && path != _lastLoadedFontPath) {
      _lastLoadedFontPath = path;
      try {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final fontLoader = FontLoader('CustomSubtitleFont');
          fontLoader.addFont(Future.value(ByteData.sublistView(bytes)));
          await fontLoader.load();
          if (mounted) {
            setState(() {
              _customFontLoaded = true;
            });
          }
        }
      } catch (e) {
        debugPrint("Failed to load custom font in player: $e");
      }
    }
  }

  late final PlayerController _playerController;
  ProviderSubscription<AsyncValue<PlayerSettings>>? _settingsSub;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);

    final deviceProfile = ref.read(deviceProfileProvider).asData?.value;
    _isTv = deviceProfile?.isTv ?? false;
    _isTablet = deviceProfile?.isTablet ?? false;

    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    WakelockPlus.enable();

    if (!Platform.isAndroid && !Platform.isIOS) {
      windowManager.isFullScreen().then((isFull) {
        if (mounted) _wasFullscreen = isFull;
      });
    }

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 128 * 1024 * 1024, // 128MB
      ),
    );

    if (_player.platform is NativePlayer) {
      final native = _player.platform as NativePlayer;
      native.setProperty('network-timeout', '120');
      native.setProperty('force-seekable', 'yes');
      native.setProperty('demuxer-lavf-probesize', '33554432');
      native.setProperty('demuxer-lavf-analyzeduration', '30');
      if (kDebugMode) {
        native.setProperty('msg-level', 'hls=v,lavf=v,ffmpeg/demuxer=v');
      }
      native.setProperty('sub-visibility', 'no');
    }

    _videoController = VideoController(_player);
    _videoViewController = vv.VideoController(autoPlay: true);

    _settingsSub = ref.listenManual<AsyncValue<PlayerSettings>>(
      playerSettingsProvider,
      (_, next) {
        final settings = next.asData?.value;
        if (settings == null) return;
        if (settings.defaultResizeMode == "Zoom") {
          _videoFit.value = BoxFit.cover;
        } else if (settings.defaultResizeMode == "Stretch") {
          _videoFit.value = BoxFit.fill;
        }
        _loadCustomFontIfNeeded(settings);
      },
      fireImmediately: true,
    );

    _playerController = ref.read(playerControllerProvider.notifier);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playerController.init(
        player: _player,
        item: widget.item,
        videoUrl: widget.videoUrl,
        episode: widget.episode,
        preloadedStreams: widget.preloadedStreams,
        videoViewController: _videoViewController,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _playerController.setAppBackgrounded(true);
      final ctrl = ref.read(playerControllerProvider);
      _wasPlayingBeforeBackground = ctrl.useExoPlayer
          ? _videoViewController.playbackState.value ==
                vv.VideoControllerPlaybackState.playing
          : _player.state.playing;
      _playerController.saveProgress();
      _playerController.pause();

      _spaceHoldTimer?.cancel();
      _spaceHoldTimer = null;
      if (_spaceHeldForSpeed) {
        final previousSpeed = _speedBeforeSpaceHold ?? 1.0;
        _spaceHeldForSpeed = false;
        _speedBeforeSpaceHold = null;
        unawaited(_playerController.setPlaybackSpeed(previousSpeed));
      }
    } else if (state == AppLifecycleState.resumed) {
      _playerController.setAppBackgrounded(false);
      final ctrl = ref.read(playerControllerProvider);
      final isCurrentlyPlaying = ctrl.useExoPlayer
          ? _videoViewController.playbackState.value ==
                vv.VideoControllerPlaybackState.playing
          : _player.state.playing;
      if (isCurrentlyPlaying) {
        WakelockPlus.enable();
      }

      if (_wasPlayingBeforeBackground) {
        _wasPlayingBeforeBackground = false;
        WakelockPlus.enable();
        _playerController.play();
      }
    }
  }

  void _updateResizeMode(BoxFit mode) {
    if (mounted) _videoFit.value = mode;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      if (!_isTv) {
        if (_isTablet) {
          SystemChrome.setPreferredOrientations([]);
        } else {
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        }
      }
      if (!Platform.isAndroid && !Platform.isIOS) {
        try {
          final isAppFullscreen = ref
              .read(generalSettingsProvider)
              .isFullscreenEnabled;
          if (!_wasFullscreen && !isAppFullscreen) {
            windowManager.setFullScreen(false);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('PlayerScreen._handleBack: $e');
        }
      }
    }

    _settingsSub?.close();
    _playerController.disposeController();

    _player.dispose();
    _videoViewController.dispose();
    _controlsVisible.dispose();
    _videoFit.dispose();
    _rootFocusNode.dispose();

    WakelockPlus.disable();

    unawaited(ScreenBrightness().resetApplicationScreenBrightness());
    _spaceHoldTimer?.cancel();
    if (_spaceHeldForSpeed) {
      final previousSpeed = _speedBeforeSpaceHold ?? 1.0;
      unawaited(_playerController.setPlaybackSpeed(previousSpeed));
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      try {
        if (Platform.isWindows || Platform.isLinux) {
          // windowManager.setTitleBarStyle(TitleBarStyle.normal);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('PlayerScreen.dispose: $e');
      }
    }
    super.dispose();
  }

  bool _isPlayActivationKey(KeyEvent event) =>
      event.logicalKey == LogicalKeyboardKey.select ||
      event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.mediaPlayPause;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final rootHasFocus = FocusManager.instance.primaryFocus == node;
    final isBigPicture = ref.read(bigPictureModeProvider).isEnabled || _isTv;

    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      return _consumeBack() ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    if (!isBigPicture &&
        rootHasFocus &&
        event.logicalKey == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        _spaceHoldTimer ??= Timer(const Duration(milliseconds: 260), () {
          if (!mounted || _spaceHeldForSpeed) return;
          _spaceHeldForSpeed = true;
          _speedBeforeSpaceHold = ref
              .read(playerControllerProvider)
              .playbackSpeed;
          unawaited(
            ref.read(playerControllerProvider.notifier).setPlaybackSpeed(2.0),
          );
          ref
              .read(playerGestureHandlerProvider.notifier)
              .showToast("2.0x", Icons.fast_forward_rounded);
        });
        return KeyEventResult.handled;
      }
      if (event is KeyRepeatEvent) {
        if (!_spaceHeldForSpeed) {
          _spaceHoldTimer?.cancel();
          _spaceHoldTimer = null;
          _spaceHeldForSpeed = true;
          _speedBeforeSpaceHold = ref
              .read(playerControllerProvider)
              .playbackSpeed;
          unawaited(
            ref.read(playerControllerProvider.notifier).setPlaybackSpeed(2.0),
          );
          ref
              .read(playerGestureHandlerProvider.notifier)
              .showToast("2.0x", Icons.fast_forward_rounded);
        }
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        _spaceHoldTimer?.cancel();
        _spaceHoldTimer = null;
        if (!_spaceHeldForSpeed) {
          _controlsKeyFinal.currentState?.togglePlayPause();
          _controlsKeyFinal.currentState?.onUserInteraction();
          return KeyEventResult.handled;
        }
        final previousSpeed = _speedBeforeSpaceHold ?? 1.0;
        _spaceHeldForSpeed = false;
        _speedBeforeSpaceHold = null;
        unawaited(
          ref
              .read(playerControllerProvider.notifier)
              .setPlaybackSpeed(previousSpeed),
        );
        ref
            .read(playerGestureHandlerProvider.notifier)
            .showToast(
              "${previousSpeed.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}x",
              Icons.play_arrow_rounded,
            );
        return KeyEventResult.handled;
      }
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (!rootHasFocus) {
      if (!isBigPicture) {
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _controlsKeyFinal.currentState?.triggerSeek(true);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _controlsKeyFinal.currentState?.triggerSeek(false);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _controlsKeyFinal.currentState?.changeVolume(0.05);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _controlsKeyFinal.currentState?.changeVolume(-0.05);
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored; // Let focus traverse natively!
    }

    if (isBigPicture && _controlsVisible.value) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight ||
          _isPlayActivationKey(event)) {
        _controlsKeyFinal.currentState?.showControls();
        return KeyEventResult.handled;
      }
    }

    if (isBigPicture && !_controlsVisible.value) {
      if (event.logicalKey == LogicalKeyboardKey.goBack ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        return KeyEventResult.ignored;
      }
      _controlsKeyFinal.currentState?.showControls();
      return KeyEventResult.handled;
    }

    if (_isPlayActivationKey(event)) {
      _controlsKeyFinal.currentState?.togglePlayPause();
      _controlsKeyFinal.currentState?.onUserInteraction();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyM) {
      _controlsKeyFinal.currentState?.toggleMute();
      _controlsKeyFinal.currentState?.onUserInteraction();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      _controlsKeyFinal.currentState?.cycleResize();
      _controlsKeyFinal.currentState?.onUserInteraction();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      final isAppFullscreen = ref
          .read(generalSettingsProvider)
          .isFullscreenEnabled;
      if (!isAppFullscreen) {
        _controlsKeyFinal.currentState?.toggleFullscreen();
        _controlsKeyFinal.currentState?.onUserInteraction();
      }
      return KeyEventResult.handled;
    }

    if (isBigPicture) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _controlsKeyFinal.currentState?.changeVolume(0.05);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _controlsKeyFinal.currentState?.changeVolume(-0.05);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _controlsKeyFinal.currentState?.triggerSeek(true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _controlsKeyFinal.currentState?.triggerSeek(false);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _consumeBack() {
    final now = DateTime.now();
    if (_lastBackAt != null &&
        now.difference(_lastBackAt!) < const Duration(milliseconds: 200)) {
      return true;
    }
    if (_controlsKeyFinal.currentState?.isFullscreen == true) {
      _lastBackAt = now;
      unawaited(_controlsKeyFinal.currentState?.toggleFullscreen());
      return true;
    }
    final s = ref.read(playerControllerProvider);
    if (s.showSourcesPanel || s.showEpisodeList || s.showContentPanel) {
      _lastBackAt = now;
      _controlsKeyFinal.currentState?.closeActivePanel();
      return true;
    }
    if (_controlsVisible.value) {
      final isBigPicture = ref.read(bigPictureModeProvider).isEnabled || _isTv;
      if (isBigPicture) {
        final isPlaying =
            ref.read(playerControllerProvider.select((s) => s.useExoPlayer))
            ? _videoViewController.playbackState.value ==
                  vv.VideoControllerPlaybackState.playing
            : _player.state.playing;
        if (isPlaying) {
          _lastBackAt = now;
          _controlsKeyFinal.currentState?.hideControls();
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _handleBack() async {
    if (!context.mounted) return;

    if (!Platform.isAndroid && !Platform.isIOS) {
      try {
        await windowManager.setFullScreen(false);
        await Future<void>.delayed(const Duration(seconds: 1));
      } catch (e) {
        if (kDebugMode) debugPrint('PlayerScreen._handleBack: $e');
      }
    }

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = ref.watch(
      playerControllerProvider.select((s) => s.errorMessage),
    );
    final isLoading = ref.watch(
      playerControllerProvider.select((s) => s.isLoading),
    );

    if (errorMessage != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _handleBack();
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                _handleBack();
                return null;
              },
            ),
          },
          child: Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 56,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!.playbackError,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        errorMessage,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        autofocus: true,
                        onPressed: _handleBack,
                        icon: const Icon(Icons.arrow_back),
                        label: Text(AppLocalizations.of(context)!.goBack),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: _controlsVisible,
      builder: (context, controlsVisible, _) {
        final isBigPicture =
            ref.watch(bigPictureModeProvider).isEnabled || _isTv;

        Widget scaffoldBody = Focus(
          focusNode: _rootFocusNode,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
            },
            child: Stack(
              children: [
                RepaintBoundary(
                  child: ValueListenableBuilder<BoxFit>(
                    valueListenable: _videoFit,
                    builder: (_, fit, child) => Center(
                      child: Consumer(
                        builder: (context, ref, _) {
                          final useExoPlayer = ref.watch(
                            playerControllerProvider.select(
                              (s) => s.useExoPlayer,
                            ),
                          );
                          if (useExoPlayer) {
                            return vv.VideoView(
                              controller: _videoViewController,
                              videoFit: fit,
                            );
                          }
                          return Video(
                            controller: _videoController,
                            fit: fit,
                            subtitleViewConfiguration:
                                const SubtitleViewConfiguration(
                                  visible: false,
                                  style: TextStyle(color: Colors.transparent),
                                ),
                            controls: (state) => const SizedBox.shrink(),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final useExoPlayer = ref.watch(
                      playerControllerProvider.select((s) => s.useExoPlayer),
                    );
                    if (useExoPlayer) {
                      return const SizedBox.shrink();
                    }

                    final subtitleSettings = ref
                        .watch(playerSettingsProvider)
                        .asData
                        ?.value;

                    return Positioned(
                      bottom:
                          (controlsVisible
                              ? HotstarPlayerStyle.bottomChromeHeight
                              : 20.0) +
                          ((100 -
                                  (subtitleSettings?.subtitlePosition ??
                                      100.0)) *
                              (MediaQuery.sizeOf(context).height * 0.008)),
                      left: 20,
                      right: 20,
                      child: SubtitleView(
                        controller: _videoController,
                        configuration: SubtitleViewConfiguration(
                          style: TextStyle(
                            fontSize: subtitleSettings?.subtitleSize ?? 22.0,
                            color: Color(
                              subtitleSettings?.subtitleColor ?? 0xFFFFFFFF,
                            ),
                            backgroundColor:
                                Color(
                                  subtitleSettings?.subtitleBackgroundColor ??
                                      0x00000000,
                                ).withValues(
                                  alpha:
                                      subtitleSettings
                                          ?.subtitleBackgroundOpacity ??
                                      0.0,
                                ),
                            shadows: const [
                              Shadow(
                                offset: Offset(0, 1),
                                blurRadius: 2,
                                color: Colors.black,
                              ),
                            ],
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    );
                  },
                ),
                Positioned.fill(
                  child: RepaintBoundary(
                    child: SkyStreamPlayerControls(
                      key: _controlsKeyFinal,
                      isLoading: isLoading,
                      player: _player,
                      videoViewController: _videoViewController,
                      title: widget.item.title,
                      subtitle: ref
                          .read(playerControllerProvider)
                          .streamSubtitle,
                      backdropUrl: widget.item.backdropImageUrl,
                      logoUrl: widget.item.logoUrl,
                      onResize: _updateResizeMode,
                      onBackPointer: _handleBack,
                      onRequestRootFocus: () => _rootFocusNode.requestFocus(),
                      onVisibilityChanged: (v) {
                        if (mounted) {
                          _controlsVisible.value = v;
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        // ONLY wrap in Actions if we are in Big Picture / TV Mode
        if (isBigPicture) {
          scaffoldBody = Actions(
            actions: <Type, Action<Intent>>{
              AppLeftTriggerIntent: CallbackAction<AppLeftTriggerIntent>(
                onInvoke: (_) {
                  _controlsKeyFinal.currentState?.triggerSeek(true);
                  return null;
                },
              ),
              AppRightTriggerIntent: CallbackAction<AppRightTriggerIntent>(
                onInvoke: (_) {
                  _controlsKeyFinal.currentState?.triggerSeek(false);
                  return null;
                },
              ),
              AppSecondaryIntent: CallbackAction<AppSecondaryIntent>(
                onInvoke: (_) {
                  // X Button -> Dismiss / Close / Start Over
                  _controlsKeyFinal.currentState
                      ?.triggerSecondaryOverlayAction();
                  return null;
                },
              ),
              AppTertiaryIntent: CallbackAction<AppTertiaryIntent>(
                onInvoke: (_) {
                  // Y Button -> Skip / Resume / Next Ep
                  _controlsKeyFinal.currentState?.triggerActiveOverlay();
                  return null;
                },
              ),
            },
            child: scaffoldBody,
          );
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            if (_consumeBack()) return;
            await _handleBack();
          },
          child: Scaffold(body: scaffoldBody),
        );
      },
    );
  }

  SubtitleViewConfiguration _buildSubtitleConfiguration(
    PlayerSettings settings,
  ) {
    String? fontFamily;
    const List<String> builtInFonts = [
      'Normal (system sans-serif)',
      'Trebuchet MS',
      'Netflix Sans',
      'Google Sans',
      'Open Sans',
      'Futura',
      'Consolas',
      'Gotham',
      'Lucida Grande',
      'STIX General',
      'Times New Roman',
      'Verdana',
      'Ubuntu',
      'Comic Sans MS',
      'Poppins',
    ];

    if (settings.subTypefaceFilePath != null &&
        settings.subTypefaceFilePath!.isNotEmpty &&
        _customFontLoaded) {
      fontFamily = 'CustomSubtitleFont';
    } else if (settings.subTypeface != null &&
        settings.subTypeface! > 0 &&
        settings.subTypeface! < builtInFonts.length) {
      fontFamily = builtInFonts[settings.subTypeface!];
    }

    final fontSize = settings.subFixedTextSize ?? settings.subtitleSize;
    final fgColor = Color(
      settings.subForegroundColor != 0xFFFFFFFF
          ? settings.subForegroundColor
          : settings.subtitleColor,
    );

    final edgeColor = Color(settings.subEdgeColor);
    final edgeSize = settings.subEdgeSize ?? 2.5;

    List<Shadow>? shadows;
    switch (settings.subEdgeType) {
      case 0:
        shadows = null;
        break;
      case 1:
        shadows = [
          Shadow(offset: const Offset(-1.5, -1.5), color: edgeColor),
          Shadow(offset: const Offset(1.5, -1.5), color: edgeColor),
          Shadow(offset: const Offset(1.5, 1.5), color: edgeColor),
          Shadow(offset: const Offset(-1.5, 1.5), color: edgeColor),
          Shadow(offset: const Offset(0, -1.5), color: edgeColor),
          Shadow(offset: const Offset(0, 1.5), color: edgeColor),
          Shadow(offset: const Offset(-1.5, 0), color: edgeColor),
          Shadow(offset: const Offset(1.5, 0), color: edgeColor),
        ];
        break;
      case 2:
        shadows = [
          Shadow(
            offset: const Offset(-1, -1),
            color: edgeColor.withValues(alpha: 0.5),
          ),
          Shadow(
            offset: const Offset(1, 1),
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ];
        break;
      case 3:
        shadows = [
          Shadow(
            offset: Offset(edgeSize, edgeSize),
            blurRadius: 2.0,
            color: edgeColor,
          ),
        ];
        break;
      case 4:
        shadows = [
          Shadow(offset: const Offset(1, 1), color: edgeColor),
          Shadow(
            offset: const Offset(2, 2),
            color: edgeColor.withValues(alpha: 0.5),
          ),
        ];
        break;
    }

    final bgColorValue = settings.subBackgroundColor != 0x00000000
        ? settings.subBackgroundColor
        : settings.subtitleBackgroundColor;
    final bgOpacity = settings.subBackgroundOpacity;
    final Color? backgroundColor =
        (bgColorValue != 0x00000000 && bgOpacity > 0.0)
        ? Color(bgColorValue).withValues(alpha: bgOpacity)
        : null;

    var baseStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: settings.subBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: settings.subItalic ? FontStyle.italic : FontStyle.normal,
      color: fgColor,
      backgroundColor: backgroundColor,
      shadows: shadows,
    );

    baseStyle = _getSubtitleTextStyle(fontFamily, baseStyle);

    final alignmentCode = settings.subAlignment ?? 2;
    final textAlign = switch (alignmentCode) {
      1 || 4 || 7 => TextAlign.left,
      3 || 6 || 9 => TextAlign.right,
      _ => TextAlign.center,
    };

    return SubtitleViewConfiguration(
      visible: true,
      style: baseStyle,
      textAlign: textAlign,
      padding: EdgeInsets.zero,
    );
  }
}
