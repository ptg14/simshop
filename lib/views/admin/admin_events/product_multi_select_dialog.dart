import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/product.dart';
import '../../../services/product_service.dart';

// ---------------------------------------------------------------------------
// Multi-select product picker for the event dialog. Pops with the
// set of selected IDs (or null on cancel).
//
// Modeled after `ProductPickerDialog` in admin_articles.dart but
// keeps an internal selection set so the user can toggle several
// items and commit them in one action via the bottom "Xong" button.
// ---------------------------------------------------------------------------

class ProductMultiSelectDialog extends StatefulWidget {
  const ProductMultiSelectDialog({super.key, required this.existingIds});

  final List<String> existingIds;

  @override
  State<ProductMultiSelectDialog> createState() =>
      _ProductMultiSelectDialogState();
}

class _ProductMultiSelectDialogState
    extends State<ProductMultiSelectDialog> {
  final TextEditingController _queryCtrl = TextEditingController();
  final Set<String> _selected = <String>{};
  List<Product> _results = const [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.existingIds);
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(''));
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    // Simple debounce via Future.delayed — keeps a stale frame from
    // overwriting a newer one.
    final myQuery = v;
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted || myQuery != _lastQuery && _queryCtrl.text != myQuery) {
        return;
      }
      _search(myQuery);
    });
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
        _results = results;
      });
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          'Chọn sản phẩm (${_selected.length} đã chọn)',
        ),
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
                        ? const Center(child: Text('Không tìm thấy sản phẩm'))
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final p = _results[i];
                              final selected = _selected.contains(p.id);
                              return CheckboxListTile(
                                value: selected,
                                onChanged: (v) {
                                  setState(() {
                                    if (v ?? false) {
                                      _selected.add(p.id);
                                    } else {
                                      _selected.remove(p.id);
                                    }
                                  });
                                },
                                title: Text(
                                  p.name.isEmpty ? p.id : p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: p.category.isEmpty
                                    ? null
                                    : Text(p.category),
                                secondary: p.imageUrl.isEmpty
                                    ? const Icon(Icons.shopping_bag_outlined)
                                    : ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        child: Image.network(
                                          p.imageUrl,
                                          width: 36,
                                          height: 36,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                                  Icons.shopping_bag_outlined),
                                        ),
                                      ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
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
          FilledButton(
            onPressed: () => Navigator.pop(context, _selected),
            child: const Text('Xong'),
          ),
        ],
      );
}
