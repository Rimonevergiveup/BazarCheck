import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Product image with disk caching, a calm placeholder, and a graceful
/// fallback when the URL is missing or broken.
///
/// Replaces bare `Image.network`, which re-downloaded on every rebuild and
/// showed a jarring broken-image icon — very visible with the seeded
/// `example.com` URLs.
class AppImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;

  const AppImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 0,
  });

  @override
  Widget build(BuildContext context) {
    final child = _buildInner(context);
    if (radius <= 0) return child;
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }

  Widget _buildInner(BuildContext context) {
    final u = url?.trim();
    if (u == null || u.isEmpty || !u.startsWith('http')) {
      return _Fallback(width: width, height: height);
    }
    return CachedNetworkImage(
      imageUrl: u,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, _) => _Placeholder(width: width, height: height),
      errorWidget: (_, _, _) => _Fallback(width: width, height: height),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final double? width;
  final double? height;
  const _Placeholder({this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}

class _Fallback extends StatelessWidget {
  final double? width;
  final double? height;
  const _Fallback({this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.shopping_basket_outlined,
        size: (height != null && height! < 64) ? 20 : 32,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}
