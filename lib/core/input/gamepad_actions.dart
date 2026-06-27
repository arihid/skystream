import 'package:flutter/widgets.dart';
import 'gamepad_intents.dart';

class AppActionBindings {
  static Map<Type, Action<Intent>> getBindings(BuildContext context) {
    return {
      AppSelectIntent: CallbackAction<AppSelectIntent>(
        onInvoke: (AppSelectIntent intent) {
          final FocusNode? primaryFocus = FocusManager.instance.primaryFocus;
          if (primaryFocus != null && primaryFocus.context != null) {
            // Find the nearest primary input component (like InkWell or GestureDetector) 
            // and invoke its click/tap behavior programmatically.
            Actions.invoke(primaryFocus.context!, const ActivateIntent());
          }
          return null;
        },
      ),
      AppBackIntent: CallbackAction<AppBackIntent>(
        onInvoke: (AppBackIntent intent) {
          // Triggers standard Navigator pop behavior globally
          Navigator.of(context).maybePop();
          return null;
        },
      ),
      AppContextIntent: CallbackAction<AppContextIntent>(
        onInvoke: (AppContextIntent intent) {
          // Optional: Handle context menu / long-press simulation globally
          return null;
        },
      ),
    };
  }
}