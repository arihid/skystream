import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:skystream/core/input/gamepad_actions.dart';

import '../player_controller.dart';
import '../../../../shared/widgets/custom_widgets.dart';
import '../../../../l10n/generated/app_localizations.dart';


class PlayerLoadingOverlay extends StatefulWidget {
  final VoidCallback onDoubleTap;
  final VoidCallback onBack;
  final PlaybackUiPhase phase;
  final List<SourceAttemptEntry> sourceAttempts;
  final String? backdropUrl;
  final String? logoUrl;
  final VoidCallback? onGoLive;
  final VoidCallback? onSkip;
  final bool isTv;

  const PlayerLoadingOverlay({
    super.key,
    required this.onDoubleTap,
    required this.onBack,
    required this.phase,
    required this.sourceAttempts,
    this.backdropUrl,
    this.logoUrl,
    this.onGoLive,
    this.onSkip,
    this.isTv = false,
  });

  @override
  State<PlayerLoadingOverlay> createState() => _PlayerLoadingOverlayState();
}

class _PlayerLoadingOverlayState extends State<PlayerLoadingOverlay> {
  late final FocusScopeNode _overlayScopeNode;

  @override
  void initState() {
    super.initState();
    _overlayScopeNode = FocusScopeNode(debugLabel: 'LoadingOverlayScope');
    _stealFocus();
  }

  @override
  void didUpdateWidget(PlayerLoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldHasActions = _hasActions(oldWidget);
    final newHasActions = _hasActions(widget);
    
    if ((!oldHasActions && newHasActions) || (newHasActions && !_overlayScopeNode.hasFocus)) {
      _stealFocus();
    } else if (!newHasActions && oldHasActions) {
      _stealFocus();
    }
  }

  @override
  void dispose() {
    _overlayScopeNode.dispose();
    super.dispose();
  }

  bool _hasActions(PlayerLoadingOverlay w) {
    return (w.onSkip != null) ||
           (w.phase.showGoLive && w.onGoLive != null) ||
           (w.phase.kind == PlaybackUiPhaseKind.error);
  }

  void _stealFocus() {
    if (!widget.isTv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Force focus out of the PlayerScreen root and into this overlay's buttons
      _overlayScopeNode.requestFocus();
    });
  }

  Widget _buildMiniHint(BuildContext context, String btn, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            btn,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).shortestSide < 600;
    final l10n = AppLocalizations.of(context)!;

    final content = _LoadingCard(
      phase: widget.phase,
      sourceAttempts: widget.sourceAttempts,
      logoUrl: widget.logoUrl,
      onGoLive: widget.onGoLive,
      onSkip: widget.onSkip,
      onBack: widget.onBack,
      isTv: widget.isTv,
    );

    return FocusScope(
      node: _overlayScopeNode,
      child: GestureDetector(
        onDoubleTap: widget.onDoubleTap,
        behavior: HitTestBehavior.translucent,
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: Stack(
            children: [
              Positioned.fill(
                child: Stack(
                  children: [
                    if (widget.backdropUrl != null && (!isCompact || widget.isTv))
                      Positioned.fill(
                        child: CachedNetworkImage(
                          imageUrl: widget.backdropUrl!,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          placeholder: (_, _) => const SizedBox.shrink(),
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.5),
                              Colors.black.withValues(alpha: 0.5),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: content,
                  ),
                ),
              ),
              
              if (widget.isTv)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.only(top: 64, bottom: 32),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.9),
                          Colors.black.withValues(alpha: 0.4),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.onSkip != null) ...[
                          _buildMiniHint(context, 'A', l10n.skip, Colors.greenAccent.shade400),
                          const SizedBox(width: 16),
                        ] else if (widget.phase.showGoLive && widget.onGoLive != null) ...[
                          _buildMiniHint(context, 'A', l10n.goLive, Colors.greenAccent.shade400),
                          const SizedBox(width: 16),
                        ] else if (widget.phase.kind == PlaybackUiPhaseKind.error) ...[
                          _buildMiniHint(context, 'A', l10n.goBack, Colors.greenAccent.shade400),
                          const SizedBox(width: 16),
                        ],
                        _buildMiniHint(context, 'B', l10n.cancel, Colors.redAccent.shade400),
                      ],
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

class _LoadingCard extends StatelessWidget {
  final PlaybackUiPhase phase;
  final List<SourceAttemptEntry> sourceAttempts;
  final String? logoUrl;
  final VoidCallback? onGoLive;
  final VoidCallback? onSkip;
  final VoidCallback? onBack;
  final bool isTv;

  const _LoadingCard({
    required this.phase,
    required this.sourceAttempts,
    this.logoUrl,
    this.onGoLive,
    this.onSkip,
    this.onBack,
    this.isTv = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showSourcePanel =
        phase.showsInlineSourcePanel && sourceAttempts.length > 1;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.0),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.0),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logoUrl != null && logoUrl!.isNotEmpty) ...[
                  if (logoUrl!.toLowerCase().endsWith('.svg'))
                    SvgPicture.network(
                      logoUrl!,
                      height: isTv ? 100 : 80,
                      fit: BoxFit.contain,
                      placeholderBuilder: (_) => const SizedBox(height: 80),
                    )
                  else
                    CachedNetworkImage(
                      imageUrl: logoUrl!,
                      height: isTv ? 100 : 80,
                      fit: BoxFit.contain,
                      placeholder: (_, _) => const SizedBox(height: 80),
                      errorWidget: (_, _, _) => const SizedBox(height: 80),
                    ),
                  const SizedBox(height: 24),
                ],
                _PhaseIndicator(phase: phase),
                const SizedBox(height: 18),
                if (phase.title.isNotEmpty)
                  Text(
                    phase.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                if ((phase.subtitle ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    phase.subtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if ((phase.detail ?? '').isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    phase.detail!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 14,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (phase.attemptIndex != null &&
                    phase.attemptTotal != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l10n.sourceAttempt(
                        phase.attemptIndex!,
                        phase.attemptTotal!,
                      ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (_hasActions) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      if (onSkip != null)
                        _ActionButton(
                          label: l10n.skip,
                          icon: Icons.fast_forward_rounded,
                          onPressed: onSkip,
                          primary: true,
                          isTv: isTv,
                          autofocus: isTv,
                        ),
                      if (phase.showGoLive && onGoLive != null)
                        _ActionButton(
                          label: l10n.goLive,
                          icon: Icons.live_tv,
                          onPressed: onGoLive,
                          primary: false,
                          isTv: isTv,
                          autofocus: isTv && onSkip == null,
                        ),
                      if (phase.kind == PlaybackUiPhaseKind.error &&
                          onBack != null)
                        _ActionButton(
                          label: l10n.goBack,
                          icon: Icons.arrow_back_rounded,
                          onPressed: onBack,
                          primary: false,
                          isTv: isTv,
                          autofocus:
                              isTv && onSkip == null && !phase.showGoLive,
                        ),
                    ],
                  ),
                ],
                if (showSourcePanel) ...[
                  const SizedBox(height: 18),
                  _SourceAttemptList(attempts: sourceAttempts),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasActions =>
      (onSkip != null) ||
      (phase.showGoLive && onGoLive != null) ||
      (phase.kind == PlaybackUiPhaseKind.error && onBack != null);
}

class _PhaseIndicator extends StatelessWidget {
  final PlaybackUiPhase phase;

  const _PhaseIndicator({required this.phase});

  @override
  Widget build(BuildContext context) {
    const size = 42.0;

    if (phase.kind == PlaybackUiPhaseKind.error) {
      return Icon(Icons.error_outline, color: Colors.red.shade300, size: size);
    }

    return const SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 3,
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool isTv;
  final bool autofocus;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.primary,
    this.isTv = false,
    this.autofocus = false,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isFocused = false;
  bool _isHovered = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'ActionButton_${widget.label}');
    if (widget.autofocus && widget.isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(_ActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus && !oldWidget.autofocus && widget.isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = widget.primary
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final fgColor = widget.primary
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
          AppSelectButtonIntent: CallbackAction<AppSelectButtonIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _focusNode,
          onFocusChange: (hasFocus) {
            setState(() => _isFocused = hasFocus);
          },
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.space) {
              widget.onPressed?.call();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              onTap: widget.onPressed,
              child: AnimatedScale(
                scale: _isFocused ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _isFocused
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: _isFocused || _isHovered
                        ? [
                            BoxShadow(
                              color: bgColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            )
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 18, color: fgColor),
                      const SizedBox(width: 8),
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: fgColor, 
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
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

class _SourceAttemptList extends StatefulWidget {
  final List<SourceAttemptEntry> attempts;

  const _SourceAttemptList({required this.attempts});

  @override
  State<_SourceAttemptList> createState() => _SourceAttemptListState();
}

class _SourceAttemptListState extends State<_SourceAttemptList> {
  static const double _rowExtent = 46;
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant _SourceAttemptList oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (!_controller.hasClients || widget.attempts.length <= 6) return;
    final currentIndex = widget.attempts.indexWhere((a) => a.isCurrent);
    if (currentIndex == -1) return;

    final target = (currentIndex * _rowExtent) - (_rowExtent * 2);
    _controller.animateTo(
      target.clamp(0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      controller: _controller,
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      itemCount: widget.attempts.length,
      separatorBuilder: (_, _) =>
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
      itemBuilder: (context, index) {
        final attempt = widget.attempts[index];
        return _SourceAttemptRow(attempt: attempt);
      },
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(18), child: list),
      ),
    );
  }
}

class _SourceAttemptRow extends StatelessWidget {
  final SourceAttemptEntry attempt;

  const _SourceAttemptRow({required this.attempt});

  @override
  Widget build(BuildContext context) {
    final (icon, color, statusLabel) = _statusPresentation(
      context,
      attempt.status,
    );
    final highlight = attempt.isCurrent;

    return Material(
      color: highlight
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.transparent,
      child: SizedBox(
        height: 46,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Center(
                  child:
                      icon ??
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  attempt.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                statusLabel,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (Widget?, Color, String) _statusPresentation(
    BuildContext context,
    SourceAttemptStatus status,
  ) {
    final l10n = AppLocalizations.of(context)!;
    switch (status) {
      case SourceAttemptStatus.trying:
        return (
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          Colors.white,
          l10n.trying,
        );
      case SourceAttemptStatus.failed:
        return (
          Icon(Icons.close_rounded, size: 16, color: Colors.red.shade300),
          Colors.red.shade300,
          l10n.failed,
        );
      case SourceAttemptStatus.selected:
        return (
          const Icon(Icons.radio_button_checked, size: 16, color: Colors.white),
          Colors.white,
          l10n.selected,
        );
      case SourceAttemptStatus.playing:
        return (
          Icon(Icons.check_circle, size: 16, color: Colors.green.shade300),
          Colors.green.shade300,
          l10n.playing,
        );
      case SourceAttemptStatus.pending:
        return (
          const Icon(
            Icons.radio_button_unchecked,
            size: 16,
            color: Colors.white54,
          ),
          Colors.white70,
          l10n.pending,
        );
    }
  }
}