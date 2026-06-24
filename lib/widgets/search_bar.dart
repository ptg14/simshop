import 'package:flutter/material.dart';
import '../utils/responsive.dart';

/// Material 3 [SearchBar] wrapper for product search.
class ProductSearchBar extends StatefulWidget {
  const ProductSearchBar({
    super.key,
    required this.onSearch,
    this.onClear,
    this.hintText = 'Tìm kiếm sản phẩm...',
  });
  final Function(String) onSearch;
  final Function()? onClear;
  final String hintText;

  @override
  State<ProductSearchBar> createState() => _ProductSearchBarState();
}

class _ProductSearchBarState extends State<ProductSearchBar> {
  late TextEditingController _controller;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.horizontalPadding,
        vertical: 8,
      ),
      child: SearchBar(
        controller: _controller,
        hintText: widget.hintText,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Icon(Icons.search, color: scheme.onSurfaceVariant),
        ),
        trailing: _hasText
            ? [
                IconButton(
                  tooltip: 'Xoá',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _controller.clear();
                    widget.onClear?.call();
                  },
                ),
              ]
            : null,
        onChanged: widget.onSearch,
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        surfaceTintColor: WidgetStatePropertyAll(scheme.surfaceTint),
        elevation: const WidgetStatePropertyAll(1),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        textStyle: WidgetStatePropertyAll(
          TextStyle(color: scheme.onSurface, fontSize: 16),
        ),
      ),
    );
  }
}