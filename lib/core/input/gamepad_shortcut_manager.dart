import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:gamepads/gamepads.dart';
import 'gamepad_intents.dart';

class GamepadShortcutManager extends StatefulWidget {
  final Widget child;

  const GamepadShortcutManager({super.key, required this.child});

  @override
  State<GamepadShortcutManager> createState() => _GamepadShortcutManagerState();
}

class _GamepadShortcutManagerState extends State<GamepadShortcutManager> {
  StreamSubscription<GamepadEvent>? _gamepadSubscription;

  @override
  void initState() {
    super.initState();
    _initGamepadListener();
  }

void _initGamepadListener() async {
    // Listen to raw hardware events across Windows, macOS, Linux, and Android
    _gamepadSubscription = Gamepads.events.listen((GamepadEvent event) {
      // We only care about button presses (value == 1.0), ignore releases (0.0)
      if (event.type == KeyType.button && event.value == 1.0) {
        // FIXED: The property is event.key, not event.id
        _handleGamepadButton(event.key); 
      }
    });
  }

void _handleGamepadButton(String rawKey) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return;

    final key = rawKey.toLowerCase();

    // Select / Enter (A Button)
    if (key == 'a' || key.contains('button_a') || key.contains('button 0')) {
      // maybeInvoke prevents the crash if the focused item isn't natively clickable
      Actions.maybeInvoke(context, const ActivateIntent());
    } 
    // Back / Escape (B Button)
    else if (key == 'b' || key.contains('button_b') || key.contains('button 1')) {
      Navigator.maybePop(context);
    } 
    // Context Menu (X / Square Button)
    else if (key == 'x' || key.contains('button_x') || key.contains('button 2')) {
      // Optional: Add custom intent for X button later
    } 
    
    // D-Pad Navigation (Using Native Intents to jump between layout groups like Sidebars)
    else if (key.contains('dpadup') || key.contains('dpad_up')) {
      Actions.maybeInvoke(context, const DirectionalFocusIntent(TraversalDirection.up));
    } else if (key.contains('dpaddown') || key.contains('dpad_down')) {
      Actions.maybeInvoke(context, const DirectionalFocusIntent(TraversalDirection.down));
    } else if (key.contains('dpadleft') || key.contains('dpad_left')) {
      Actions.maybeInvoke(context, const DirectionalFocusIntent(TraversalDirection.left));
    } else if (key.contains('dpadright') || key.contains('dpad_right')) {
      Actions.maybeInvoke(context, const DirectionalFocusIntent(TraversalDirection.right));
    }
  }

  @override
  void dispose() {
    _gamepadSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // We still keep the Shortcuts widget so standard keyboards and TV remotes 
    // work seamlessly alongside our raw Gamepad listener.
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const AppSelectIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): const AppSelectIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape): const AppBackIntent(),
        LogicalKeySet(LogicalKeyboardKey.goBack): const AppBackIntent(),
      },
      child: widget.child,
    );
  }
}