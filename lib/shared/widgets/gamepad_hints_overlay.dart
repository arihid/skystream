import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';

// Global provider to hide hints completely (e.g., Virtual Keyboard open)
final showGamepadHintsProvider = StateProvider<bool>((ref) => true);

// NEW: Global provider for context-aware focused widget overrides
final focusedGamepadHintsProvider = StateProvider<List<GamepadHint>?>((ref) => null);

class GamepadHint {
  final String buttonLabel;
  final String actionLabel;
  final Color buttonColor;

  const GamepadHint({
    required this.buttonLabel,
    required this.actionLabel,
    required this.buttonColor,
  });
}

class GamepadHintsOverlay extends ConsumerWidget {
  final List<GamepadHint>? customHints; // Fallback screen-level hints

  const GamepadHintsOverlay({super.key, this.customHints});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showHints = ref.watch(showGamepadHintsProvider);
    if (!showHints) return const SizedBox.shrink();

    // The Magic: We listen to whatever the currently focused widget wants to display!
    final focusedHints = ref.watch(focusedGamepadHintsProvider);
    
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // The safe fallback hints if nothing special is focused
    final defaultHints = [
      GamepadHint(buttonLabel: 'A', actionLabel: 'Select', buttonColor: Colors.greenAccent.shade400),
      GamepadHint(buttonLabel: 'B', actionLabel: l10n?.cancel ?? 'Back', buttonColor: Colors.redAccent.shade400),
      GamepadHint(buttonLabel: '≡', actionLabel: 'Menu', buttonColor: Colors.white),
    ];

    // Priority: 1. Focused Widget -> 2. Screen-Level Overlay -> 3. Global Defaults
    final hintsToDisplay = focusedHints ?? customHints ?? defaultHints;

    return IgnorePointer(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          border: Border(
            top: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: hintsToDisplay.map((hint) {
            return Padding(
              padding: EdgeInsets.only(
                right: hint == hintsToDisplay.last ? 0 : 24,
              ),
              child: _buildHintItem(context, hint),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildHintItem(BuildContext context, GamepadHint hint) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hint.buttonColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: hint.buttonColor.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Text(
            hint.buttonLabel,
            style: TextStyle(
              color: hint.buttonColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          hint.actionLabel,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}