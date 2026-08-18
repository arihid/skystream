import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter/services.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:video_view/video_view.dart' as vv;
import '../../../../l10n/generated/app_localizations.dart';
import '../player_controller.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/models/torrent_status.dart';
import '../components/torrent_info_widget.dart';
import '../../../settings/presentation/player_settings_provider.dart';
import '../../../../core/providers/device_info_provider.dart';
import '../../../../core/utils/responsive_breakpoints.dart';
import 'player_stream_widgets.dart';
import 'player_control_components.dart';
import 'next_episode_overlay.dart';
import 'resume_prompt_overlay.dart';
import 'player_side_panel.dart';
import 'player_bottom_sheets.dart';
import 'player_loading_overlay.dart';
import 'player_osd_overlay.dart';
import 'skip_segment_overlay.dart';
import 'hotstar_player_style.dart';
import '../player_platform_service.dart';
import '../player_gesture_handler.dart';
import 'player_metadata_scrim.dart';
import '../../../skip/data/skip_service.dart';

class SkyStreamPlayerControls extends ConsumerStatefulWidget {
  final Player player;
  final vv.VideoController? videoViewController;
  final String? title;
  final String? subtitle;
  final VoidCallback? onBackPointer;
  final List<StreamResult>? streams;
  final StreamResult? currentStream;

  final List<SubtitleFile>? externalSubtitles;
  final TorrentStatus? torrentStatus;
  final void Function(StreamResult)? onStreamSelected;
  final void Function(int)? onTorrentFileSelected;
  final void Function(BoxFit)? onResize;
  final void Function(bool)? onVisibilityChanged;

  final VoidCallback? onRequestRootFocus;
  final String? backdropUrl;
  final String? logoUrl;

  const SkyStreamPlayerControls({
    super.key,
    required this.player,
    this.videoViewController,
    this.title,
    this.subtitle,
    this.onBackPointer,
    this.streams,
    this.currentStream,
    this.externalSubtitles,
    this.torrentStatus,
    this.onStreamSelected,
    this.onTorrentFileSelected,
    this.onResize,
    this.onVisibilityChanged,
    this.onRequestRootFocus,
    this.backdropUrl,
    this.logoUrl,
    this.isLoading = false,
  });

  final bool isLoading;

  @override
  ConsumerState<SkyStreamPlayerControls> createState() => SkyStreamPlayerControlsState();
}

class SkyStreamPlayerControlsState extends ConsumerState<SkyStreamPlayerControls> with SingleTickerProviderStateMixin {
  bool _isVisible = false;
  bool _isIpad = false;
  bool _isTv = false;
  bool _isInPip = false;
  bool _isDesktop = false;

  bool get _isBigPicture => _isTv || _isDesktop;

  void togglePlayPause() => _togglePlay();

  bool _showTorrentInfo = false; 
  Timer? _hideTimer;

  final GlobalKey<PlayerMetadataScrimState> _metadataScrimKey = GlobalKey();
  bool _isLocked = false;

  late AnimationController _seekAnimController;
  bool _isSeekingLeft = false;
  int _seekDisplaySeconds = 10;

  int _resizeMode = 0;
  bool _touchHeldForSpeed = false;
  double? _speedBeforeTouchHold;

  late bool _isPlaying;
  late Duration _position;
  late Duration _duration;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  late final PlayerPlatformService _platformService;
  Offset? _tapPosition;
  Duration _animDuration = HotstarPlayerStyle.controlFadeDuration;
  bool _isFullscreen = false;
  bool get isFullscreen => _isFullscreen;

  late final FocusNode _playFocusNode;
  late final FocusNode _backFocusNode;
  late final FocusNode _scrubFocusNode;
  
  FocusNode? _lastFocusedNode;
  
  bool _isSkipActive = false;
  ProviderSubscription<dynamic>? _revertMessageSub;

  @override
  void initState() {
    super.initState();
    final deviceProfile = ref.read(deviceProfileProvider).asData?.value;
    _isTv = deviceProfile?.isTv ?? false;
    _isIpad = Platform.isIOS && (deviceProfile?.isTablet ?? false);
    _isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    _platformService = PlayerPlatformService();
    ref.read(playerGestureHandlerProvider.notifier).init(
          getSettings: () async => await ref.read(playerSettingsProvider.future),
          isTv: _isTv,
          isDesktop: _isDesktop,
          getDuration: () => _duration,
          getPosition: () => _position,
          canSeek: () => ref.read(playerControllerProvider).canSeek,
          getMaxVolumeLevel: () => ref.read(playerControllerProvider).supportsVolumeBoost ? 2.0 : 1.0,
          onInteraction: () {
            if (!_isVisible) {
              setState(() => _isVisible = true);
              widget.onVisibilityChanged?.call(true);
            }
            _startHideTimer();
          },
          onHideControls: () {
            _cancelHideTimer();
            if (_isVisible && mounted) {
              setState(() => _isVisible = false);
              widget.onVisibilityChanged?.call(false);
            }
          },
          onSeekRelative: (amount) async => _seekRelative(amount),
          onSeekTo: (position) => ref.read(playerControllerProvider.notifier).seekTo(position),
          getVolumeLevel: () => ref.read(playerControllerProvider.notifier).getVolumeLevel(),
          setVolumeLevel: (value) => ref.read(playerControllerProvider.notifier).setVolumeLevel(value),
          onVolumeChange: (step) => ref.read(playerControllerProvider.notifier).changeVolume(step),
          toggleMuteLevel: () => ref.read(playerControllerProvider.notifier).toggleMute(),
          onDoubleTapAnimationStart: (isLeft, tapPos, seconds) {
            setState(() {
              _tapPosition = tapPos;
              _isSeekingLeft = isLeft;
              _seekDisplaySeconds = seconds;
            });
            _seekAnimController.forward(from: 0.0);
          },
        );

    _playFocusNode = FocusNode();
    _backFocusNode = FocusNode(debugLabel: 'back_button');
    _scrubFocusNode = FocusNode(debugLabel: 'controls_scrubber');
    
    try {
      FlutterVolumeController.updateShowSystemUI(false);
    } catch (e) {
      if (kDebugMode) debugPrint("VolumeUI Error: $e");
    }
    
    _isPlaying = widget.player.state.playing;
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;

    _subscriptions.addAll([
      widget.player.stream.playing.listen((val) {
        final oldPlaying = _isPlaying;
        _isPlaying = val;
        if (mounted) setState(() {}); 
        if (val) {
          _startHideTimer();
          _metadataScrimKey.currentState?.resetSchedule();
        } else {
          _cancelHideTimer();
          _metadataScrimKey.currentState?.resetSchedule();
        }
        if (mounted && val && !oldPlaying && _duration == Duration.zero) {
          setState(() {});
        }
        if (Platform.isAndroid) {
          const MethodChannel('dev.akash.skystream.player/pip').invokeMethod('setPipState', {'isPlaying': val});
        }
      }),
      widget.player.stream.position.listen((val) {
        _position = val; 
      }),
      widget.player.stream.duration.listen((val) {
        final oldDuration = _duration;
        _duration = val;
        if (mounted && oldDuration == Duration.zero && val != Duration.zero) {
          setState(() => _isVisible = true);
          widget.onVisibilityChanged?.call(true);
          _startHideTimer();
          _restoreFocus();
        }
      }),
      widget.player.stream.width.listen((_) => _updateOrientation()),
      widget.player.stream.height.listen((_) => _updateOrientation()),
    ]);

    _seekAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

    widget.videoViewController?.position.addListener(_onVvPosition);
    widget.videoViewController?.playbackState.addListener(_onVvPlaybackState);
    widget.videoViewController?.mediaInfo.addListener(_onVvMediaInfo);
    widget.videoViewController?.videoSize.addListener(_updateOrientation);
    widget.videoViewController?.orientation.addListener(_updateOrientation);

    if (Platform.isAndroid && !_isTv) {
      const MethodChannel('dev.akash.skystream.player/pip').setMethodCallHandler((call) async {
        switch (call.method) {
          case 'pipModeChanged':
            if (mounted) setState(() => _isInPip = call.arguments as bool);
            break;
          case 'play':
            unawaited(ref.read(playerControllerProvider.notifier).play());
            break;
          case 'pause':
            unawaited(ref.read(playerControllerProvider.notifier).pause());
            break;
          case 'seekForward':
            _seekRelative(const Duration(seconds: 10));
            break;
          case 'seekBackward':
            _seekRelative(const Duration(seconds: -10));
            break;
        }
      });
    }

    if (widget.streams != null && widget.streams!.isNotEmpty) {
      _isVisible = true;
    }
    
    if (_isBigPicture) {
      _isVisible = true;
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isVisible) {
        widget.onVisibilityChanged?.call(true);
        _restoreFocus();
      }
    });

    _startHideTimer();
    FocusManager.instance.addListener(_onFocusChange);

    _revertMessageSub = ref.listenManual(playerControllerProvider, (_, _) {
      final msg = ref.read(playerControllerProvider.notifier).consumeRevertMessage();
      if (msg != null && mounted) ref.read(notificationServiceProvider).showInfo(msg);
    });
  }

  @override
  void dispose() {
    widget.videoViewController?.position.removeListener(_onVvPosition);
    widget.videoViewController?.playbackState.removeListener(_onVvPlaybackState);
    widget.videoViewController?.mediaInfo.removeListener(_onVvMediaInfo);
    widget.videoViewController?.videoSize.removeListener(_updateOrientation);
    widget.videoViewController?.orientation.removeListener(_updateOrientation);
    
    if (_touchHeldForSpeed) {
      final previousSpeed = _speedBeforeTouchHold ?? 1.0;
      unawaited(ref.read(playerControllerProvider.notifier).setPlaybackSpeed(previousSpeed));
    }
    
    FocusManager.instance.removeListener(_onFocusChange);
    _revertMessageSub?.close();
    
    _playFocusNode.dispose();
    _backFocusNode.dispose();
    _scrubFocusNode.dispose();
    
    _hideTimer?.cancel();
    _seekAnimController.dispose();
    
    for (final s in _subscriptions) {
      s.cancel();
    }
    
    try {
      ScreenBrightness().resetApplicationScreenBrightness();
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to reset brightness: $e');
    }
    try {
      FlutterVolumeController.updateShowSystemUI(true);
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to restore volume UI: $e');
    }
    
    SystemChrome.setPreferredOrientations([]); 
    if (Platform.isAndroid && !_isTv) {
      const MethodChannel('dev.akash.skystream.player/pip').setMethodCallHandler(null);
    }
    super.dispose();
  }

  void _restoreFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isVisible) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (_panelOpen) return;

      if (_lastFocusedNode != null && _lastFocusedNode!.canRequestFocus) {
        _lastFocusedNode!.requestFocus();
      } else {
        _playFocusNode.requestFocus();
      }
    });
  }

  void _onFocusChange() {
    if (_isVisible && mounted) {
      final currentFocus = FocusManager.instance.primaryFocus;
      if (currentFocus != null && currentFocus.debugLabel != 'player_root') {
        _lastFocusedNode = currentFocus;
      }
      _startHideTimer();
    }
  }

  bool triggerActiveOverlay() {
    final s = ref.read(playerControllerProvider);
    if (s.resumePromptPosition != null || s.resumePromptPercentage != null) {
      ref.read(playerControllerProvider.notifier).confirmResume();
      return true;
    }
    if (s.showNextEpisodeOverlay && s.nextEpisodeTitle != null) {
      ref.read(playerControllerProvider.notifier).playNextEpisode();
      return true;
    }
    if (_isSkipActive) {
      final positionMs = _position.inMilliseconds;
      for (final seg in s.skipSegments) {
        final int startMs = (seg.startTime * 1000).toInt();
        final int endMs = (seg.endTime * 1000).toInt();

        if (positionMs >= startMs && positionMs < endMs) {
          ref.read(playerControllerProvider.notifier).seekTo(Duration(milliseconds: endMs));
          if (seg.type == SkipType.outro) {
            ref.read(playerControllerProvider.notifier).forceNextEpisodeOverlay();
          }
          return true;
        }
      }
    }
    return false;
  }

  bool triggerSecondaryOverlayAction() {
    final s = ref.read(playerControllerProvider);
    if (s.resumePromptPosition != null || s.resumePromptPercentage != null) {
      ref.read(playerControllerProvider.notifier).dismissResumePrompt();
      return true;
    }
    if (s.showNextEpisodeOverlay && s.nextEpisodeTitle != null) {
      ref.read(playerControllerProvider.notifier).dismissNextEpisodeOverlay();
      return true;
    }
    return false;
  }

  void _updateOrientation() {
    final useExo = ref.read(playerControllerProvider.select((s) => s.useExoPlayer));
    if (useExo && widget.videoViewController != null) {
      final size = widget.videoViewController!.videoSize.value;
      final orientation = widget.videoViewController!.orientation.value;

      if (size.width > 0 && size.height > 0) {
        final isLandscape = orientation == 1 || orientation == 3;
        final w = isLandscape ? size.height : size.width;
        final h = isLandscape ? size.width : size.height;
        _platformService.updateOrientation(w.toInt(), h.toInt());
      }
    } else {
      _platformService.updateOrientation(widget.player.state.width, widget.player.state.height);
    }
  }

  Future<void> _enterPip() async {
    await _platformService.enterPip(_isPlaying);
  }

  void _toggleOrientation() {
    _platformService.toggleOrientation(context);
  }

  Future<void> toggleFullscreen() async {
    final nowFullscreen = await _platformService.toggleFullscreen();
    if (mounted) setState(() => _isFullscreen = nowFullscreen);
  }

  Future<void> _handleDoubleTap() async {
    if (_isLocked || _panelOpen) return;
    try {
      if (context.isDesktop && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        unawaited(toggleFullscreen());
        return;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('SkyStreamPlayerControls._handleDoubleTap: $e');
    }

    if (widget.isLoading || _duration == Duration.zero) return;
    if (_tapPosition != null) {
      unawaited(ref.read(playerGestureHandlerProvider.notifier).handleDoubleTap(_tapPosition!, MediaQuery.sizeOf(context).width));
    }
  }

  void _startTouchSpeedHold() {
    if (_isLocked || _panelOpen || _isTv || !(Platform.isAndroid || Platform.isIOS)) return;
    if (_touchHeldForSpeed) return;
    _touchHeldForSpeed = true;
    _speedBeforeTouchHold = ref.read(playerControllerProvider).playbackSpeed;
    unawaited(ref.read(playerControllerProvider.notifier).setPlaybackSpeed(2.0));
    ref.read(playerGestureHandlerProvider.notifier).showToast("2.0x", Icons.fast_forward_rounded);
  }

  void _endTouchSpeedHold() {
    if (!_touchHeldForSpeed) return;
    final previousSpeed = _speedBeforeTouchHold ?? 1.0;
    _touchHeldForSpeed = false;
    _speedBeforeTouchHold = null;
    unawaited(ref.read(playerControllerProvider.notifier).setPlaybackSpeed(previousSpeed));
    ref.read(playerGestureHandlerProvider.notifier).showToast("${previousSpeed.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}x", Icons.play_arrow_rounded);
  }

  void _returnFocusToRoot() {
    widget.onRequestRootFocus?.call();
  }

  void _toggleVisibility() {
    _animDuration = const Duration(milliseconds: 300);
    setState(() => _isVisible = !_isVisible);
    widget.onVisibilityChanged?.call(_isVisible);
    if (_isVisible) {
      _startHideTimer();
      _restoreFocus();
    } else {
      _returnFocusToRoot();
    }
  }

  void hideControls() {
    if (mounted) {
      _hideTimer?.cancel();
      setState(() => _isVisible = false);
      widget.onVisibilityChanged?.call(false);
      _returnFocusToRoot();
      _metadataScrimKey.currentState?.resetSchedule();
    }
  }

  void updateTorrentStatus(TorrentStatus status) {}

  void showControls() {
    if (mounted) {
      setState(() => _isVisible = true);
      widget.onVisibilityChanged?.call(true);
      _startHideTimer();
      _restoreFocus();
    }
  }

  bool get _panelOpen {
    final s = ref.read(playerControllerProvider);
    return s.showSourcesPanel || s.showEpisodeList || s.showContentPanel;
  }

  void _enterPanelMode() {
    _cancelHideTimer();
    if (_isVisible) {
      setState(() => _isVisible = false);
      widget.onVisibilityChanged?.call(false);
    }
  }

  void openSourcesPanel(int tab) {
    _enterPanelMode();
    ref.read(playerControllerProvider.notifier).openSourcesPanel(tab: tab);
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) FocusScope.of(context).nextFocus();
    });
  }

  void openEpisodesPanel() {
    _enterPanelMode();
    ref.read(playerControllerProvider.notifier).openEpisodeList();
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) FocusScope.of(context).nextFocus();
    });
  }

  void openContentPanel() {
    _enterPanelMode();
    ref.read(playerControllerProvider.notifier).openContentPanel();
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) FocusScope.of(context).nextFocus();
    });
  }

  void closeSourcesPanel() {
    if (!ref.read(playerControllerProvider).showSourcesPanel) return;
    ref.read(playerControllerProvider.notifier).closeSourcesPanel();
    showControls();
  }

  void closeEpisodesPanel() {
    if (!ref.read(playerControllerProvider).showEpisodeList) return;
    ref.read(playerControllerProvider.notifier).closeEpisodeList();
    showControls();
  }

  void closeContentPanel() {
    if (!ref.read(playerControllerProvider).showContentPanel) return;
    ref.read(playerControllerProvider.notifier).closeContentPanel();
    showControls();
  }

  void closeActivePanel() {
    closeSourcesPanel();
    closeEpisodesPanel();
    closeContentPanel();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_isVisible || _panelOpen) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _isVisible = false);
        widget.onVisibilityChanged?.call(false);
        _returnFocusToRoot();
      }
    });
  }

  void onUserInteraction() {
    if (mounted) {
      if (_panelOpen) return; 
      if (!_isVisible) {
        setState(() => _isVisible = true);
        widget.onVisibilityChanged?.call(true);
        _restoreFocus();
      }
      _startHideTimer();
    }
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
  }

  void _onVvPosition() {
    final ms = widget.videoViewController?.position.value ?? 0;
    _position = Duration(milliseconds: ms);
  }

  void _onVvPlaybackState() {
    final state = widget.videoViewController?.playbackState.value;
    final playing = state == vv.VideoControllerPlaybackState.playing;
    if (playing != _isPlaying) {
      _isPlaying = playing;
      if (mounted) setState(() {}); 
      if (playing) {
        _startHideTimer();
        _metadataScrimKey.currentState?.resetSchedule();
      } else {
        _cancelHideTimer();
        _metadataScrimKey.currentState?.resetSchedule();
      }
    }
  }

  void _onVvMediaInfo() {
    final info = widget.videoViewController?.mediaInfo.value;
    final ms = info?.duration ?? 0;
    final newDuration = Duration(milliseconds: ms);
    final oldDuration = _duration;
    _duration = newDuration;
    if (mounted && oldDuration == Duration.zero && newDuration != Duration.zero) {
      setState(() => _isVisible = true);
      widget.onVisibilityChanged?.call(true);
      _startHideTimer();
      _restoreFocus();
    }

    if (widget.videoViewController != null) {
      final size = widget.videoViewController!.videoSize.value;
      if (size.width > 0 && size.height > 0) _updateOrientation();
    }
  }

  void _togglePlay() {
    unawaited(ref.read(playerControllerProvider.notifier).togglePlayPause());
  }

  void _seekRelative(Duration amount) {
    unawaited(ref.read(playerControllerProvider.notifier).seekRelative(amount));
    _startHideTimer();
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      _isVisible = true;
    });
    _startHideTimer();
  }

  void toggleMute() {
    ref.read(playerGestureHandlerProvider.notifier).toggleMute();
  }

  Future<void> changeVolume(double step) async {
    await ref.read(playerGestureHandlerProvider.notifier).changeVolume(step);
  }

  void triggerSeek(bool isLeft, [int? customSeconds]) {
    final width = MediaQuery.sizeOf(context).width;
    final settings = ref.read(playerSettingsProvider).asData?.value ?? const PlayerSettings();
    final seconds = customSeconds ?? settings.seekDuration;

    setState(() {
      _isSeekingLeft = isLeft;
      _seekDisplaySeconds = seconds;
      _tapPosition = Offset(isLeft ? width * 0.25 : width * 0.75, 100);
    });
    _seekAnimController.forward(from: 0.0);

    _seekRelative(Duration(seconds: isLeft ? -seconds : seconds));
  }

  void cycleResize() {
    setState(() {
      _resizeMode = (_resizeMode + 1) % 3;
      final modes = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
      final l10n = AppLocalizations.of(context)!;
      final labels = [l10n.fit, l10n.zoom, l10n.stretch];

      widget.onResize?.call(modes[_resizeMode]);
      ref.read(playerGestureHandlerProvider.notifier).showToast(labels[_resizeMode], Icons.aspect_ratio);
    });
  }

  Future<void> _handleDragStart(DragStartDetails details) async {
    if (_isLocked || _panelOpen) return;
    final size = MediaQuery.sizeOf(context);
    await ref.read(playerGestureHandlerProvider.notifier).handleDragStart(details, size.width, size.height);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_isLocked || _panelOpen) return;
    ref.read(playerGestureHandlerProvider.notifier).handleDragUpdate(details);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_isLocked || _panelOpen) return;
    ref.read(playerGestureHandlerProvider.notifier).handleDragEnd(details);
  }

  Future<void> _handleHorizontalDragStart(DragStartDetails details) async {
    if (_isLocked || _panelOpen) return;
    final size = MediaQuery.sizeOf(context);
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    await ref.read(playerGestureHandlerProvider.notifier).handleHorizontalDragStart(details, _isVisible, size.width, size.height, bottomPadding);
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (_isLocked || _panelOpen) return;
    ref.read(playerGestureHandlerProvider.notifier).handleHorizontalDragUpdate(details);
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (_isLocked || _panelOpen) return;
    ref.read(playerGestureHandlerProvider.notifier).handleHorizontalDragEnd(details);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return "$hours:${twoDigits(minutes)}:${twoDigits(seconds)}";
    }
    return "$minutes:${twoDigits(seconds)}";
  }

  Widget _buildKickAnimation() {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _seekAnimController, curve: Curves.easeOutCubic)),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1.0).animate(CurvedAnimation(parent: _seekAnimController, curve: Curves.easeOut)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isSeekingLeft) const Icon(Icons.keyboard_double_arrow_left_rounded, color: Colors.white, size: 34),
            Text(
              "$_seekDisplaySeconds",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 28, fontFeatures: [FontFeature.tabularFigures()]),
            ),
            if (!_isSeekingLeft) const Icon(Icons.keyboard_double_arrow_right_rounded, color: Colors.white, size: 34),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniHint(BuildContext context, String btn, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            btn,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 11, fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controllerTitle = ref.watch(playerControllerProvider.select((s) => s.playerTitle));
    final title = controllerTitle.isEmpty ? (widget.title ?? "") : controllerTitle;
    final controllerSubtitle = ref.watch(playerControllerProvider.select((s) => s.streamSubtitle));
    final subtitle = controllerSubtitle ?? widget.subtitle;
    final streams = ref.watch(playerControllerProvider.select((s) => s.streams));
    final currentStream = ref.watch(playerControllerProvider.select((s) => s.currentStream));
    final externalSubtitles = ref.watch(playerControllerProvider.select((s) => s.externalSubtitles));
    final torrentStatus = ref.watch(playerControllerProvider.select((s) => s.torrentStatus));
    
    final showNextEpOverlay = ref.watch(playerControllerProvider.select((s) => s.showNextEpisodeOverlay));
    final nextEpTitle = ref.watch(playerControllerProvider.select((s) => s.nextEpisodeTitle));
    final nextEpPosterUrl = ref.watch(playerControllerProvider.select((s) => s.nextEpisodePosterUrl));
    final nextEpRating = ref.watch(playerControllerProvider.select((s) => s.nextEpisodeRating));
    final nextEpNumber = ref.watch(playerControllerProvider.select((s) => s.nextEpisodeNumber));
    final nextEpSeason = ref.watch(playerControllerProvider.select((s) => s.nextEpisodeSeason));
    final nextEpRuntime = ref.watch(playerControllerProvider.select((s) => s.nextEpisodeRuntime));
    final nextEpDescription = ref.watch(playerControllerProvider.select((s) => s.nextEpisodeDescription));
    
    final resumePromptPosition = ref.watch(playerControllerProvider.select((s) => s.resumePromptPosition));
    final resumePromptPercentage = ref.watch(playerControllerProvider.select((s) => s.resumePromptPercentage));
    
    final showEpisodeList = ref.watch(playerControllerProvider.select((s) => s.showEpisodeList));
    final supportsPlaybackSpeed = ref.watch(playerControllerProvider.select((s) => s.supportsPlaybackSpeed));
    final playbackSpeed = ref.watch(playerControllerProvider.select((s) => s.playbackSpeed));
    final maxPlaybackSpeed = ref.watch(playerControllerProvider.select((s) => s.maxPlaybackSpeed));
    final isSeries = ref.read(playerControllerProvider.notifier).isSeries;
    
    final skipSegments = ref.watch(playerControllerProvider.select((s) => s.skipSegments));
    final uiPhase = ref.watch(playerControllerProvider.select((s) => s.uiPhase));
    final sourceAttempts = ref.watch(playerControllerProvider.select((s) => s.sourceAttempts));
    
    final size = MediaQuery.sizeOf(context);
    final isSmallWindow = size.width < 300 || size.height < 200;

    if (_isInPip || isSmallWindow) return const SizedBox.shrink();

    if (uiPhase.fullscreenBlocking) return _buildLoadingUI(phase: uiPhase, sourceAttempts: sourceAttempts);

    return MouseRegion(
      cursor: (_isVisible || _panelOpen) ? SystemMouseCursors.basic : SystemMouseCursors.none,
      onEnter: (_) {
        if (_panelOpen) return; 
        if (!_isVisible) {
          setState(() => _isVisible = true);
          widget.onVisibilityChanged?.call(true);
        }
        _startHideTimer();
      },
      onHover: (_) {
        if (_panelOpen) return; 
        if (!_isVisible && mounted) {
          setState(() => _isVisible = true);
          widget.onVisibilityChanged?.call(true);
        }
        _startHideTimer();
      },
      onExit: (_) {
        if (_isPlaying) _startHideTimer();
      },
      child: GestureDetector(
        onVerticalDragStart: _handleDragStart,
        onVerticalDragUpdate: _handleDragUpdate,
        onVerticalDragEnd: _handleDragEnd,
        onHorizontalDragStart: _handleHorizontalDragStart,
        onHorizontalDragUpdate: _handleHorizontalDragUpdate,
        onHorizontalDragEnd: _handleHorizontalDragEnd,
        onDoubleTapDown: (d) => _tapPosition = d.globalPosition,
        onDoubleTap: _handleDoubleTap,
        onLongPressStart: (_) => _startTouchSpeedHold(),
        onLongPressEnd: (_) => _endTouchSpeedHold(),
        onLongPressCancel: _endTouchSpeedHold,
        child: GestureDetector(
          onTap: () {
            if (_panelOpen) return; 
            final gestureState = ref.read(playerGestureHandlerProvider);
            if (gestureState.showOSD) ref.read(playerGestureHandlerProvider.notifier).dismissOSD();
            
            if (_isLocked) {
              setState(() => _isVisible = !_isVisible);
              widget.onVisibilityChanged?.call(_isVisible);
              if (_isVisible) _startHideTimer();
            } else {
              _toggleVisibility();
            }
          },
          behavior: HitTestBehavior.translucent,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.transparent,
            child: Stack(
              children: [
                if (_isLocked) _buildLockedUI()
                else _buildUnlockedUI(
                    title: title, subtitle: subtitle, torrentStatus: torrentStatus, streams: streams, currentStream: currentStream,
                    externalSubtitles: externalSubtitles, showEpisodeList: showEpisodeList, isSeries: isSeries,
                    supportsPlaybackSpeed: supportsPlaybackSpeed, playbackSpeed: playbackSpeed, maxPlaybackSpeed: maxPlaybackSpeed,
                  ),

                if (!_isBigPicture && (Platform.isAndroid || Platform.isIOS) && !_isLocked)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_isVisible,
                      child: AnimatedOpacity(
                        opacity: _isVisible ? 1.0 : 0.0,
                        duration: _animDuration,
                        child: Center(
                          child: PlayerPlayPauseButton(
                            player: widget.player, videoViewController: widget.videoViewController,
                            isLoading: widget.isLoading, isTv: _isBigPicture, size: 82,
                            backgroundColor: Colors.black.withValues(alpha: 0.32),
                            onPressed: _togglePlay,
                          ),
                        ),
                      ),
                    ),
                  ),

                PlayerBufferingIndicator(isVisible: _isVisible, isTouch: !_isBigPicture && (Platform.isAndroid || Platform.isIOS)),

                AnimatedBuilder(
                  animation: _seekAnimController,
                  builder: (context, _) {
                    if (!_seekAnimController.isAnimating) return const SizedBox.shrink();
                    return Align(
                      alignment: Alignment(_isSeekingLeft ? -0.84 : 0.84, 0.0),
                      child: _buildKickAnimation(),
                    );
                  },
                ),

                PlayerOSDVolumeOverlay(getDuration: () => _duration, formatDuration: _formatDuration),

                if (torrentStatus != null && _showTorrentInfo)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: SafeArea(
                        left: false, right: false,
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: _isBigPicture ? 88 : 68,
                              right: _isBigPicture ? HotstarPlayerStyle.tvEdgeInset : (MediaQuery.viewPaddingOf(context).right > HotstarPlayerStyle.edgeInset ? MediaQuery.viewPaddingOf(context).right : HotstarPlayerStyle.edgeInset),
                              left: 12,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: (size.width * 0.36).clamp(240.0, 360.0)),
                              child: TorrentInfoWidget(status: torrentStatus),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // 🛡️ REMOVED THE FAULTY EXCLUDE FOCUS AND STACK!
                // These now render exactly where they did originally, with their own timers wired up.
                if (!widget.isLoading && _duration != Duration.zero && !_isLocked && (resumePromptPosition != null || resumePromptPercentage != null))
                  ResumePromptOverlay(
                    focusNode: FocusNode(canRequestFocus: false), 
                    positionMs: resumePromptPosition, percentage: resumePromptPercentage,
                    onResume: () => ref.read(playerControllerProvider.notifier).confirmResume(), 
                    onStartOver: () => ref.read(playerControllerProvider.notifier).dismissResumePrompt(), 
                    isTv: _isBigPicture,
                  ),

                if (resumePromptPosition == null && resumePromptPercentage == null && showNextEpOverlay && nextEpTitle != null)
                  NextEpisodeOverlay(
                    focusNode: FocusNode(canRequestFocus: false), nextEpisodeTitle: nextEpTitle, nextEpisodePosterUrl: nextEpPosterUrl,
                    nextEpisodeRating: nextEpRating, nextEpisodeNumber: nextEpNumber, nextEpisodeSeason: nextEpSeason,
                    nextEpisodeRuntime: nextEpRuntime, nextEpisodeDescription: nextEpDescription,
                    onPlayNext: () => ref.read(playerControllerProvider.notifier).playNextEpisode(), 
                    onDismiss: () => ref.read(playerControllerProvider.notifier).dismissNextEpisodeOverlay(), 
                    isTv: _isBigPicture, isPlaying: _isPlaying,
                  ),

                if (resumePromptPosition == null && resumePromptPercentage == null && !showNextEpOverlay && skipSegments.isNotEmpty)
                  SkipSegmentOverlay(
                    focusNode: FocusNode(canRequestFocus: false),
                    onActiveSegmentChanged: (active) {
                      if (mounted) setState(() => _isSkipActive = active);
                    },
                    player: widget.player, videoViewController: widget.videoViewController, skipSegments: skipSegments, isTv: _isBigPicture, controlsVisible: _isVisible,
                    onFocusReturned: () {},
                  ),

                if (isSeries && ref.read(playerControllerProvider.notifier).multimediaItem != null)
                  Positioned.fill(
                    child: PlayerSidePanel(
                      isVisible: showEpisodeList && !_isLocked, isTv: _isBigPicture, onDismiss: closeEpisodesPanel,
                      child: PlayerEpisodesPanel(
                        item: ref.read(playerControllerProvider.notifier).multimediaItem!, isTv: _isBigPicture, onClose: closeEpisodesPanel,
                      ),
                    ),
                  ),

                if (torrentStatus != null)
                  Positioned.fill(
                    child: PlayerSidePanel(
                      isVisible: ref.watch(playerControllerProvider.select((s) => s.showContentPanel)), isTv: _isBigPicture, onDismiss: closeContentPanel,
                      child: PlayerContentPanel(
                        isTv: _isBigPicture, onFileSelected: (idx) => ref.read(playerControllerProvider.notifier).onTorrentFileSelected(idx), onClose: closeContentPanel,
                      ),
                    ),
                  ),

                PlayerMetadataScrim(
                  key: _metadataScrimKey, item: ref.read(playerControllerProvider.notifier).multimediaItem, episode: ref.read(playerControllerProvider.notifier).currentEpisode,
                  isSeries: ref.read(playerControllerProvider.notifier).isSeries, isPaused: !_isPlaying, isDialogOpen: _panelOpen, controlsVisible: _isVisible,
                  isTv: _isBigPicture, onHidePlayerUI: hideControls,
                ),

                Positioned.fill(
                  child: PlayerSidePanel(
                    isVisible: ref.watch(playerControllerProvider.select((s) => s.showSourcesPanel)), isTv: _isBigPicture, onDismiss: closeSourcesPanel,
                    child: PlayerSourcesPanel(
                      player: widget.player, videoViewController: widget.videoViewController, isTv: _isBigPicture, onClose: closeSourcesPanel,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon, required String label, required VoidCallback onTap, bool highlight = false, FocusNode? focusNode,
  }) {
    return PlayerActionButton(icon: icon, label: label, onTap: onTap, highlight: highlight, isTv: _isBigPicture, focusNode: focusNode);
  }

  Widget _buildLockedUI() {
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: _isVisible,
      child: IgnorePointer(
        ignoring: !_isVisible,
        child: AnimatedOpacity(
          opacity: _isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 180),
          child: Center(
            child: _buildActionButton(
              icon: Icons.lock, label: AppLocalizations.of(context)!.unlock, onTap: _toggleLock, highlight: false,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockedUI({
    required String title, String? subtitle, TorrentStatus? torrentStatus, List<StreamResult>? streams, StreamResult? currentStream,
    List<SubtitleFile>? externalSubtitles, required bool showEpisodeList, required bool isSeries, required bool supportsPlaybackSpeed,
    required double playbackSpeed, required double maxPlaybackSpeed,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isTouch = !_isBigPicture && (Platform.isAndroid || Platform.isIOS);

    final playPause = PlayerPlayPauseButton(
      player: widget.player, videoViewController: widget.videoViewController, isLoading: widget.isLoading, isTv: _isBigPicture,
      size: 52, focusNode: _playFocusNode, onPressed: _togglePlay, showBufferingSpinner: false,
    );

    final leading = <Widget>[
      if (!isTouch) playPause,
      if (isTouch)
        PlayerIconButton(icon: _isLocked ? Icons.lock : Icons.lock_open, tooltip: _isLocked ? l10n.unlock : l10n.lock, onPressed: _toggleLock, isTv: _isBigPicture, highlight: _isLocked),
      if (isSeries)
        PlayerIconButton(icon: Icons.skip_next_rounded, tooltip: l10n.next, onPressed: () => ref.read(playerControllerProvider.notifier).playNextEpisode(), isTv: _isBigPicture),
    ];

    final playerSettings = ref.watch(playerSettingsProvider).asData?.value ?? const PlayerSettings();

    final actions = <Widget>[
      PlayerIconButton(icon: Icons.source, tooltip: l10n.sources, onPressed: () => openSourcesPanel(0), isTv: _isBigPicture),
      PlayerIconButton(icon: Icons.audiotrack_rounded, tooltip: l10n.audioTracks, onPressed: () => openSourcesPanel(1), isTv: _isBigPicture),
      PlayerIconButton(icon: Icons.subtitles_rounded, tooltip: l10n.subtitles, onPressed: () => openSourcesPanel(2), isTv: _isBigPicture),
      if (supportsPlaybackSpeed && playerSettings.showPlaybackSpeed)
        PlayerIconButton(
          icon: Icons.speed, tooltip: "${playbackSpeed.toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '')}x",
          onPressed: () {
            PlayerBottomSheets.showSpeedSelection(
              context: context, currentSpeed: playbackSpeed, maxSpeed: maxPlaybackSpeed,
              onSpeedSelected: (s) => ref.read(playerControllerProvider.notifier).setPlaybackSpeed(s, persist: true),
            );
          },
          isTv: _isBigPicture,
        ),
      if (torrentStatus != null)
        PlayerIconButton(icon: Icons.folder, tooltip: l10n.content, onPressed: openContentPanel, isTv: _isBigPicture),
      if (torrentStatus != null)
        PlayerIconButton(icon: Icons.info_outline, tooltip: l10n.stats, onPressed: () => setState(() => _showTorrentInfo = !_showTorrentInfo), isTv: _isBigPicture, highlight: _showTorrentInfo),
      if (isTouch && (Platform.isAndroid || (Platform.isIOS && !_isIpad)) && playerSettings.showRotate)
        PlayerIconButton(icon: Icons.screen_rotation, tooltip: l10n.rotate, onPressed: _toggleOrientation, isTv: _isBigPicture),
      if (isSeries && playerSettings.showEpisodes)
        PlayerIconButton(icon: Icons.playlist_play_rounded, tooltip: l10n.episodes, onPressed: openEpisodesPanel, isTv: _isBigPicture),
      if (playerSettings.showResize)
        PlayerIconButton(icon: Icons.aspect_ratio_rounded, tooltip: l10n.resize, onPressed: cycleResize, isTv: _isBigPicture),
      if (Platform.isAndroid && !_isBigPicture && playerSettings.showPip)
        PlayerIconButton(icon: Icons.picture_in_picture_alt_rounded, tooltip: l10n.pip, onPressed: _enterPip, isTv: _isBigPicture),
      if (!context.isDesktop && !_isBigPicture)
        PlayerIconButton(
          icon: _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          tooltip: _isFullscreen ? l10n.windowed : l10n.fullscreen,
          onPressed: toggleFullscreen,
          isTv: _isBigPicture,
        ),
    ];

    final chromeVisible = _isVisible && !_panelOpen;
    return FocusTraversalGroup(
      // 🎯 THE FIX: WidgetOrderTraversalPolicy keeps D-Pad leaps completely bulletproof!
      policy: WidgetOrderTraversalPolicy(),
      child: Focus(
        canRequestFocus: false,
        descendantsAreFocusable: chromeVisible, // 🎯 AXTree FIX: Replaces ExcludeFocus! Safely removes children from semantic tree without crashing!
        child: IgnorePointer(
          ignoring: !chromeVisible,
          child: AnimatedOpacity(
            opacity: chromeVisible ? 1.0 : 0.0,
            duration: _animDuration,
            // 🎯 Heavy visibility gradient!
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.9),
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7), 
                  ],
                  stops: const [0.0, 0.2, 0.4, 0.8, 1.0],
                ),
              ),
              child: Column(
                children: [
                  Focus(
                    canRequestFocus: false,
                    descendantsAreFocusable: !_isBigPicture, 
                    child: _absorbGestures(
                      Visibility(
                        visible: !_isBigPicture, 
                        child: PlayerTopBar(
                          title: title, subtitle: subtitle, onBack: widget.onBackPointer ?? () => context.pop(),
                          isTv: _isBigPicture, backFocusNode: _backFocusNode,
                        ),
                      ),
                    ),
                  ),
                  const Expanded(child: SizedBox.expand()),
                  _absorbGestures(
                    PlayerBottomBar(
                      isTv: _isBigPicture,
                      isTouch: isTouch,
                      progressBar: Focus(
                        canRequestFocus: false,
                        descendantsAreFocusable: !_isBigPicture, // Hide Scrubber from D-Pad
                        child: PlayerProgressBar(
                          player: widget.player, videoViewController: widget.videoViewController,
                          onSeekStart: _cancelHideTimer, isTv: _isBigPicture, focusNode: _scrubFocusNode,
                          onArrowUp: () {},
                        ),
                      ),
                      leading: leading,
                      actions: actions,
                    ),
                  ),
                  // 🎯 RESTORED HINT ROW
                  if (_isBigPicture)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildMiniHint(context, 'A', 'Select', Colors.greenAccent.shade400),
                          const SizedBox(width: 16),
                          _buildMiniHint(context, 'B', 'Exit', Colors.redAccent.shade400),
                          const SizedBox(width: 16),
                          _buildMiniHint(context, 'LT / RT', 'Seek 10s', Colors.white),
                          const SizedBox(width: 16),
                          _buildMiniHint(context, '≡', 'Menu', Colors.white),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _absorbGestures(Widget child) {
    return GestureDetector(onTap: () {}, onDoubleTap: () {}, onVerticalDragStart: (_) {}, onHorizontalDragStart: (_) {}, child: child);
  }

  Widget _buildLoadingUI({required PlaybackUiPhase phase, required List<SourceAttemptEntry> sourceAttempts}) {
    final canSkip = phase.kind != PlaybackUiPhaseKind.bootstrapping && phase.kind != PlaybackUiPhaseKind.fetchingSources && phase.kind != PlaybackUiPhaseKind.error;
    return PlayerLoadingOverlay(
      onDoubleTap: _handleDoubleTap, onBack: widget.onBackPointer ?? () => context.pop(), phase: phase, sourceAttempts: sourceAttempts,
      backdropUrl: widget.backdropUrl, logoUrl: widget.logoUrl, isTv: _isBigPicture,
      onSkip: canSkip ? () => ref.read(playerControllerProvider.notifier).skipLoadingOverlay() : null,
      onGoLive: () => ref.read(playerControllerProvider.notifier).goLive(),
    );
  }
}