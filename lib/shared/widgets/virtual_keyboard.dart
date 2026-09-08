import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gamepads/gamepads.dart';
import '../../core/widgets/focusable_wrapper.dart';

class VirtualKeyboard extends ConsumerStatefulWidget {
  final String query;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onSearch;

  const VirtualKeyboard({
    super.key,
    required this.query,
    required this.onQueryChanged,
    required this.onSearch,
  });

  @override
  ConsumerState<VirtualKeyboard> createState() => _VirtualKeyboardState();
}

class _VirtualKeyboardState extends ConsumerState<VirtualKeyboard> {
  bool _isUppercase = false;
  bool _isSymbols = false;
  bool _isKeyboardFocused = false;

  StreamSubscription<GamepadEvent>? _gamepadSubscription;
  final FocusNode _initialFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initialFocusNode.requestFocus();
      }
    });

    _gamepadSubscription = Gamepads.events.listen((event) {
      if (!mounted || !_isKeyboardFocused) return;

      // Only trigger on button press down (1.0), ignore release (0.0) or analog movement
      if (event.type == KeyType.button && event.value == 1.0) {
        final key = event.key.toLowerCase();

        if (key == 'x' || key.contains('button 2')) {
          _backspace();
        } else if (key == 'y' || key.contains('button 3')) {
          _space();
        } else if (key == 'select' ||
            key == 'view' ||
            key == 'back' ||
            key == 'minus' ||
            key.contains('button 6') ||
            key.contains('button 8') ||
            key.contains('button_select')) {
          _clear();
        } else if (key.contains('l1') ||
            key.contains('lb') ||
            key.contains('button 4') ||
            key.contains('left_shoulder') ||
            key.contains('leftshoulder')) {
          _toggleShift();
        } else if (key.contains('r1') ||
            key.contains('rb') ||
            key.contains('button 5') ||
            key.contains('right_shoulder') ||
            key.contains('rightshoulder')) {
          widget.onSearch();
        }
      }
    });
  }

  @override
  void dispose() {
    _gamepadSubscription?.cancel();
    _initialFocusNode.dispose();
    super.dispose();
  }

  void _addChar(String char) {
    widget.onQueryChanged(widget.query + char);
    if (_isUppercase) setState(() => _isUppercase = false);
  }

  void _backspace() {
    if (widget.query.isNotEmpty) {
      widget.onQueryChanged(widget.query.substring(0, widget.query.length - 1));
    }
  }

  void _space() => widget.onQueryChanged('${widget.query} ');
  void _clear() => widget.onQueryChanged('');

  void _toggleShift() {
    if (!_isSymbols) setState(() => _isUppercase = !_isUppercase);
  }

  void _toggleSymbols() => setState(() => _isSymbols = !_isSymbols);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final letters = [
      ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
      ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
      ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
    ];

    final symbols = [
      ['!', '@', '#', '\$', '%', '^', '&', '*', '(', ')'],
      ['-', '_', '=', '+', '[', ']', '{', '}', '\\', '|'],
      [';', ':', '\'', '"', ',', '.', '<', '>', '/', '?'],
    ];

    final topRow = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
    final activeGrid = _isSymbols ? symbols : letters;

    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Focus(
        skipTraversal: true,
        canRequestFocus: false,
        onFocusChange: (hasFocus) => _isKeyboardFocused = hasFocus,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            border: Border(
              top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: topRow.map((char) => _buildKey(char)).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: activeGrid[0]
                    .map(
                      (char) => _buildKey(
                        char,
                        isInitialFocus: char == 'q' || char == '!',
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: activeGrid[1].map((char) => _buildKey(char)).toList(),
              ),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_isSymbols)
                    _buildActionKey(
                      'SHIFT',
                      width: 90,
                      onTap: _toggleShift,
                      isActive: _isUppercase,
                      icon: Icons.keyboard_capslock_rounded,
                      hint: 'LB',
                    ),
                  ...activeGrid[2].map((char) => _buildKey(char)),
                  _buildActionKey(
                    'DEL',
                    width: 90,
                    onTap: _backspace,
                    icon: Icons.backspace_rounded,
                    hint: 'X',
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildActionKey(
                    _isSymbols ? 'ABC' : '!#\$',
                    width: 90,
                    onTap: _toggleSymbols,
                    isActive: _isSymbols,
                  ),
                  _buildActionKey(
                    'SPACE',
                    width: 300,
                    onTap: _space,
                    hint: 'Y',
                    isPrimary: false,
                  ),
                  _buildActionKey(
                    'CLEAR',
                    width: 90,
                    onTap: _clear,
                    icon: Icons.delete_sweep_rounded,
                    hint: 'VIEW',
                  ),
                  _buildActionKey(
                    'SEARCH',
                    width: 120,
                    onTap: widget.onSearch,
                    icon: Icons.search_rounded,
                    hint: 'RB',
                    isPrimary: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKey(String label, {bool isInitialFocus = false}) {
    final displayLabel = _isUppercase && !_isSymbols
        ? label.toUpperCase()
        : label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: FocusableWrapper(
        focusNode: isInitialFocus ? _initialFocusNode : null,
        onTap: () => _addChar(displayLabel),
        useScaleEffect: true,
        child: Container(
          width: 44,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            displayLabel,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionKey(
    String label, {
    required double width,
    required VoidCallback onTap,
    IconData? icon,
    bool isPrimary = false,
    bool isActive = false,
    String? hint,
  }) {
    final theme = Theme.of(context);
    final bgColor = isPrimary
        ? theme.colorScheme.primary
        : (isActive
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainerHighest);
    final fgColor = isPrimary
        ? theme.colorScheme.onPrimary
        : (isActive
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onSurface);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: FocusableWrapper(
        onTap: onTap,
        useScaleEffect: true,
        child: Container(
          width: width,
          height: 48,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: fgColor, size: 20),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: fgColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (hint != null)
                Positioned(
                  top: 4,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      hint,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
