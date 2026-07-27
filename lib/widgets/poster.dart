import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/media_item.dart';

/// Poster artwork. With [width] set it renders at fixed 2:3 size (list
/// tiles); with [width] null it expands to fill its parent (grid cells).
class Poster extends StatelessWidget {
  final String? url;
  final double? width;

  const Poster({super.key, required this.url, this.width});

  @override
  Widget build(BuildContext context) {
    final height = width == null ? null : width! * 1.5;
    final placeholder = Container(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.image_outlined,
          color: Theme.of(context).colorScheme.outline),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url!,
              width: width ?? double.infinity,
              height: height ?? double.infinity,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}

/// Detail-sheet header with fanart/backdrop art behind [child], fading
/// into the sheet background so the title stays readable. Falls back to
/// a plain padded header when there is no artwork.
class SheetBackdropHeader extends StatelessWidget {
  final String? backdropUrl;
  final Widget child;

  const SheetBackdropHeader({
    super.key,
    required this.backdropUrl,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: child,
    );
    if (backdropUrl == null) return padded;
    final theme = Theme.of(context);
    final bg = theme.bottomSheetTheme.backgroundColor ??
        theme.colorScheme.surface;
    return Stack(
      children: [
        Positioned.fill(
          child: CachedNetworkImage(
            imageUrl: backdropUrl!,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bg.withValues(alpha: 0.55), bg],
              ),
            ),
          ),
        ),
        padded,
      ],
    );
  }
}

/// Small status badge shown on grid posters and detail sheets.
class StatusIcon extends StatelessWidget {
  final MediaStatus status;
  final double size;

  const StatusIcon({super.key, required this.status, this.size = 16});

  static String label(MediaStatus status) => switch (status) {
        MediaStatus.downloading => 'Downloading',
        MediaStatus.downloaded => 'Downloaded',
        MediaStatus.wanted => 'Wanted',
        MediaStatus.unmonitored => 'Unmonitored',
      };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      MediaStatus.downloading => (Icons.downloading, Colors.lightBlue),
      MediaStatus.downloaded => (Icons.check_circle, Colors.green),
      MediaStatus.wanted => (Icons.schedule, Colors.amber),
      MediaStatus.unmonitored => (
          Icons.visibility_off,
          Theme.of(context).colorScheme.outline
        ),
    };
    return Icon(icon, size: size, color: color);
  }
}
