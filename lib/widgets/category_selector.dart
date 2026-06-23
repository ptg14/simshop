import 'package:flutter/material.dart';
import '../utils/responsive.dart';

/// Category selector widget.
class CategorySelector extends StatelessWidget {
  const CategorySelector({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });
  final List<String> categories;
  final String selectedCategory;
  final Function(String) onCategorySelected;

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.symmetric(
          vertical:
              context.responsive<double>(mobile: 12, tablet: 14, desktop: 16),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: context.horizontalPadding),
          child: Row(
            children: categories.map((category) {
              final isSelected = category == selectedCategory;
              return GestureDetector(
                onTap: () => onCategorySelected(category),
                child: Container(
                  margin: EdgeInsets.only(
                    right: context.responsive<double>(
                        mobile: 12, tablet: 14, desktop: 16),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: context.responsive<double>(
                        mobile: 16, tablet: 18, desktop: 20),
                    vertical: context.responsive<double>(
                        mobile: 8, tablet: 10, desktop: 12),
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF1E88E5) : Colors.white,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF1E88E5)
                          : Colors.grey[300]!,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF1E88E5)
                                  .withValues(alpha: 0.3),
                              blurRadius: 4,
                            ),
                          ]
                        : [],
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : Colors.grey[800],
                      fontSize: context.responsive<double>(
                        mobile: 13,
                        tablet: 14,
                        desktop: 15,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );
}
