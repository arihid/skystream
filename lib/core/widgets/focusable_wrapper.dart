import 'package:flutter/material.dart';
import '../input/gamepad_actions.dart'; // Import custom intents

class FocusableWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap; // <-- NEW: Accept 'X' button callbacks
  final VoidCallback? onLongPress;    // <-- Accept 'Y' button / Touch-and-Hold

  const FocusableWrapper({
    super.key, 
    required this.child, 
    required this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
  });

  @override
  State<FocusableWrapper> createState() => _FocusableWrapperState();
}

class _FocusableWrapperState extends State<FocusableWrapper> {
  final FocusNode _focusNode = FocusNode();
  bool _isHovered = false; 

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        // 'A' Button / Tap
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            widget.onTap(); 
            return null;
          },
        ),
        // 'X' Button / Secondary Tap
        AppSecondaryIntent: CallbackAction<AppSecondaryIntent>(
          onInvoke: (AppSecondaryIntent intent) {
            // Smart Fallback: If onSecondaryTap isn't defined, use onLongPress.
            // This ensures episode cards still download on 'X' without breaking!
            if (widget.onSecondaryTap != null) {
              widget.onSecondaryTap!();
            } else if (widget.onLongPress != null) {
              widget.onLongPress!();
            }
            return null;
          }
        ),
        // 'Y' Button / Tertiary / Long Press
        AppTertiaryIntent: CallbackAction<AppTertiaryIntent>(
          onInvoke: (AppTertiaryIntent intent) {
            if (widget.onLongPress != null) widget.onLongPress!();
            return null;
          }
        ),
      },
      child: Focus(
        focusNode: _focusNode,
        onFocusChange: (hasFocus) {
          if (hasFocus) {
            if (Scrollable.maybeOf(context) != null) {
              Scrollable.ensureVisible(
                context,
                alignment: 0.5,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
              );
            }
          }
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress, // Sync touch long-press to the Y action
            child: AnimatedBuilder(
              animation: _focusNode,
              builder: (context, child) {
                final bool isActive = _focusNode.hasFocus || _isHovered;
                
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  transform: isActive 
                      ? (Matrix4.identity()..scale(1.04)) 
                      : Matrix4.identity(),
                  transformAlignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive 
                          ? Theme.of(context).colorScheme.primary 
                          : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withAlpha(100),
                              blurRadius: 12,
                              spreadRadius: 2,
                            )
                          ]
                        : [],
                  ),
                  child: child,
                );
              },
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}