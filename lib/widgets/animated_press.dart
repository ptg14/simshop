import 'package:flutter/material.dart';

/// Wraps a child in a subtle scale animation + M3 ink ripple while pressed.
///
/// Built on [Material] + [InkWell] so it inherits:
///   • keyboard focus + activation (Enter/Space)
///   • screen-reader semantics (button role)
///   • M3 ripple feedback
///
/// Combine with [Card] (which already wraps in Material) — in that case the
/// outer [Material] here is transparent so the ink still shows through.
class AnimatedPress extends StatefulWidget {
  const AnimatedPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.duration = const Duration(milliseconds: 120),
    this.reverseDuration = const Duration(milliseconds: 180),
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final Duration duration;
  final Duration reverseDuration;

  /// Optional spoken label for screen readers. Falls back to the child's
  /// intrinsic semantics when null.
  final String? semanticLabel;

  @override
  State<AnimatedPress> createState() => _AnimatedPressState();
}

class _AnimatedPressState extends State<AnimatedPress> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final core = AnimatedScale(
      scale: _pressed ? widget.scale : 1.0,
      duration: widget.duration,
      curve: Curves.easeOut,
      child: widget.child,
    );

    // Wrap in Semantics + InkWell so the gesture is keyboard- and
    // screen-reader-accessible. The transparent Material ensures the
    // ripple is visible even when the child is a Card.
    return Semantics(
      button: true,
      enabled: widget.onTap != null || widget.onLongPress != null,
      label: widget.semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: core,
        ),
      ),
    );
  }
}
