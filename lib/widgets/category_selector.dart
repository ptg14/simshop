import 'package:flutter/material.dart';

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
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: categories.map((category) {
            final isSelected = category == selectedCategory;
            return GestureDetector(
              onTap: () => onCategorySelected(category),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            color: const Color(0xFF1E88E5).withValues(alpha: 0.3),
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
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
}
