import 'package:flutter/material.dart';
import '../utils/responsive.dart';

/// Promotional banner widget.
class PromoBanner extends StatelessWidget {
  const PromoBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actionText,
    required this.onTap,
    this.backgroundColor = const Color(0xFF1E88E5),
    this.textColor = Colors.white,
    this.imageUrl,
  });
  final String title;
  final String subtitle;
  final String actionText;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color textColor;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.symmetric(
          horizontal: context.horizontalPadding,
          vertical:
              context.responsive<double>(mobile: 12, tablet: 14, desktop: 16),
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              backgroundColor,
              backgroundColor.withValues(alpha: 0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: backgroundColor.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              /// Background image if provided
              if (imageUrl != null)
                Positioned.fill(
                  child: Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.expand(),
                  ),
                ),

              /// Content
              Padding(
                padding: EdgeInsets.all(
                  context.responsive<double>(
                      mobile: 20, tablet: 24, desktop: 28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// Title
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: context.responsive<double>(
                            mobile: 24, tablet: 28, desktop: 32),
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        height: 1.2,
                      ),
                    ),

                    SizedBox(
                        height: context.responsive<double>(
                            mobile: 8, tablet: 10, desktop: 12)),

                    /// Subtitle
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: context.responsive<double>(
                            mobile: 14, tablet: 15, desktop: 16),
                        color: textColor.withValues(alpha: 0.9),
                        height: 1.4,
                      ),
                    ),

                    SizedBox(
                        height: context.responsive<double>(
                            mobile: 16, tablet: 18, desktop: 20)),

                    /// Action button
                    ElevatedButton(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: EdgeInsets.symmetric(
                          horizontal: context.responsive<double>(
                              mobile: 24, tablet: 28, desktop: 32),
                          vertical: context.responsive<double>(
                              mobile: 12, tablet: 14, desktop: 16),
                        ),
                      ),
                      child: Text(
                        actionText,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: context.responsive<double>(
                              mobile: 14, tablet: 15, desktop: 16),
                        ),
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
