import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart'; 
import 'package:gamepads/gamepads.dart';
import 'gamepad_intents.dart';
import 'gamepad_actions.dart';

class GamepadShortcutManager extends StatefulWidget {
  final Widget child;

  const GamepadShortcutManager({super.key, required this.child});

  @override
  State<GamepadShortcutManager> createState() => _GamepadShortcutManagerState();
}

class _GamepadShortcutManagerState extends State<GamepadShortcutManager> {
  StreamSubscription<GamepadEvent>? _gamepadSubscription;
  
  // ─── DIGITAL BUTTONS STATE ───
  Timer? _repeatTimer;
  String? _heldKey;
  final int initialDelayMs = 350; 
  final int repeatIntervalMs = 150; 

  // ─── ANALOG VELOCITY ENGINE STATE ───
  double _analogX = 0.0;
  double _analogY = 0.0;
  double _bucketX = 0.0;
  double _bucketY = 0.0;
  bool _isFirstMoveX = true;
  bool _isFirstMoveY = true;
  Timer? _analogTimer;

  // 🎛️ VELOCITY TWEAKS
  final double analogDeadzone = 0.15; // Ignore tiny stick drifts
  final double analogThreshold = 130.0; // Target threshold to fire a movement (Lower = Faster max speed)
  final double analogInitialDelay = -250.0; // Adds 250ms delay before repeat kicks in

  @override
  void initState() {
    super.initState();
    _initGamepadListener();
  }

  void _initGamepadListener() async {
    _gamepadSubscription = Gamepads.events.listen((GamepadEvent event) {
      final key = event.key.toLowerCase();

      // 1. ANALOG STICKS (Velocity Engine)
      if (event.type == KeyType.analog) {
        final value = event.value;
        final isXAxis = key.endsWith('x') || key.contains('_x') || key.contains('axis 0') || key.contains('axis-0');
        final isYAxis = key.endsWith('y') || key.contains('_y') || key.contains('axis 1') || key.contains('axis-1');

        if (isXAxis) _analogX = value;
        if (isYAxis) _analogY = value;

        if (_analogX.abs() > analogDeadzone || _analogY.abs() > analogDeadzone) {
          _startAnalogTimer();
        }
        return;
      }

      // 2. DIGITAL BUTTONS (D-Pad, Bumpers)
      if (event.type == KeyType.button) {
        if (event.value == 1.0) {
          if (key.contains('dpad') || key.contains('l1') || key.contains('r1') || 
              key.contains('lb') || key.contains('rb') || key.contains('shoulder') || 
              key.contains('bumper') || key.contains('button 4') || key.contains('button 5')) {
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

  // ========================================================
  // 🏎️ ANALOG VELOCITY TICKER (60 FPS)
  // ========================================================
  void _startAnalogTimer() {
    if (_analogTimer != null) return;

    _analogTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      bool isMoving = false;

      // --- X AXIS (Left / Right) ---
      if (_analogX.abs() > analogDeadzone) {
        isMoving = true;
        if (_isFirstMoveX) {
          _fireGamepadAction(_analogX > 0 ? 'dpadright' : 'dpadleft');
          _isFirstMoveX = false;
          _bucketX = analogInitialDelay; // Pause briefly after initial tap
        } else {
          // Calculate speed based on how hard the stick is pushed!
          double normalized = (_analogX.abs() - analogDeadzone) / (1.0 - analogDeadzone);
          double speedFactor = Curves.easeIn.transform(normalized.clamp(0.0, 1.0));
          speedFactor = speedFactor.clamp(0.15, 1.0); // 15% minimum speed

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

      // --- Y AXIS (Up / Down) ---
      if (_analogY.abs() > analogDeadzone) {
        isMoving = true;
        if (_isFirstMoveY) {
          _fireGamepadAction(_analogY > 0 ? 'dpadup' : 'dpaddown');
          _isFirstMoveY = false;
          _bucketY = analogInitialDelay;
        } else {
          double normalized = (_analogY.abs() - analogDeadzone) / (1.0 - analogDeadzone);
          double speedFactor = Curves.easeIn.transform(normalized.clamp(0.0, 1.0));
          speedFactor = speedFactor.clamp(0.15, 1.0);

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

      if (!isMoving) {
        _stopAnalogTimer();
      }
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

  // ========================================================
  // 🕹️ DIGITAL REPEATER (D-Pad)
  // ========================================================
  void _handleHeldMove(String actionKey) {
    if (_heldKey != actionKey) {
      _heldKey = actionKey;
      _fireGamepadAction(actionKey);
      
      _repeatTimer?.cancel();
      _repeatTimer = Timer(Duration(milliseconds: initialDelayMs), () {
        _repeatTimer = Timer.periodic(Duration(milliseconds: repeatIntervalMs), (timer) {
          _fireGamepadAction(actionKey);
        });
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
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return;

    if (key == 'a' || key.contains('button_a') || key.contains('button 0') || key == 'south') {
      Actions.maybeInvoke(context, const ActivateIntent());
    } 
    else if (key == 'b' || key.contains('button_b') || key.contains('button 1') || key == 'east') {
      Actions.maybeInvoke(context, const AppBackIntent());
    } 
    else if (key == 'x' || key.contains('button_x') || key.contains('button 2') || key == 'west') {
      Actions.maybeInvoke(context, const AppSecondaryIntent());
    } 
    else if (key == 'y' || key.contains('button_y') || key.contains('button 3') || key == 'north') {
      Actions.maybeInvoke(context, const AppTertiaryIntent());
    }
    else if (key == 'select' || key == 'view' || key == 'back' || key == 'minus' || key.contains('button 6') || key.contains('button 8') || key.contains('button_select')) {
      Actions.maybeInvoke(context, const AppSelectButtonIntent());
    }
    else if (key == 'start' || key == 'menu' || key == 'options' || key.contains('button_start') || key.contains('button 7') || key.contains('button 11') || key == 'plus') {
      Actions.maybeInvoke(context, const AppMenuIntent());
    }
    else if (key.contains('l1') || key.contains('lb') || key.contains('button 4') || key.contains('left_shoulder') || key.contains('leftshoulder') || key.contains('left_bumper')) {
      Actions.maybeInvoke(context, const AppLeftBumperIntent());
    }
    else if (key.contains('r1') || key.contains('rb') || key.contains('button 5') || key.contains('right_shoulder') || key.contains('rightshoulder') || key.contains('right_bumper')) {
      Actions.maybeInvoke(context, const AppRightBumperIntent());
    }
    else if (key.contains('dpadup') || key.contains('dpad_up')) {
      Actions.maybeInvoke(context, const GamepadDirectionalIntent(TraversalDirection.up));
    } else if (key.contains('dpaddown') || key.contains('dpad_down')) {
      Actions.maybeInvoke(context, const GamepadDirectionalIntent(TraversalDirection.down));
    } else if (key.contains('dpadleft') || key.contains('dpad_left')) {
      Actions.maybeInvoke(context, const GamepadDirectionalIntent(TraversalDirection.left));
    } else if (key.contains('dpadright') || key.contains('dpad_right')) {
      Actions.maybeInvoke(context, const GamepadDirectionalIntent(TraversalDirection.right));
    }
  }

  @override
  void dispose() {
    _stopAnalogTimer();
    _repeatTimer?.cancel();
    _gamepadSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const AppSelectIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): const AppSelectIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape): const AppBackIntent(),
        LogicalKeySet(LogicalKeyboardKey.goBack): const AppBackIntent(),
        LogicalKeySet(LogicalKeyboardKey.pageUp): const AppLeftBumperIntent(),
        LogicalKeySet(LogicalKeyboardKey.pageDown): const AppRightBumperIntent(),
      },
      child: widget.child,
    );
  }
}