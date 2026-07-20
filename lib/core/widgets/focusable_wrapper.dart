import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/gamepad_hints_overlay.dart';
import '../input/gamepad_actions.dart';
import '../input/gamepad_intents.dart';

class FocusableWrapper extends ConsumerStatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool useScaleEffect;
  final List<GamepadHint>? gamepadHints;

  const FocusableWrapper({
    super.key,
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.autofocus = false,
    this.focusNode,
    this.useScaleEffect = true,
    this.gamepadHints,
  });

  @override
  ConsumerState<FocusableWrapper> createState() => _FocusableWrapperState();
}

class _FocusableWrapperState extends ConsumerState<FocusableWrapper> {
  FocusNode? _internalNode;
  bool _isHovered = false;

  // Safely grab the external node, or create an internal one if null. No late variables!
  FocusNode get _effectiveNode => widget.focusNode ?? (_internalNode ??= FocusNode());

  @override
  void dispose() {
    _internalNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Actions(
        // 🎯 THE FIX: Catch the Intents fired by the Gamepad!
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
          AppSecondaryIntent: CallbackAction<AppSecondaryIntent>(
            onInvoke: (_) {
              widget.onSecondaryTap?.call();
              return null;
            },
          ),
          AppTertiaryIntent: CallbackAction<AppTertiaryIntent>(
            onInvoke: (_) {
              widget.onLongPress?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTapDown: (_) => widget.onSecondaryTap?.call(),
          onLongPress: widget.onLongPress,
          child: Focus(
            focusNode: _effectiveNode,
            autofocus: widget.autofocus,
            onFocusChange: (hasFocus) {
              setState(() {});
              if (hasFocus && widget.gamepadHints != null) {
                Future.microtask(() {
                  if (mounted) {
                    ref.read(focusedGamepadHintsProvider.notifier).state = widget.gamepadHints;
                  }
                });
              } else if (!hasFocus && widget.gamepadHints != null) {
                Future.microtask(() {
                  if (mounted) {
                    final currentHints = ref.read(focusedGamepadHintsProvider);
                    if (currentHints == widget.gamepadHints) {
                      ref.read(focusedGamepadHintsProvider.notifier).state = null;
                    }
                  }
                });
              }
            },
            child: AnimatedBuilder(
              animation: _effectiveNode,
              builder: (context, child) {
                final isFocused = _effectiveNode.hasFocus || _isHovered;
                return AnimatedScale(
                  scale: (isFocused && widget.useScaleEffect) ? 1.05 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isFocused ? Theme.of(context).colorScheme.primary : Colors.transparent,
                        width: 3,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                      boxShadow: isFocused ? [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 12,
                          spreadRadius: 2,
                        )
                      ] : [],
                    ),
                    child: widget.child,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}