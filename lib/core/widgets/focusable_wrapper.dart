import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../input/gamepad_actions.dart';
import '../../shared/widgets/gamepad_hints_overlay.dart'; 

class FocusableWrapper extends ConsumerStatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap; 
  final VoidCallback? onLongPress;    
  final bool autofocus;
  final bool useScaleEffect;
  final List<GamepadHint>? gamepadHints;

  const FocusableWrapper({
    super.key, 
    required this.child, 
    required this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.autofocus = false,
    this.useScaleEffect = true,
    this.gamepadHints,
  });

  @override
  ConsumerState<FocusableWrapper> createState() => _FocusableWrapperState();
}

class _FocusableWrapperState extends ConsumerState<FocusableWrapper> {
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
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            widget.onTap(); 
            return null;
          },
        ),
        if (widget.onSecondaryTap != null || widget.onLongPress != null)
          AppSecondaryIntent: CallbackAction<AppSecondaryIntent>(
            onInvoke: (AppSecondaryIntent intent) {
              if (widget.onSecondaryTap != null) widget.onSecondaryTap!();
              else if (widget.onLongPress != null) widget.onLongPress!();
              return null;
            }
          ),
        if (widget.onLongPress != null)
          AppTertiaryIntent: CallbackAction<AppTertiaryIntent>(
            onInvoke: (AppTertiaryIntent intent) {
              widget.onLongPress!();
              return null;
            }
          ),
      },
      child: Focus(
        autofocus: widget.autofocus,
        focusNode: _focusNode,
        onFocusChange: (hasFocus) {
          if (widget.gamepadHints != null) {
            Future.microtask(() {
              if (mounted) {
                if (hasFocus) {
                  ref.read(focusedGamepadHintsProvider.notifier).state = widget.gamepadHints;
                } else if (ref.read(focusedGamepadHintsProvider) == widget.gamepadHints) {
                  ref.read(focusedGamepadHintsProvider.notifier).state = null;
                }
              }
            });
          }

          if (hasFocus) {
            // 🎯 THE FIX: Stripped out the buggy vertical viewport math!
            // It was accidentally grabbing horizontal bounds and forcing the vertical screen to 0.0 (Top).
            // With cacheExtent: 99999 applied elsewhere, Flutter's native focus engine handles vertical reveals safely.

            // Strict Horizontal Snapping
            final hScrollable = Scrollable.maybeOf(context, axis: Axis.horizontal);
            if (hScrollable != null) {
              hScrollable.position.ensureVisible(
                context.findRenderObject()!,
                alignment: 0.04, 
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic, 
              );
            }
          }
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: AnimatedBuilder(
              animation: _focusNode,
              builder: (context, child) {
                final bool isActive = _focusNode.hasFocus || _isHovered;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  transform: (isActive && widget.useScaleEffect) 
                      ? (Matrix4.identity()..scale(1.04)) 
                      : Matrix4.identity(),
                  transformAlignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive ? Theme.of(context).colorScheme.primary : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: isActive 
                        ? [BoxShadow(color: Theme.of(context).colorScheme.primary.withAlpha(100), blurRadius: 12, spreadRadius: 2)] 
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