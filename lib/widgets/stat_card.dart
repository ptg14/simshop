import 'package:flutter/material.dart';
import '../utils/responsive.dart';

/// A reusable card widget for displaying dashboard statistics.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    super.key,
  });
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.1),
                color.withValues(alpha: 0.05)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(
              context.responsive<double>(mobile: 16, tablet: 18, desktop: 20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(
                    context.responsive<double>(
                        mobile: 8, tablet: 10, desktop: 12),
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: context.responsive<double>(
                        mobile: 24, tablet: 28, desktop: 32),
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
                        color: color,
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
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}
