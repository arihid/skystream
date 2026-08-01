import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/utils/responsive_breakpoints.dart';
import '../../features/settings/presentation/general_settings_provider.dart';
import 'cards_wrapper.dart';
import 'shimmer_placeholder.dart';
import 'thumbnail_error_placeholder.dart';

class MultimediaCard extends ConsumerWidget {
  final String? imageUrl;
  final String title;
  final VoidCallback onTap;
  final String heroTag;
  final bool isPortrait;
  final FocusNode? focusNode;

  const MultimediaCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.onTap,
    required this.heroTag,
    this.isPortrait = true,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = context.isDesktop;
    final cardWidth = isDesktop
        ? (isPortrait ? 200.0 : 300.0)
        : (isPortrait ? 130.0 : 200.0);

    final titlePosition = ref.watch(
      generalSettingsProvider.select((s) => s.titlePosition),
    );
    final isInside = titlePosition == 'inside';

    final imageWidget = Hero(
      tag: heroTag,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: imageUrl ?? '',
          fit: BoxFit.cover,
          width: double.infinity,
          placeholder: (context, url) => ShimmerPlaceholder(borderRadius: 12),
          errorWidget: (_, _, _) => ThumbnailErrorPlaceholder(label: title),
        ),
      ),
    );

    final titleTextStyle = TextStyle(
      color: isInside
          ? Colors.white
          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
      fontSize: isDesktop ? 22 : 14,
      fontWeight: FontWeight.w500,
      shadows: isInside
          ? [
              const Shadow(
                color: Colors.black87,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ]
          : null,
    );

    return RepaintBoundary(
      child: CardsWrapper(
        onTap: onTap,
        focusNode: focusNode,
        scaleFactor: 1.05,
        child: SizedBox(
          width: cardWidth,
          child: isInside
              ? _buildInsideMode(imageWidget, titleTextStyle)
              : _buildBelowMode(imageWidget, titleTextStyle),
        ),
      ),
    );
  }

  Widget _buildBelowMode(Widget imageWidget, TextStyle titleTextStyle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: imageWidget),
        const SizedBox(height: 8),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleTextStyle,
        ),
      ],
    );
  }

  Widget _buildInsideMode(Widget imageWidget, TextStyle titleTextStyle) {
    return Stack(
      children: [
        Positioned.fill(child: imageWidget),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
                stops: [0.0, 1.0],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: titleTextStyle,
            ),
          ),
        ),
      ],
    );
  }
}
