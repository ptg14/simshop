import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'shimmer_placeholder.dart';

/// Network image with shimmer placeholder and themed error icon.
///
/// Wraps [CachedNetworkImage] (already in `pubspec.yaml`) so all product,
/// thumbnail and detail images get free disk caching plus a consistent
/// loading + error treatment.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.radius = 0,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        width: width,
        height: height,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, __) => ShimmerBox(width: width, height: height),
        errorWidget: (_, __, ___) => Container(
          width: width,
          height: height,
          color: scheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(
            Icons.image_not_supported_outlined,
            color: scheme.onSurfaceVariant,
            size: 32,
          ),
        ),
      ),
    );
  }
}
