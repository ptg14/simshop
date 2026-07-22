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
///
/// Layout strategy:
///   • On tablet/desktop there's room for the inline stock stepper
///     + Edit + Delete next to the body — keeps each row compact in
///     the vertical dimension (one logical row per product, easy to
///     scan).
///   • On mobile (<600dp) the same trailing widget group is wider
///     than the leftover content space after the 80dp image +
///     padding. Forcing it inline used to crush the title to
///     "Tai n..." and squeeze the option-chip Wrap down to a single
///     chip per row (with text breaking mid-word, e.g. "Optio / n3").
///     On mobile we drop the actions under the body instead so the
///     title and chips get the full available width and the chips
///     reflow horizontally.
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
    final isMobile = context.isMobile;
    final actions = _buildActions(context, scheme);

    return Card(
      margin: EdgeInsets.only(
        bottom: context.responsive<double>(mobile: 8, tablet: 10, desktop: 12),
      ),
      // Use a Padding+Row layout (instead of ListTile) so we can
      // move the actions row to a second line on mobile while
      // keeping the standard `Card` chrome. ListTile bakes its
      // trailing into the same row as the body, with no built-in
      // way to flow it under on narrow widths.
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProductImage(imageUrl: product.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TitleAndPrice(product: product),
                  if (product.options.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _OptionChips(options: product.options),
                  ],
                  if (isMobile) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actions,
                    ),
                  ],
                ],
              ),
            ),
            if (!isMobile) ...[
              const SizedBox(width: 8),
              actions,
            ],
          ],
        ),
      ),
    );
  }

  /// Inline stock stepper + Edit + Delete. Wrapped in a single
  /// builder so we can render the same widget group inline on
  /// tablet/desktop and under the body on mobile (see
  /// [ProductListTile.build]).
  Widget _buildActions(BuildContext context, ColorScheme scheme) => Row(
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
      );

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

/// First line of the row body: product name on the LEFT (Expanded
/// so a long Vietnamese name ellipsizes instead of overflowing),
/// price + (optional) sale pill on the RIGHT.
///
/// Why split title and price across the row instead of stacking
/// them: on mobile the title can be long ("Tai nghe Bluetooth
/// chống ồn chủ động") and stacking the price below makes the row
/// feel tall. Putting the price to the right of the title keeps
/// the row to one logical line of info, which matches what
/// grocery/retail admin tables do.
///
/// When a discount is active the pill carries the exact promotional
/// numbers; when nothing is on sale the row just shows the base
/// price with no extra chrome.
///
/// Trailing cluster is wrapped in [Flexible] (with `fit: loose`) so
/// on extremely narrow viewports — including the default Flutter
/// test viewport of 800×600 — the pill can shrink and ellipsize
/// the event-name detail instead of overflowing the row. The title
/// still wins the budget via its [Expanded]; if both have to
/// squeeze, the pill's internal `Flexible(detail)` clips first.
class _TitleAndPrice extends StatelessWidget {
  const _TitleAndPrice({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            product.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
          ),
        ),
        const SizedBox(width: 8),
        // Flexible so a long event name in the pill can't push the
        // title off-screen on narrow widths. The pill itself is
        // already soft (its detail text uses Flexible+ellipsis).
        Flexible(
          fit: FlexFit.loose,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatCurrency(product.price),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (_kind(product) != _SaleStateKind.none) ...[
                const SizedBox(width: 6),
                Flexible(child: _SalePill(product: product)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Decide which [Widget] (if any) the right-hand slot should render.
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

/// Option-chip strip. Renders as a [Wrap] so chips reflow
/// horizontally to fit the row width.
///
/// Previous bug: when this lived inside [ListTile.subtitle] it
/// shared horizontal space with the price+title, and on mobile it
/// was crushed to ~80dp wide → chips fell one-per-row and the
/// internal [Text] broke long Vietnamese names mid-word ("Optio / n3").
/// Now that the chip wrap gets the full body width, each chip can
/// sit on a single line in the wrap, eliminating the mid-word
/// breaks.
class _OptionChips extends StatelessWidget {
  const _OptionChips({required this.options});
  final List<Option> options;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: options
          .where((o) => o.name.isNotEmpty)
          .take(4)
          .map(
            (o) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                o.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          )
          .toList(),
    );
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
          ? 'Đang tham gia sự kiện ${product.currentEvent!.name} với giảm giá $tag'
          : 'Giảm giá thủ công $tag',
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
