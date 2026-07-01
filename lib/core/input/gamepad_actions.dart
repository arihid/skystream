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
// ------------------------------------

class AppActionBindings {
  static Map<Type, Action<Intent>> getBindings(BuildContext context) {
    return {
      AppSelectIntent: CallbackAction<AppSelectIntent>(
        onInvoke: (AppSelectIntent intent) {
          final FocusNode? primaryFocus = FocusManager.instance.primaryFocus;
          if (primaryFocus != null && primaryFocus.context != null) {
            Actions.invoke(primaryFocus.context!, const ActivateIntent());
          }
          return null;
        },
      ),
      AppBackIntent: CallbackAction<AppBackIntent>(
        onInvoke: (AppBackIntent intent) {
          Navigator.of(context).maybePop();
          return null;
        },
      ),
      GamepadDirectionalIntent: CallbackAction<GamepadDirectionalIntent>(
        onInvoke: (GamepadDirectionalIntent intent) {
          final primaryFocus = FocusManager.instance.primaryFocus;
          if (primaryFocus == null) return null;

          final currentContext = primaryFocus.context;
          if (currentContext == null) return null;

          final currentRenderObject = currentContext.findRenderObject();
          if (currentRenderObject is! RenderBox) return null;

          final currentPos = currentRenderObject.localToGlobal(Offset.zero);
          final currentRect = currentPos & currentRenderObject.size;

          // 1. Tell Flutter to attempt the directional move natively
          bool moved = primaryFocus.focusInDirection(intent.direction);

          // 2. THE INVISIBLE GEOMETRY WALL (Anti-Diagonal Jump Guard)
          // If we moved Left or Right, verify we didn't jump to a different vertical row!
          if (moved && (intent.direction == TraversalDirection.left || intent.direction == TraversalDirection.right)) {
            final newFocus = FocusManager.instance.primaryFocus;
            final newContext = newFocus?.context;
            
            if (newContext != null) {
              final newRenderObject = newContext.findRenderObject();
              if (newRenderObject is RenderBox) {
                final newPos = newRenderObject.localToGlobal(Offset.zero);
                final newRect = newPos & newRenderObject.size;

                // Mathematical Proof: Overlap check.
                // We calculate the center Y of both widgets.
                final currentCenterY = currentRect.center.dy;
                final newCenterY = newRect.center.dy;
                
                // If the centers differ by more than half the height of the original item,
                // it means the new item is definitively on a different row below/above us!
                if ((currentCenterY - newCenterY).abs() > (currentRect.height / 2)) {
                  // BLOCKED: Revert focus back to the edge of the row!
                  primaryFocus.requestFocus(); 
                }
              }
            }
          }
          return null;
        },
      ),
      AppMenuIntent: CallbackAction<AppMenuIntent>(
        onInvoke: (AppMenuIntent intent) {
          final targetContext = FocusManager.instance.primaryFocus?.context ?? context;
          final ScaffoldState? scaffold = Scaffold.maybeOf(targetContext);
          if (scaffold != null) {
            if (scaffold.hasDrawer && !scaffold.isDrawerOpen) scaffold.openDrawer();
            else if (scaffold.hasEndDrawer && !scaffold.isEndDrawerOpen) scaffold.openEndDrawer();
          }
          return null;
        }
      ),
      // Dummy bindings so the global map doesn't crash if they bubble up unhandled
      AppSecondaryIntent: CallbackAction<AppSecondaryIntent>(onInvoke: (_) => null),
      AppTertiaryIntent: CallbackAction<AppTertiaryIntent>(onInvoke: (_) => null),
    };
  }
}