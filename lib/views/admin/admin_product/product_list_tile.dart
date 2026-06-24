import 'package:flutter/material.dart';
import '../../../models/product.dart';
import '../../../utils/currency_formatter.dart';
import '../../../utils/responsive.dart';
import '../../../viewmodels/admin_viewmodel.dart';
import '../../../widgets/network_image.dart';
import 'edit_product_dialog.dart';

/// A single row in the admin product list.
class ProductListTile extends StatelessWidget {
  const ProductListTile({
    super.key,
    required this.product,
    required this.viewModel,
  });

  final Product product;
  final AdminViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.only(
        bottom: context.responsive<double>(mobile: 8, tablet: 10, desktop: 12),
      ),
      child: ListTile(
        leading: _ProductImage(imageUrl: product.imageUrl),
        title: Text(
          product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _ProductSubtitle(product: product),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Sửa',
              icon: Icon(Icons.edit, color: scheme.primary),
              onPressed: () =>
                  showEditProductDialog(context, viewModel, product),
            ),
            IconButton(
              tooltip: 'Xoá',
              icon: Icon(Icons.delete, color: scheme.error),
              onPressed: () => _showDeleteConfirm(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa sản phẩm'),
        content: Text('Bạn có chắc muốn xóa "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await viewModel.deleteProduct(product.id);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Xóa sản phẩm thành công')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Lỗi khi xóa sản phẩm: $e'),
                      backgroundColor: scheme.error,
                    ),
                  );
                }
              }
            },
            child: Text('Xóa', style: TextStyle(color: scheme.error)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private sub-widgets
// ---------------------------------------------------------------------------

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AppNetworkImage(
          url: imageUrl,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _ProductSubtitle extends StatelessWidget {
  const _ProductSubtitle({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${formatCurrency(product.price)} • Tồn kho: ${product.stock ?? 0}',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (product.options.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: product.options
                .where((o) => o.name.isNotEmpty)
                .take(4)
                .map(
                  (o) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      o.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}
