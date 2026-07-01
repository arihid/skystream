import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
  Timer? _repeatTimer;
  String? _heldKey;

  @override
  void initState() {
    super.initState();
    _initGamepadListener();
  }

  void _initGamepadListener() async {
    _gamepadSubscription = Gamepads.events.listen((GamepadEvent event) {
      if (event.type == KeyType.button) {
        final key = event.key.toLowerCase();
        
        if (event.value == 1.0) {
          _heldKey = key;
          _fireGamepadAction(key);
          
          // RAPID MOVEMENT FIX: Start a repeating timer for D-pad & Bumpers
          if (key.contains('dpad') || key.contains('l1') || key.contains('r1') || key.contains('lb') || key.contains('rb')) {
            _repeatTimer?.cancel();
            
            // 350ms initial delay
            _repeatTimer = Timer(const Duration(milliseconds: 350), () {
              // 150ms rapid-fire repeat (slowed down from 60ms for better control)
              _repeatTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
                _fireGamepadAction(key);
              });
            });
          }
        } else if (event.value == 0.0) {
          if (_heldKey == key) {
            _repeatTimer?.cancel();
            _repeatTimer = null;
            _heldKey = null;
          }
        }
      }
    });
  }

  void _fireGamepadAction(String key) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return;

    if (key == 'a' || key.contains('button_a') || key.contains('button 0')) {
      Actions.maybeInvoke(context, const ActivateIntent());
    } 
    else if (key == 'b' || key.contains('button_b') || key.contains('button 1')) {
      Navigator.maybePop(context);
    } 
    else if (key == 'x' || key.contains('button_x') || key.contains('button 2')) {
      Actions.maybeInvoke(context, const AppSecondaryIntent());
    } 
    else if (key == 'y' || key.contains('button_y') || key.contains('button 3')) {
      Actions.maybeInvoke(context, const AppTertiaryIntent());
    }
    else if (key == 'start' || key == 'menu' || key == 'options' || key.contains('button_start') || key.contains('button 7') || key.contains('button 11')) {
      Actions.maybeInvoke(context, const AppMenuIntent());
    }
    // NATIVE SCROLLING FIX: Delegate to Flutter's native ScrollIntent
    else if (key.contains('l1') || key.contains('lb') || key.contains('button 4')) {
      Actions.maybeInvoke(context, const ScrollIntent(direction: AxisDirection.up, type: ScrollIncrementType.page));
    }
    else if (key.contains('r1') || key.contains('rb') || key.contains('button 5')) {
      Actions.maybeInvoke(context, const ScrollIntent(direction: AxisDirection.down, type: ScrollIncrementType.page));
    }
    // D-Pad Navigation
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
        // NATIVE SCROLLING FIX: Map Keyboard Page Up/Down to native scrolling!
        LogicalKeySet(LogicalKeyboardKey.pageUp): const ScrollIntent(direction: AxisDirection.up, type: ScrollIncrementType.page),
        LogicalKeySet(LogicalKeyboardKey.pageDown): const ScrollIntent(direction: AxisDirection.down, type: ScrollIncrementType.page),
      },
      child: widget.child,
    );
  }
}