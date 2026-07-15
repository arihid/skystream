import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'gamepad_intents.dart';
import '../../shared/widgets/global_system_menu.dart'; 

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
          final targetContext = FocusManager.instance.primaryFocus?.context ?? context;
          Navigator.maybePop(targetContext);
          return null;
        },
      ),
      GamepadDirectionalIntent: CallbackAction<GamepadDirectionalIntent>(
        onInvoke: (GamepadDirectionalIntent intent) {
          final primaryFocus = FocusManager.instance.primaryFocus;
          
          if (primaryFocus == null || primaryFocus.context == null || !primaryFocus.context!.mounted) {
            FocusManager.instance.rootScope.focusInDirection(intent.direction);
            return null;
          }

          final currentRenderObject = primaryFocus.context!.findRenderObject();

          if (currentRenderObject is! RenderBox || !currentRenderObject.attached) {
            FocusManager.instance.rootScope.focusInDirection(intent.direction);
            return null;
          }

          final currentRect = currentRenderObject.localToGlobal(Offset.zero) & currentRenderObject.size;
          
          // Normal native directional movement
          bool moved = primaryFocus.focusInDirection(intent.direction);

          if (moved) {
            final newContext = FocusManager.instance.primaryFocus?.context;
            if (newContext != null) {
              if (intent.direction == TraversalDirection.left || intent.direction == TraversalDirection.right) {
                // Safenet: Prevent horizontal movement from jumping to a different vertical row
                final newRenderObject = newContext.findRenderObject();
                if (newRenderObject is RenderBox) {
                  final newRect = newRenderObject.localToGlobal(Offset.zero) & newRenderObject.size;
                  final dyDiff = (currentRect.center.dy - newRect.center.dy).abs();
                  
                  if (dyDiff > (currentRect.height / 2)) {
                    primaryFocus.requestFocus(); 
                  }
                }
              }
            }
          } else {
            // Horizontal blind fallback
            if (intent.direction == TraversalDirection.left || intent.direction == TraversalDirection.right) {
              primaryFocus.nextFocus();
            }
            // Vertical failure is now completely ignored, letting Flutter's upstream engine handle it natively!
          }
          return null;
        },
      ),
      
      AppLeftBumperIntent: CallbackAction<AppLeftBumperIntent>(onInvoke: (_) => null),
      AppRightBumperIntent: CallbackAction<AppRightBumperIntent>(onInvoke: (_) => null),
      
      AppMenuIntent: CallbackAction<AppMenuIntent>(
        onInvoke: (_) {
          final targetContext = FocusManager.instance.primaryFocus?.context ?? context;
          GlobalSystemMenu.toggle(targetContext);
          return null;
        }
      ),
      
      AppSecondaryIntent: CallbackAction<AppSecondaryIntent>(onInvoke: (_) => null),
      AppTertiaryIntent: CallbackAction<AppTertiaryIntent>(onInvoke: (_) => null),
      AppSelectButtonIntent: CallbackAction<AppSelectButtonIntent>(onInvoke: (_) => null),
    };
  }
}