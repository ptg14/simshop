import 'package:flutter/material.dart';

/// Shape of a [ShimmerBox].
enum ShimmerShape { rectangle, square, circle }

/// A pulsing skeleton placeholder that uses a moving gradient to suggest
/// loading. Implemented with [ShaderMask] over a colored box so it works
/// without any external packages.
class ShimmerPlaceholder extends StatefulWidget {
  const ShimmerPlaceholder({
    super.key,
    required this.child,
    this.shape = ShimmerShape.rectangle,
  });

  /// The widget to overlay the shimmer on. Typically a [ShimmerBox].
  final Widget child;

  /// Reserved for future use. Currently always rendered as a rectangle.
  final ShimmerShape shape;

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    // Pick a highlight color with enough contrast against `base`.
    final highlight = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: 0.06),
      base,
    );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            // Move the highlight across the box from -1.5 to 1.5 of its width.
            final dx = (_controller.value * 3 - 1.5) * rect.width;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(Rect.fromLTWH(dx, 0, rect.width, rect.height));
          },
          child: child,
        ),
      child: widget.child,
    );
  }
}

/// A simple sized, colored box ready to be wrapped in a [ShimmerPlaceholder].
///
/// Use it via `ShimmerBox(width: 80, height: 80)` for image placeholders or
/// `ShimmerBox(height: 16, radius: 8)` for text placeholders.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.shape = ShimmerShape.rectangle,
    this.radius = 12,
  });

  final double? width;
  final double? height;
  final ShimmerShape shape;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.surfaceContainerHighest;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: shape == ShimmerShape.circle
            ? BorderRadius.circular(999)
            : BorderRadius.circular(radius),
        shape: shape == ShimmerShape.circle ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
  }
}
