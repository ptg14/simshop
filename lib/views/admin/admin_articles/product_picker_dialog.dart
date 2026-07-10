import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/product.dart';
import '../../../services/product_service.dart';

// ---------------------------------------------------------------------------
// Product picker dialog
// ---------------------------------------------------------------------------

/// Click-to-pick product dialog backed by [IProductService.searchProducts].
/// Filters out products whose ids are already in [existingIds]. Pops with
/// the picked [Product] (or null if the user cancels).
class ProductPickerDialog extends StatefulWidget {
  const ProductPickerDialog({super.key, required this.existingIds});

  final List<String> existingIds;

  @override
  State<ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<ProductPickerDialog> {
  final TextEditingController _queryCtrl = TextEditingController();
  Timer? _debounce;
  List<Product> _results = const [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    // Run an empty search on open so the dialog isn't blank.
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _search(v));
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _lastQuery = query;
    });
    try {
      final svc = context.read<IProductService>();
      final results = await svc.searchProducts(query);
      if (!mounted || query != _lastQuery) return;
      setState(() {
        _results = results
            .where((p) => !widget.existingIds.contains(p.id))
            .toList(growable: false);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
      title: const Text('Chọn sản phẩm'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _queryCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Tìm kiếm',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onChanged,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? const Center(
                          child: Text('Không tìm thấy sản phẩm'),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, i) {
                            final p = _results[i];
                            return ListTile(
                              leading: p.imageUrl.isEmpty
                                  ? const Icon(Icons.shopping_bag_outlined)
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(
                                        p.imageUrl,
                                        width: 36,
                                        height: 36,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(
                                            Icons.shopping_bag_outlined),
                                      ),
                                    ),
                              title: Text(
                                p.name.isEmpty ? p.id : p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: p.category.isEmpty
                                  ? null
                                  : Text(p.category),
                              onTap: () => Navigator.pop(context, p),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
      ],
    );
}
