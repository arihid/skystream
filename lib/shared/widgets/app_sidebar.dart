import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skystream/l10n/generated/app_localizations.dart';
import 'package:skystream/core/utils/layout_constants.dart';

/// Global provider to track whether the D-pad/keyboard navigation mode is active.
class DpadActiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool val) => state = val;
}

final isDpadActiveProvider = NotifierProvider<DpadActiveNotifier, bool>(
  DpadActiveNotifier.new,
);

/// Number of routing destinations rendered by [AppSidebar].
/// (Note: The Exit button is injected dynamically and doesn't count against this)
const int kSidebarDestinationCount = 5;

double calculateContainerSize(double distance) {
  final d = distance.clamp(-150.0, 150.0);
  if (d < 0) {
    return 40.0 + 40.0 * (1.0 + d / 150.0);
  } else {
    return 80.0 - 40.0 * (d / 150.0);
  }
}

double calculateIconSize(double distance) {
  final d = distance.clamp(-150.0, 150.0);
  if (d < 0) {
    return 20.0 + 20.0 * (1.0 + d / 150.0);
  } else {
    return 40.0 - 20.0 * (d / 150.0);
  }
}

class AppSidebar extends ConsumerStatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onItemTapped;
  final List<FocusNode> focusNodes;

  const AppSidebar({
    super.key,
    required this.currentIndex,
    required this.onItemTapped,
    required this.focusNodes,
  });

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar> {
  late final ValueNotifier<double> _mouseY;
  int? _focusedIndex;

  late final FocusNode _exitFocusNode;

  @override
  void initState() {
    super.initState();
    _mouseY = ValueNotifier(double.infinity);
    _exitFocusNode = FocusNode(debugLabel: 'sidebar_exit');

    for (int i = 0; i < widget.focusNodes.length; i++) {
      widget.focusNodes[i].addListener(_onFocusChanged);
    }
    _exitFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _mouseY.dispose();
    for (int i = 0; i < widget.focusNodes.length; i++) {
      widget.focusNodes[i].removeListener(_onFocusChanged);
    }
    _exitFocusNode.removeListener(_onFocusChanged);
    _exitFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AppSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNodes != widget.focusNodes) {
      for (final node in oldWidget.focusNodes) {
        node.removeListener(_onFocusChanged);
      }
      for (final node in widget.focusNodes) {
        node.addListener(_onFocusChanged);
      }
    }
  }

  void _onFocusChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      int? currentFocused;

      // Combine nodes to accurately detect focus across all 6 items
      final allNodes = [...widget.focusNodes, _exitFocusNode];

      for (int i = 0; i < allNodes.length; i++) {
        if (allNodes[i].hasFocus) {
          currentFocused = i;
          break;
        }
      }

      if (_focusedIndex != currentFocused) {
        setState(() {
          _focusedIndex = currentFocused;
          if (currentFocused != null && _mouseY.value == double.infinity) {
            ref
                .read<DpadActiveNotifier>(isDpadActiveProvider.notifier)
                .set(true);
          }
        });
      }
    });
  }

  void _showExitDialog(BuildContext context, AppLocalizations l10n) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.confirmExitTitle),
          content: Text(l10n.confirmExitMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (Platform.isAndroid || Platform.isIOS) {
                  SystemNavigator.pop();
                } else {
                  exit(0);
                }
              },
              child: const Text(
                'Exit',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isDpadMode = ref.watch<bool>(isDpadActiveProvider);

    final destinations = [
      (Icons.home_outlined, Icons.home, l10n.home),
      (Icons.search, Icons.search, l10n.search),
      (Icons.explore_outlined, Icons.explore, l10n.explore),
      (Icons.video_library_outlined, Icons.video_library, l10n.library),
      (Icons.settings_outlined, Icons.settings, l10n.settings),
      (
        Icons.power_settings_new_outlined,
        Icons.power_settings_new_rounded,
        l10n.exitApp,
      ),
    ];

    // Combine Focus Nodes
    final allFocusNodes = [...widget.focusNodes, _exitFocusNode];

    const double dockWidth = 64.0;

    const unscaledCenters = [36.0, 92.0, 148.0, 204.0, 260.0, 316.0];

    final dockBgColor = isDark
        ? const Color(0xFF171717)
        : const Color(0xFFF9FAFB);
    final dockBorderColor = isDark
        ? const Color(0xFF262626)
        : const Color(0xFFE5E7EB);

    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.none,
      child: Container(
        width: LayoutConstants.sidebarWidthCompact,
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        child: ValueListenableBuilder<double>(
          valueListenable: _mouseY,
          builder: (context, mouseYValue, child) {
            final itemSizes = List<double>.filled(destinations.length, 40.0);
            final iconSizes = List<double>.filled(destinations.length, 20.0);

            for (int i = 0; i < destinations.length; i++) {
              double distance = 150.0;
              if (mouseYValue != double.infinity) {
                distance = mouseYValue - unscaledCenters[i];
              } else if (_focusedIndex != null && isDpadMode) {
                final diff = (i - _focusedIndex!).abs();
                if (diff == 0) {
                  distance = 0.0;
                } else if (diff == 1) {
                  distance = 56.0;
                }
              }
              itemSizes[i] = calculateContainerSize(distance);
              iconSizes[i] = calculateIconSize(distance);
            }

            final tops = List<double>.filled(destinations.length, 0.0);
            tops[0] = 16.0;
            for (int i = 1; i < destinations.length; i++) {
              tops[i] = tops[i - 1] + itemSizes[i - 1] + 16.0;
            }
            final double dynamicDockHeight =
                tops[destinations.length - 1] +
                itemSizes[destinations.length - 1] +
                16.0;

            return MouseRegion(
              onHover: (event) {
                _mouseY.value = event.localPosition.dy;
                if (ref.read<bool>(isDpadActiveProvider)) {
                  ref
                      .read<DpadActiveNotifier>(isDpadActiveProvider.notifier)
                      .set(false);
                }
              },
              onExit: (_) {
                _mouseY.value = double.infinity;
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: const _AceternitySpringCurve(),
                width: dockWidth,
                height: dynamicDockHeight,
                clipBehavior: Clip.none,
                decoration: BoxDecoration(
                  color: dockBgColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: dockBorderColor.withValues(alpha: 0.8),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.35 : 0.08,
                      ),
                      blurRadius: 16,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: List.generate(destinations.length, (i) {
                    final (outlinedIcon, filledIcon, label) = destinations[i];

                    // The Exit button (index 5) is never technically "selected" as a route
                    final isSelected = widget.currentIndex == i && i != 5;

                    return AnimatedPositioned(
                      key: ValueKey('dock_item_$i'),
                      duration: const Duration(milliseconds: 350),
                      curve: const _AceternitySpringCurve(),
                      left: 12.0,
                      top: tops[i],
                      width: itemSizes[i],
                      height: itemSizes[i],
                      child: _SidebarDockItem(
                        focusNode: allFocusNodes[i],
                        icon: isSelected ? filledIcon : outlinedIcon,
                        label: label,
                        isSelected: isSelected,
                        iconSize: iconSizes[i],
                        onTap: () {
                          if (i == 5) {
                            _showExitDialog(context, l10n);
                          } else {
                            widget.onItemTapped(i);
                          }
                        },
                        index: i,
                        focusNodes: allFocusNodes,
                        isDpadMode: isDpadMode,
                        isDestructive: i == 5,
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SidebarDockItem extends ConsumerStatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final bool isSelected;
  final double iconSize;
  final VoidCallback onTap;
  final int index;
  final List<FocusNode> focusNodes;
  final bool isDpadMode;
  final bool isDestructive;

  const _SidebarDockItem({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.iconSize,
    required this.onTap,
    required this.index,
    required this.focusNodes,
    required this.isDpadMode,
    this.isDestructive = false,
  });

  @override
  ConsumerState<_SidebarDockItem> createState() => _SidebarDockItemState();
}

class _SidebarDockItemState extends ConsumerState<_SidebarDockItem> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final showTooltip = _isHovered || (_isFocused && widget.isDpadMode);

    final itemBgColor = widget.isDestructive && showTooltip
        ? Colors.redAccent.withValues(alpha: 0.8)
        : (isDark ? const Color(0xFF262626) : const Color(0xFFE5E7EB));

    final iconColor = widget.isDestructive && showTooltip
        ? Colors.white
        : (isDark ? Colors.white : const Color(0xFF171717));

    final tooltipBgColor = isDark
        ? const Color(0xFF262626)
        : const Color(0xFFF3F4F6);
    final tooltipBorderColor = isDark
        ? const Color(0xFF171717)
        : const Color(0xFFE5E7EB);
    final tooltipTextColor = isDark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF374151);

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          ref.read<DpadActiveNotifier>(isDpadActiveProvider.notifier).set(true);
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            if (event is KeyDownEvent) {
              widget.onTap();
            }
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (widget.index < widget.focusNodes.length - 1) {
              widget.focusNodes[widget.index + 1].requestFocus();
              return KeyEventResult.handled;
            }
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            if (widget.index > 0) {
              widget.focusNodes[widget.index - 1].requestFocus();
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _isHovered = true);
        },
        onExit: (_) {
          setState(() => _isHovered = false);
        },
        cursor: SystemMouseCursors.click,
        child: SizedBox.expand(
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final size = constraints.maxHeight;
                        return Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            color: itemBgColor,
                            shape: BoxShape.circle,
                          ),
                          child: GestureDetector(
                            onTap: () {
                              widget.focusNode.requestFocus();
                              widget.onTap();
                            },
                            child: Container(
                              color: Colors.transparent,
                              alignment: Alignment.center,
                              child: TweenAnimationBuilder<double>(
                                duration: const Duration(milliseconds: 350),
                                curve: const _AceternitySpringCurve(),
                                tween: Tween<double>(end: widget.iconSize),
                                builder: (context, animatedIconSize, child) {
                                  return Icon(
                                    widget.icon,
                                    color: iconColor,
                                    size: animatedIconSize,
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12.0),
                    IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: showTooltip ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        child: TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          tween: Tween<double>(end: showTooltip ? 0.0 : 8.0),
                          builder: (context, xOffset, child) {
                            return Transform.translate(
                              offset: Offset(xOffset, 0.0),
                              child: child,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: tooltipBgColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: tooltipBorderColor,
                                width: 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              widget.label,
                              style: TextStyle(
                                color: tooltipTextColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AceternitySpringCurve extends Curve {
  const _AceternitySpringCurve();

  @override
  double transformInternal(double t) {
    if (t == 0.0) return 0.0;
    if (t == 1.0) return 1.0;
    final double actualT = t * 0.35;
    final double val =
        1.0 -
        1.15465359 * math.exp(-14.1742431 * actualT) +
        0.15465359 * math.exp(-105.8257569 * actualT);
    return val.clamp(0.0, 1.0);
  }
}
