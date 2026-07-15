import 'package:flutter/material.dart';
import '../../../models/product.dart';
import '../../../utils/currency_formatter.dart';
import '../../../utils/responsive.dart';
import '../../../viewmodels/admin_viewmodel.dart';
import '../../../widgets/network_image.dart';
import 'edit_product_dialog.dart';

/// What we render in the row's "discount state" slot. The slot used
/// to carry stock ("Tồn kho: N") but the inline stock stepper now
/// owns that information; admins want to see at-a-glance which
/// products are *currently discounted* and by how much — that is
/// the most useful signal for picking which rows to inspect first.
enum _SaleStateKind {
  /// Product is part of an active event (server-decorated
  /// `current_event`). The most actionable state — name + discount
  /// text come from the Event itself.
  event,

  /// No active event but the row carries a manual
  /// `originalPrice > price`. Legacy "Giảm giá" flag the admin set
  /// from the edit dialog before the events system existed.
  manual,

  /// No discount. Renders nothing in the pill slot — the row just
  /// shows the base price.
  none,
}

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
            // Quick +/- stock stepper sits to the LEFT of Edit so
            // admins can nudge inventory without opening the full
            // product-edit dialog. The whole widget is rebuilt
            // whenever the VM notifies (because we read
            // `product.stock` from the row's copy); the optimistic
            // update path in [AdminViewModel.quickAdjustStock]
            // handles the round-trip / revert.
            _StockStepper(
              product: product,
              viewModel: viewModel,
            ),
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

  /// Render the subtitle: price + (optionally) a discount pill
  /// describing *why* the price differs from the base.
  ///
  /// The pill slot used to carry "Tồn kho: N" but the inline
  /// stock stepper in the trailing row already owns stock info;
  /// sale state is the more actionable signal for admins — the
  /// question they ask most when scanning the list is "which of
  /// these is currently on promotion".
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Always render the base price. When a discount is
            // active the pill on the right carries the exact
            // promotional numbers; when nothing is on sale the
            // row just shows the base price with no extra chrome.
            Text(
              formatCurrency(product.price),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (_kind(product) != _SaleStateKind.none) ...[
              const SizedBox(width: 8),
              Flexible(child: _SalePill(product: product)),
            ],
          ],
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

  /// Decide which [Widget] (if any) the subtitle's right-hand slot
  /// should render.
  ///
  /// Event wins over manual: a product can be both (manual discount
  /// + active event) but the event is the live, server-validated
  /// state, so we surface that and let the manual slot stay hidden
  /// — admins don't need two stacked discount ribbons on one row.
  _SaleStateKind _kind(Product p) {
    if (p.currentEvent != null) return _SaleStateKind.event;
    if (p.originalPrice != null && p.originalPrice! > p.price) {
      return _SaleStateKind.manual;
    }
    return _SaleStateKind.none;
  }
}

/// Small status pill rendered next to the price in each row's
/// subtitle. Two visual flavours:
///   • [_SaleStateKind.event] — pink/error-tinted, shows the event
///     discount text ("-20%") + the event name, since admins
///     typically want to know which sale this product is part of
///     (helps when cross-referencing with the Events tab).
///   • [_SaleStateKind.manual] — softer secondaryContainer tint,
///     shows just the discount percentage. Used for legacy
///     `originalPrice > price` rows created before the events
///     system was added.
class _SalePill extends StatelessWidget {
  const _SalePill({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = product.currentEvent != null
        ? _SaleStateKind.event
        : _SaleStateKind.manual;

    // Format the leading tag and the trailing detail differently
    // per kind so the two visual states stay distinguishable at a
    // glance.
    final String tag;
    final String detail;
    if (kind == _SaleStateKind.event) {
      final ev = product.currentEvent!;
      tag = ev.formatDiscount(); // "-20%" or "-50000đ"
      // Event name goes in the detail slot. The server's
      // effective_price is the authoritative customer-facing
      // price; render it next to the discount so admins can
      // spot pricing mistakes at a glance.
      detail = '${ev.name}  •  ${formatCurrency(product.effectivePayPrice)}';
    } else {
      tag = '-${product.discountPercentage}%';
      detail = formatCurrency(product.effectivePayPrice);
    }

    final Color bg;
    final Color fg;
    if (kind == _SaleStateKind.event) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    } else {
      bg = scheme.secondaryContainer;
      fg = scheme.onSecondaryContainer;
    }

    return Semantics(
      label: kind == _SaleStateKind.event
          ? 'Đang tham gia sự kiện ${product.currentEvent!.name} với giảm giá ${tag}'
          : 'Giảm giá thủ công ${tag}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tag,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
            const SizedBox(width: 6),
            // Flexible so a long event name doesn't overflow the
            // row; the price column will ellipsize the name
            // gracefully while keeping the discount tag visible.
            Flexible(
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: fg.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline `−` count `+` stepper that nudges the row's product stock
/// by ±1 without opening the full edit dialog.
///
/// Behaviour:
///   • Each tap fires `AdminViewModel.quickAdjustStock` (which
///     optimistically updates the local list and PUTs the full
///     product to the backend).
///   • The two buttons are disabled while a step is in flight, so
///     rapid double-taps can't queue conflicting requests.
///   • The middle label renders the row's current stock. `null` is
///     shown as `?` rather than `0` so the user notices the value is
///     unknown rather than mistakenly thinking the SKU is depleted.
class _StockStepper extends StatefulWidget {
  const _StockStepper({
    required this.product,
    required this.viewModel,
  });

  final Product product;
  final AdminViewModel viewModel;

  @override
  State<_StockStepper> createState() => _StockStepperState();
}

class _StockStepperState extends State<_StockStepper> {
  /// True while a [AdminViewModel.quickAdjustStock] call is in
  /// flight. Reset on every VM notify (which includes the post-call
  /// rebuild) OR on a fresh rebuild of the row with a different
  /// product — see [didUpdateWidget].
  bool _busy = false;

  @override
  void didUpdateWidget(covariant _StockStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      _busy = false;
    }
  }

  Future<void> _bump(int delta) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.viewModel.quickAdjustStock(widget.product.id, delta);
    } finally {
      // Note: the VM's notifyListeners drives the parent Consumer
      // rebuild which in turn re-creates this widget's State on
      // identity change. We still need to flip the local flag back
      // so a follow-up tap on the *same* row works.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stock = widget.product.stock;
    final stockLabel = stock == null ? '?' : '$stock';
    final atFloor = stock == 0;

    return Container(
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Giảm 1',
            icon: const Icon(Icons.remove, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: (_busy || atFloor) ? null : () => _bump(-1),
          ),
          // Render the stock count with a fixed minimum width so
          // single-digit values don't cause the row width to
          // twitch every time the user increments.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 22),
            child: Text(
              stockLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: atFloor ? scheme.error : scheme.onSurface,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Tăng 1',
            icon: const Icon(Icons.add, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : () => _bump(1),
          ),
        ],
      ),
    );
  }
}
