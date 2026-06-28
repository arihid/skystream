import 'package:flutter/material.dart';

class FocusableWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const FocusableWrapper({
    super.key, 
    required this.child, 
    required this.onTap,
  });

  @override
  State<FocusableWrapper> createState() => _FocusableWrapperState();
}

class _FocusableWrapperState extends State<FocusableWrapper> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. We wrap the item in Actions to catch the Gamepad 'A' Button
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            // 2. Trigger the exact same logic as a mouse/touch tap!
            widget.onTap(); 
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: _focusNode,
        onFocusChange: (hasFocus) {
          if (hasFocus) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
          }
        },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _focusNode,
          builder: (context, child) {
            final bool isFocused = _focusNode.hasFocus;
            
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              // Scale up slightly when targeted to mimic premium TV UI experiences
              transform: isFocused 
                  ? (Matrix4.identity()..scale(1.04)) 
                  : Matrix4.identity(),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isFocused 
                      ? Theme.of(context).colorScheme.primary 
                      : Colors.transparent,
                  width: 3,
                ),
                boxShadow: isFocused
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
    );
  }
}