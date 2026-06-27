import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'gamepad_intents.dart';

class GamepadShortcutManager extends StatelessWidget {
  final Widget child;

  const GamepadShortcutManager({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Gamepad A button / Enter Key / Spacebar -> Select
        LogicalKeySet(LogicalKeyboardKey.select): const AppSelectIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): const AppSelectIntent(),
        LogicalKeySet(LogicalKeyboardKey.gameButtonA): const AppSelectIntent(),

        // Gamepad B button / Escape / Backspace -> Back
        LogicalKeySet(LogicalKeyboardKey.escape): const AppBackIntent(),
        LogicalKeySet(LogicalKeyboardKey.goBack): const AppBackIntent(),
        LogicalKeySet(LogicalKeyboardKey.gameButtonB): const AppBackIntent(),
        
        // Gamepad X or Menu button -> Context/Options
        LogicalKeySet(LogicalKeyboardKey.contextMenu): const AppContextIntent(),
        LogicalKeySet(LogicalKeyboardKey.gameButtonX): const AppContextIntent(),
      },
      child: child,
    );
  }
}