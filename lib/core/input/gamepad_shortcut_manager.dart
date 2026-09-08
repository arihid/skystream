import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';
import 'package:gamepads/gamepads.dart';
import 'gamepad_intents.dart';
import 'gamepad_actions.dart';

class GamepadShortcutManager extends StatefulWidget {
  final Widget child;

  const GamepadShortcutManager({super.key, required this.child});

  @override
  State<GamepadShortcutManager> createState() => _GamepadShortcutManagerState();
}

class _GamepadShortcutManagerState extends State<GamepadShortcutManager>
    with WidgetsBindingObserver, WindowListener {
  StreamSubscription<GamepadEvent>? _gamepadSubscription;
  bool _isAppFocused = true;

  // ─── DIGITAL BUTTONS STATE ───
  Timer? _repeatTimer;
  String? _heldKey;
  final int initialDelayMs = 350;
  final int repeatIntervalMs = 150;

  // ─── ANALOG VELOCITY ENGINE STATE (Left Stick Only) ───
  double _analogX = 0.0;
  double _analogY = 0.0;
  double _bucketX = 0.0;
  double _bucketY = 0.0;
  bool _isFirstMoveX = true;
  bool _isFirstMoveY = true;
  Timer? _analogTimer;

  final double analogDeadzone = 0.25;
  final double analogThreshold = 130.0;
  final double analogInitialDelay = -250.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _initGamepadListener();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppFocused = state == AppLifecycleState.resumed;
    if (!_isAppFocused) {
      _stopAnalogTimer();
      _repeatTimer?.cancel();
      _heldKey = null;
    }
  }

  @override
  void onWindowFocus() {
    _isAppFocused = true;
  }

  @override
  void onWindowBlur() {
    _isAppFocused = false;
    _stopAnalogTimer();
    _repeatTimer?.cancel();
    _heldKey = null;
  }

  Future<void> _initGamepadListener() async {
    _gamepadSubscription = Gamepads.events.listen((GamepadEvent event) {
      if (!_isAppFocused) return;

      final key = event.key.toLowerCase();
      final value = event.value;

      // 1. Handle Analog Stick (Left Stick to D-Pad Conversion)
      if (event.type == KeyType.analog) {
        // STRICT MAPPING: Only catch universally recognized Right Stick axes
        final isRightStick =
            key.contains('rightthumbstick') ||
            key == 'rx' ||
            key == 'ry' ||
            key == 'rz' ||
            key == 'z' ||
            key == 'axis 2' ||
            key == 'axis 3';
        if (isRightStick) return;

        // STRICT MAPPING: Safely map Left Stick & Analog D-Pads
        final isXAxis =
            key == 'leftthumbstickx' ||
            key == 'x' ||
            key == 'axis 0' ||
            key == 'hat0x' ||
            key == 'axis 6';
        final isYAxis =
            key == 'leftthumbsticky' ||
            key == 'y' ||
            key == 'axis 1' ||
            key == 'hat0y' ||
            key == 'axis 7';

        if (isXAxis) _analogX = value;
        if (isYAxis) _analogY = value;

        // HANDLE ANALOG TRIGGERS (LT / RT)
        final isLTAnalog =
            key == 'l2' ||
            key == 'axis 4' ||
            (key.contains('trigger') && key.contains('left'));
        final isRTAnalog =
            key == 'r2' ||
            key == 'axis 5' ||
            (key.contains('trigger') && key.contains('right'));

        if (isLTAnalog && value > 0.5) {
          _handleHeldMove('lt');
        } else if (isLTAnalog && value < 0.1) {
          _handleRelease('lt', 'lt'); }

        if (isRTAnalog && value > 0.5) {
          _handleHeldMove('rt');
        } else if (isRTAnalog && value < 0.1) {
          _handleRelease('rt', 'rt');
        }

        if (_analogX.abs() > analogDeadzone ||
            _analogY.abs() > analogDeadzone) {
          _startAnalogTimer();
        }
        return;
      }

      // 2. Handle Digital Buttons (D-Pad, ABXY, Bumpers, Select/Start)
      if (event.type == KeyType.button) {
        if (event.value == 1.0) {
          if (key.contains('dpad') ||
              key.contains('l1') ||
              key.contains('r1') ||
              key.contains('lb') ||
              key.contains('rb') ||
              key.contains('shoulder') ||
              key == 'l2' ||
              key == 'r2' ||
              key.contains('trigger') ||
              key == 'button 6' ||
              key == 'button 7') {
            _handleHeldMove(key);
          } else {
            _fireGamepadAction(key);
          }
        } else if (event.value == 0.0) {
          _handleRelease(key, key);
        }
      }
    });
  }

  void _startAnalogTimer() {
    if (_analogTimer != null) return;

    _analogTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      bool isMoving = false;

      if (_analogX.abs() > analogDeadzone) {
        isMoving = true;
        if (_isFirstMoveX) {
          _fireGamepadAction(_analogX > 0 ? 'dpadright' : 'dpadleft');
          _isFirstMoveX = false;
          _bucketX = analogInitialDelay;
        } else {
          final double normalized =
              (_analogX.abs() - analogDeadzone) / (1.0 - analogDeadzone);
          final double speedFactor = Curves.easeIn
              .transform(normalized.clamp(0.0, 1.0))
              .clamp(0.15, 1.0);
          _bucketX += speedFactor * 16.0;
          if (_bucketX >= analogThreshold) {
            _bucketX = 0.0;
            _fireGamepadAction(_analogX > 0 ? 'dpadright' : 'dpadleft');
          }
        }
      } else {
        _isFirstMoveX = true;
        _bucketX = 0.0;
      }

      if (_analogY.abs() > analogDeadzone) {
        isMoving = true;
        if (_isFirstMoveY) {
          _fireGamepadAction(_analogY > 0 ? 'dpadup' : 'dpaddown');
          _isFirstMoveY = false;
          _bucketY = analogInitialDelay;
        } else {
          final double normalized =
              (_analogY.abs() - analogDeadzone) / (1.0 - analogDeadzone);
          final double speedFactor = Curves.easeIn
              .transform(normalized.clamp(0.0, 1.0))
              .clamp(0.15, 1.0);
          _bucketY += speedFactor * 16.0;
          if (_bucketY >= analogThreshold) {
            _bucketY = 0.0;
            _fireGamepadAction(_analogY > 0 ? 'dpadup' : 'dpaddown');
          }
        }
      } else {
        _isFirstMoveY = true;
        _bucketY = 0.0;
      }

      if (!isMoving) _stopAnalogTimer();
    });
  }

  void _stopAnalogTimer() {
    _analogTimer?.cancel();
    _analogTimer = null;
    _isFirstMoveX = true;
    _isFirstMoveY = true;
    _bucketX = 0.0;
    _bucketY = 0.0;
  }

  void _handleHeldMove(String actionKey) {
    if (_heldKey != actionKey) {
      _heldKey = actionKey;
      _fireGamepadAction(actionKey);
      _repeatTimer?.cancel();
      _repeatTimer = Timer(Duration(milliseconds: initialDelayMs), () {
        _repeatTimer = Timer.periodic(
          Duration(milliseconds: repeatIntervalMs),
          (timer) => _fireGamepadAction(actionKey),
        );
      });
    }
  }

  void _handleRelease(String key1, String key2) {
    if (_heldKey == key1 || _heldKey == key2) {
      _repeatTimer?.cancel();
      _repeatTimer = null;
      _heldKey = null;
    }
  }

  void _fireGamepadAction(String key) {
    final primaryFocus = FocusManager.instance.primaryFocus;

    // The Safe Context Resolution!
    BuildContext? targetContext = primaryFocus?.context;
    if (targetContext == null || !targetContext.mounted) {
      targetContext = FocusManager.instance.rootScope.context;
    }
    if (targetContext == null || !targetContext.mounted) {
      targetContext = context;
    }

    if (key.contains('dpad') &&
        primaryFocus?.context != null &&
        primaryFocus!.context!.mounted) {
      final renderObject = primaryFocus.context!.findRenderObject();
      if (renderObject is RenderBox &&
          renderObject.hasSize &&
          renderObject.attached) {
        final screenSize = MediaQuery.sizeOf(context);
        if (renderObject.size.width < screenSize.width * 0.9) {
          try {
            final transform = renderObject.getTransformTo(null);
            final paintBounds = MatrixUtils.transformRect(
              transform,
              renderObject.paintBounds,
            );
            final viewport = Offset.zero & screenSize;

            if (!viewport.overlaps(paintBounds)) {
              Scrollable.ensureVisible(
                primaryFocus.context!,
                alignment: 0.5,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
              );
            }
          } catch (_) {}
        }
      }
    }

    if (key == 'a' || key.contains('button 0')) {
      Actions.maybeInvoke(targetContext, const ActivateIntent());
    } else if (key == 'b' || key.contains('button 1')) {
      Actions.maybeInvoke(targetContext, const AppBackIntent());
    } else if (key == 'x' || key.contains('button 2')) {
      Actions.maybeInvoke(targetContext, const AppSecondaryIntent());
    } else if (key == 'y' || key.contains('button 3')) {
      Actions.maybeInvoke(targetContext, const AppTertiaryIntent());
    }
    else if (key == 'select' ||
        key == 'view' ||
        key == 'back' ||
        key == 'minus' ||
        key.contains('button 6') ||
        key.contains('button 8') ||
        key.contains('button_select')) {
      Actions.maybeInvoke(targetContext, const AppSelectButtonIntent());
    } else if (key == 'start' ||
        key == 'menu' ||
        key == 'options' ||
        key.contains('button_start') ||
        key.contains('button 7') ||
        key.contains('button 11') ||
        key == 'plus') {
      Actions.maybeInvoke(targetContext, const AppMenuIntent());
    } else if (key.contains('l1') ||
        key.contains('lb') ||
        key.contains('button 4') ||
        key.contains('left_shoulder') ||
        key.contains('leftshoulder') ||
        key.contains('left_bumper')) {
      Actions.maybeInvoke(targetContext, const AppLeftBumperIntent());
    } else if (key.contains('r1') ||
        key.contains('rb') ||
        key.contains('button 5') ||
        key.contains('right_shoulder') ||
        key.contains('rightshoulder') ||
        key.contains('right_bumper')) {
      Actions.maybeInvoke(targetContext, const AppRightBumperIntent());
    } else if (key == 'lt' ||
        key == 'l2' ||
        key.contains('triggerleft') ||
        key == 'button 6') {
      Actions.maybeInvoke(targetContext, const AppLeftTriggerIntent());
    } else if (key == 'rt' ||
        key == 'r2' ||
        key.contains('triggerright') ||
        key == 'button 7') {
      Actions.maybeInvoke(targetContext, const AppRightTriggerIntent());
    } else if (key.contains('dpadup')) {
      Actions.maybeInvoke(
        targetContext,
        const GamepadDirectionalIntent(TraversalDirection.up),
      );
    } else if (key.contains('dpaddown')) {
      Actions.maybeInvoke(
        targetContext,
        const GamepadDirectionalIntent(TraversalDirection.down),
      );
    } else if (key.contains('dpadleft')) {
      Actions.maybeInvoke(
        targetContext,
        const GamepadDirectionalIntent(TraversalDirection.left),
      );
    } else if (key.contains('dpadright')) {
      Actions.maybeInvoke(
        targetContext,
        const GamepadDirectionalIntent(TraversalDirection.right),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    _stopAnalogTimer();
    _repeatTimer?.cancel();
    _gamepadSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.select): AppSelectIntent(),
    },
    child: widget.child,
  );
}

class RightStickScroller extends StatefulWidget {
  final Widget child;

  const RightStickScroller({super.key, required this.child});

  @override
  State<RightStickScroller> createState() => _RightStickScrollerState();
}

class _RightStickScrollerState extends State<RightStickScroller>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  StreamSubscription<GamepadEvent>? _subscription;
  late Ticker _ticker;
  double _rightStickY = 0.0;
  ScrollableState? _cachedVScrollable;
  bool _isAppFocused = true;

  final double _deadzone = 0.25;
  final double _scrollSpeed = 25.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
    _subscription = Gamepads.events.listen((event) {
      if (!_isAppFocused) return;

      if (event.type == KeyType.analog) {
        final key = event.key.toLowerCase();

        final isRightY =
            key == 'rightthumbsticky' ||
            key == 'ry' ||
            key == 'rz' ||
            key == 'axis 3' ||
            key == 'axis 4';

        if (isRightY) _rightStickY = event.value;

        if (_rightStickY.abs() > _deadzone) {
          if (!_ticker.isTicking) _ticker.start();
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppFocused =
        state != AppLifecycleState.paused && state != AppLifecycleState.hidden;
    if (!_isAppFocused) {
      _rightStickY = 0.0;
      if (_ticker.isTicking) _ticker.stop();
    }
  }

  ScrollableState? _getScrollable() {
    if (_cachedVScrollable != null) return _cachedVScrollable;

    ScrollableState? result;

    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null && focusContext.mounted) {
      final s = Scrollable.maybeOf(focusContext, axis: Axis.vertical);
      if (s != null) result = s;
    }

    if (result == null) {
      void visitor(Element element) {
        if (result != null) return;
        if (element.widget is Scrollable) {
          final s = element.widget as Scrollable;
          if (s.axis == Axis.vertical) {
            result = (element as StatefulElement).state as ScrollableState;
            return;
          }
        }
        element.visitChildren(visitor);
      }

      context.visitChildElements(visitor);
    }

    _cachedVScrollable = result;
    return result;
  }

  void _onTick(Duration elapsed) {
    bool isMoving = false;

    if (_rightStickY.abs() > _deadzone) {
      isMoving = true;
      final vScrollable = _getScrollable();
      if (vScrollable != null && vScrollable.position.hasPixels) {
        final pos = vScrollable.position;
        final newOffset = (pos.pixels - (_rightStickY * _scrollSpeed)).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );
        if (pos.pixels != newOffset) pos.jumpTo(newOffset);
      }
    }

    if (!isMoving) {
      _ticker.stop();
      _cachedVScrollable = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
