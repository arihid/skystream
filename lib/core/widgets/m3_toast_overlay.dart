import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';
import '../../features/settings/presentation/big_picture_provider.dart';

class M3ToastOverlay extends ConsumerWidget {
  final Widget child;

  const M3ToastOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(notificationServiceProvider);
    final isBigPicture = ref.watch(bigPictureModeProvider).isEnabled;

    return Stack(
      children: [
        child,
        ListenableBuilder(
          listenable: service,
          builder: (context, _) {
            if (service.toasts.isEmpty) return const SizedBox.shrink();

            final activeToasts = service.toasts.reversed.toList();

            return SafeArea(
              child: Align(
                alignment: isBigPicture
                    ? Alignment.bottomRight
                    : Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(
                    // 90px clears the standard TV gamepad hint row!
                    bottom: isBigPicture ? 90.0 : 40.0,
                    right: isBigPicture ? 24.0 : 0.0,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: isBigPicture
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.center,
                    children: activeToasts.map((toast) {
                      return TweenAnimationBuilder<double>(
                        key: ValueKey(toast.id),
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        tween: Tween(begin: 0.0, end: 1.0),
                        builder: (context, value, child) {
                          return Transform.translate(
                            offset: isBigPicture
                                ? Offset(
                                    40 * (1 - value),
                                    0,
                                  ) // Slide in from right
                                : Offset(
                                    0,
                                    20 * (1 - value),
                                  ), // Slide up from bottom
                            child: Opacity(opacity: value, child: child),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10.0),
                          child: isBigPicture
                              ? _SteamStyleToast(toast: toast, service: service)
                              : _M3StyleToast(toast: toast, service: service),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The Standard Material 3 Pill (for Desktop/Mobile)
class _M3StyleToast extends StatelessWidget {
  final ToastItem toast;
  final NotificationService service;

  const _M3StyleToast({required this.toast, required this.service});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (toast.type) {
      ToastType.success => Colors.greenAccent.shade400,
      ToastType.error => Colors.redAccent.shade400,
      ToastType.extension => Colors.purpleAccent.shade400,
      _ => theme.colorScheme.primary,
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.95,
          ),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (toast.leading != null) ...[
              toast.leading!,
              const SizedBox(width: 12),
            ] else if (toast.icon != null) ...[
              Icon(toast.icon, color: color, size: 20),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (toast.title != null)
                    Text(
                      toast.title!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  Text(
                    toast.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Steam Big Picture Style Card (for TV)
class _SteamStyleToast extends StatelessWidget {
  final ToastItem toast;
  final NotificationService service;

  const _SteamStyleToast({required this.toast, required this.service});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = switch (toast.type) {
      ToastType.success => Colors.greenAccent.shade400,
      ToastType.error => Colors.redAccent.shade400,
      ToastType.extension => Colors.purpleAccent.shade400,
      _ => theme.colorScheme.primary,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          toast.onAction?.call();
          service.dismissToast(toast.id);
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340, minWidth: 280),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1D),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      bottomLeft: Radius.circular(4),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (toast.leading != null) ...[
                          toast.leading!,
                          const SizedBox(width: 14),
                        ] else if (toast.icon != null) ...[
                          Icon(toast.icon, color: accentColor, size: 24),
                          const SizedBox(width: 14),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (toast.title != null)
                                Text(
                                  toast.title!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              if (toast.title != null)
                                const SizedBox(height: 4),
                              Text(
                                toast.message,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                              if (toast.actionLabel != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  toast.actionLabel!.toUpperCase(),
                                  style: TextStyle(
                                    color: accentColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
