import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/router/app_router.dart';
import '../../core/widgets/focusable_wrapper.dart';

class GlobalSystemMenu extends StatelessWidget {
  const GlobalSystemMenu({super.key});

  static bool _isOpen = false;

  // 🎮 Summon the Steam Big Picture style menu from ANYWHERE!
  static Future<void> show(BuildContext context) async {
    if (_isOpen) return;
    _isOpen = true;

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'System Menu',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SlideTransition(
          // Slide in from the left edge (Offset(-1, 0)) to the center
          position: Tween<Offset>(
            begin: const Offset(-1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: FadeTransition(
            opacity: animation,
            child: const GlobalSystemMenu(),
          ),
        );
      },
    );

    // 🎯 Wait for the dialog to be dismissed (via 'B' button, tap, or pop), then reset state
    _isOpen = false;
  }

  // 🎯 Safely toggle the menu open/closed
  static void toggle(BuildContext context) {
    if (_isOpen) {
      // Cleanly dismiss the top-most dialog (our menu)
      Navigator.of(context, rootNavigator: true).pop();
    } else {
      show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Align(
      alignment: Alignment.centerLeft, // Lock to the left edge
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          height: double.infinity, // Full screen height
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.95),
            border: Border(
              right: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2), width: 1),
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: 10),
            ],
          ),
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 24.0),
                  child: FocusTraversalGroup(
                    policy: WidgetOrderTraversalPolicy(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- Logo Header ---
                        Padding(
                          padding: const EdgeInsets.only(left: 12.0, bottom: 48.0),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.asset(
                                  'assets/images/ic_launcher_foreground.png',
                                  width: 36,
                                  height: 36,
                                  errorBuilder: (context, error, stack) => Icon(
                                    Icons.videogame_asset_rounded, 
                                    color: theme.colorScheme.primary, 
                                    size: 36,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text('SkyStream', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        
                        // --- Navigation Items ---
                        _MenuButton(
                          icon: Icons.home_rounded,
                          label: 'Home',
                          autofocus: true, // Focus starts here!
                          onTap: () {
                            Navigator.pop(context);
                            const HomeRoute().go(context);
                          },
                        ),
                        const SizedBox(height: 8),
                        _MenuButton(
                          icon: Icons.explore_rounded,
                          label: 'Explore',
                          onTap: () {
                            Navigator.pop(context);
                            const ExploreRoute().go(context);
                          },
                        ),
                        const SizedBox(height: 8),
                        _MenuButton(
                          icon: Icons.video_library_rounded,
                          label: 'Library',
                          onTap: () {
                            Navigator.pop(context);
                            const LibraryRoute().go(context);
                          },
                        ),
                        
                        const Spacer(),
                        const Divider(height: 32),
                        
                        // --- System Actions ---
                        _MenuButton(
                          icon: Icons.settings_rounded,
                          label: 'Settings',
                          onTap: () {
                            Navigator.pop(context);
                            const SettingsRoute().push<void>(context);
                          },
                        ),
                        const SizedBox(height: 16),
                        _MenuButton(
                          icon: Icons.power_settings_new_rounded,
                          label: 'Exit SkyStream',
                          isDestructive: true,
                          onTap: () {
                            showDialog<void>(
                              context: context,
                              builder: (context) {
                                return AlertDialog(
                                  title: const Text('Exit SkyStream?'),
                                  content: const Text('Are you sure you want to exit the app?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context), // Cancel
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context); // Close dialog
                                        exit(0); // Exit app
                                      },
                                      child: const Text('Exit'),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final bool isDestructive;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.isDestructive = false,
  });

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  final FocusNode _focusNode = FocusNode();
  bool _isHovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.isDestructive ? theme.colorScheme.error : theme.colorScheme.primary;
    final onColor = widget.isDestructive ? theme.colorScheme.onError : theme.colorScheme.onPrimary;

    return FocusableWrapper(
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      child: Focus(
        focusNode: _focusNode,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedBuilder(
            animation: _focusNode,
            builder: (context, child) {
              final isActive = _focusNode.hasFocus || _isHovered;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: isActive ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.icon,
                      color: isActive ? onColor : theme.colorScheme.onSurfaceVariant,
                      size: 26,
                    ),
                    const SizedBox(width: 20),
                    Text(
                      widget.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isActive ? onColor : theme.colorScheme.onSurface,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}