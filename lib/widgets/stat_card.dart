import 'package:flutter/material.dart';
import '../utils/responsive.dart';

/// M3 color role that drives the container/on-container colors of a [StatCard].
enum CardVariant { primary, secondary, tertiary, error }

/// A reusable card widget for displaying dashboard statistics.
///
/// All colors come from the [ColorScheme] via [variant] — never pass a raw
/// [Color].
class StatCard extends StatelessWidget {
  const StatCard({
    required this.title,
    required this.value,
    required this.icon,
    this.variant = CardVariant.primary,
    super.key,
  });
  final String title;
  final String value;
  final IconData icon;
  final CardVariant variant;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (container, onContainer) = switch (variant) {
      CardVariant.primary => (scheme.primaryContainer, scheme.onPrimaryContainer),
      CardVariant.secondary =>
        (scheme.secondaryContainer, scheme.onSecondaryContainer),
      CardVariant.tertiary =>
        (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      CardVariant.error => (scheme.errorContainer, scheme.onErrorContainer),
    };

    return Card(
      color: container,
      child: Padding(
        padding: EdgeInsets.all(
          context.responsive<double>(mobile: 16, tablet: 18, desktop: 20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: scheme.surface,
              child: Icon(
                icon,
                color: onContainer,
                size: context.responsive<double>(
                    mobile: 20, tablet: 22, desktop: 24),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: context.responsive<double>(
                        mobile: 28, tablet: 32, desktop: 36),
                    fontWeight: FontWeight.bold,
                    color: onContainer,
                  ),
                ),
                SizedBox(
                    height: context.responsive<double>(
                        mobile: 4, tablet: 6, desktop: 8)),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: context.responsive<double>(
                        mobile: 12, tablet: 13, desktop: 14),
                    color: onContainer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
