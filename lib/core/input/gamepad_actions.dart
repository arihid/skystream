import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'gamepad_intents.dart';

// ---- CUSTOM GAMEPAD INTENTS ----
class AppMenuIntent extends Intent { const AppMenuIntent(); }
class AppSecondaryIntent extends Intent { const AppSecondaryIntent(); }
class AppTertiaryIntent extends Intent { const AppTertiaryIntent(); } 
class GamepadDirectionalIntent extends Intent {
  final TraversalDirection direction;
  const GamepadDirectionalIntent(this.direction);
}
class AppLeftBumperIntent extends Intent { const AppLeftBumperIntent(); }
class AppRightBumperIntent extends Intent { const AppRightBumperIntent(); }
class AppSelectButtonIntent extends Intent { const AppSelectButtonIntent(); }
// ------------------------------------

class AppActionBindings {
  static Map<Type, Action<Intent>> getBindings(BuildContext context) {
    return {
      AppSelectIntent: CallbackAction<AppSelectIntent>(
        onInvoke: (_) {
          final primaryFocus = FocusManager.instance.primaryFocus;
          if (primaryFocus != null && primaryFocus.context != null) {
            Actions.invoke(primaryFocus.context!, const ActivateIntent());
          }
          return null;
        },
      ),
      AppBackIntent: CallbackAction<AppBackIntent>(
        onInvoke: (_) {
          final targetContext = FocusManager.instance.primaryFocus?.context;
          if (targetContext != null) {
            Navigator.maybePop(targetContext);
          }
          return null;
        },
      ),
      GamepadDirectionalIntent: CallbackAction<GamepadDirectionalIntent>(
        onInvoke: (GamepadDirectionalIntent intent) {
          final primaryFocus = FocusManager.instance.primaryFocus;
          if (primaryFocus == null || primaryFocus.context == null) return null;

          final currentRenderObject = primaryFocus.context!.findRenderObject();
          if (currentRenderObject is! RenderBox) return null;

          final currentRect = currentRenderObject.localToGlobal(Offset.zero) & currentRenderObject.size;
          bool moved = primaryFocus.focusInDirection(intent.direction);

          if (moved && (intent.direction == TraversalDirection.left || intent.direction == TraversalDirection.right)) {
            final newContext = FocusManager.instance.primaryFocus?.context;
            if (newContext != null) {
              final newRenderObject = newContext.findRenderObject();
              if (newRenderObject is RenderBox) {
                final newRect = newRenderObject.localToGlobal(Offset.zero) & newRenderObject.size;
                if ((currentRect.center.dy - newRect.center.dy).abs() > (currentRect.height / 2)) {
                  primaryFocus.requestFocus(); 
                }
              }
            }
          }
          return null;
        },
      ),
      AppLeftBumperIntent: CallbackAction<AppLeftBumperIntent>(onInvoke: (_) {
        Actions.maybeInvoke(FocusManager.instance.primaryFocus?.context ?? context, const ScrollIntent(direction: AxisDirection.up, type: ScrollIncrementType.page));
        return null;
      }),
      AppRightBumperIntent: CallbackAction<AppRightBumperIntent>(onInvoke: (_) {
        Actions.maybeInvoke(FocusManager.instance.primaryFocus?.context ?? context, const ScrollIntent(direction: AxisDirection.down, type: ScrollIncrementType.page));
        return null;
      }),
      AppMenuIntent: CallbackAction<AppMenuIntent>(
        onInvoke: (_) {
          final scaffold = Scaffold.maybeOf(FocusManager.instance.primaryFocus?.context ?? context);
          if (scaffold != null) {
            if (scaffold.hasDrawer && !scaffold.isDrawerOpen) scaffold.openDrawer();
            else if (scaffold.hasEndDrawer && !scaffold.isEndDrawerOpen) scaffold.openEndDrawer();
          }
          return null;
        }
      ),
      AppSecondaryIntent: CallbackAction<AppSecondaryIntent>(onInvoke: (_) => null),
      AppTertiaryIntent: CallbackAction<AppTertiaryIntent>(onInvoke: (_) => null),
      AppSelectButtonIntent: CallbackAction<AppSelectButtonIntent>(onInvoke: (_) => null),
    };
  }
}