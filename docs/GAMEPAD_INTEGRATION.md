# 🎮 SkyStream Gamepad & Big Picture Integration Guide

This document outlines the core architecture and best practices for adding new screens, widgets, or features to SkyStream while maintaining a seamless, console-grade Gamepad experience.

## 🧠 Core Concepts
Under the hood, Flutter treats Gamepad inputs (D-Pad, A/B/X/Y) identically to **Keyboard inputs**.
* **D-Pad / Left Stick** = Arrow Keys (`LogicalKeyboardKey.arrowUp`, etc.)
* **'A' Button** = Enter / Space / Select
* **'B' Button** = Escape / Backspace

Because of this, **Focus is everything.** If a widget cannot receive Focus, it cannot be interacted with via a controller.

---

## 🏗️ 1. The Golden Rule: Use `FocusableWrapper`
Whenever you create a clickable item (a button, a poster, a list tile), avoid using raw `GestureDetector` or `InkWell`. Instead, wrap it in our custom `FocusableWrapper`. 

`FocusableWrapper` automatically:
1. Registers the widget in the Flutter Focus Tree.
2. Listens for the 'A' button to trigger the `onTap` event.
3. Broadcasts Gamepad Hints to the screen corner when focused.
4. Applies visual scaling/animations (optional).

**✅ DO THIS:**
```dart
FocusableWrapper(
  onTap: () => print('Selected!'),
  gamepadHints: [
    GamepadHint(buttonLabel: 'A', actionLabel: 'Select', buttonColor: Colors.greenAccent),
  ],
  child: MyCustomCard(),
)
```

---

## 🎨 2. Visual Feedback (Hover vs. Focus)
A TV user has no mouse cursor. They only know where they are based on the **Focus Ring / Glow**. You must visually merge mouse-hover states and gamepad-focus states into a single `isActive` state.

**✅ DO THIS:**
```dart
bool _isFocused = false;
bool _isHovered = false;

Widget build(BuildContext context) {
  final isActive = _isFocused || _isHovered;

  return Focus(
    onFocusChange: (focused) => setState(() => _isFocused = focused),
    child: MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          border: Border.all(
            color: isActive ? Colors.blue : Colors.transparent, // Focus Ring!
            width: isActive ? 3 : 0,
          ),
        ),
        child: Text('Console Button'),
      ),
    ),
  );
}
```

---

## 💬 3. Managing Gamepad Hints
Hints tell the user what actions are available on the currently focused item. 

* If using `FocusableWrapper`, simply pass the `gamepadHints` list parameter.
* If building a custom `Focus` widget, update the provider inside `onFocusChange`:

```dart
onFocusChange: (hasFocus) {
  if (hasFocus) {
    Future.microtask(() {
      ref.read(focusedGamepadHintsProvider.notifier).state = [
        GamepadHint(buttonLabel: 'A', actionLabel: 'Play', buttonColor: Colors.greenAccent),
        GamepadHint(buttonLabel: 'Y', actionLabel: 'Download', buttonColor: Colors.yellowAccent),
      ];
    });
  } else {
    // Clear hints when focus leaves
    Future.microtask(() => ref.read(focusedGamepadHintsProvider.notifier).state = null);
  }
}
```

---

## 🗺️ 4. Advanced Navigation & Modals

### Dialogs (`showDialog`)
Flutter `AlertDialog`s do **not** autofocus buttons by default. A controller user will be trapped unless you explicitly tell Flutter which button is the safe default.
**Rule:** Always add `autofocus: true` to the "Cancel" or "Close" button.
```dart
TextButton(
  autofocus: true, // 🎯 Critical for Gamepad!
  onPressed: () => Navigator.pop(context),
  child: const Text('Cancel'),
)
```

### Bottom Sheets (`showModalBottomSheet`)
Bottom sheets have a slide-up animation (~250ms). If you request focus instantly, Flutter drops the request because the widget is moving.
**Rule:** Add a 300ms-350ms delay before requesting focus on the first item.
```dart
final firstItemFocusNode = FocusNode();

if (isBigPicture) {
  Future.delayed(const Duration(milliseconds: 350), () {
    if (firstItemFocusNode.canRequestFocus) {
      firstItemFocusNode.requestFocus();
    }
  });
}

// Bind to your first ListTile
ListTile(
  focusNode: index == 0 ? firstItemFocusNode : null,
  // ...
)
```

### Catching Custom Buttons (Back, Menus)
To intercept specific buttons (like making the 'B' button close a menu, or 'Right Arrow' dismiss a drawer), wrap your UI in an `Actions` widget or use the `onKeyEvent` callback on a `Focus` node.

```dart
Focus(
  onKeyEvent: (node, event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowRight) {
      Navigator.pop(context); // Dismiss menu on Right D-Pad
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  },
  child: MyMenuWidget(),
)
```

---

## 🚫 5. Anti-Patterns & Common Pitfalls

1. **NEVER use `ExcludeFocus` on clickable items.**
   * *Why:* `ExcludeFocus` tells the D-Pad to completely ignore the widget. If it has an `onTap`, but `ExcludeFocus` is wrapped around it, gamepad users can never reach it.
2. **Avoid `Scrollbar` on TV UIs.**
   * *Why:* Controller users navigate by jumping from item to item. Physical scrollbars are meant for mice. Rely on `ListView`'s auto-scrolling when an off-screen item receives focus.
3. **Beware of missing `FocusTraversalGroup`.**
   * *Why:* If the D-Pad is jumping wildly to the wrong side of the screen, wrap your Column, Row, or List in a `FocusTraversalGroup(policy: WidgetOrderTraversalPolicy())`. This forces Flutter to respect the visual layout (up/down/left/right) rather than the internal memory order.
4. **Don't hardcode `--big-picture` persistence.**
   * *Why:* Steam handles display selection and window bounds automatically. Trust the launch argument and let the OS window manager do its job to prevent FFI/GPU crashes.