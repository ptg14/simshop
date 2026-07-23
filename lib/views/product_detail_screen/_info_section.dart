import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/product.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/responsive.dart';
import '../../viewmodels/site_config_viewmodel.dart';
import '../product_detail_screen.dart' show resolveStoreMapUrl;

/// Right column (or below-gallery section on mobile) of the
/// product-detail screen. Extracted from the inline `Column` so
/// the 2-column layout on tablet/desktop can mount it as a
/// sibling of [GallerySection].
class InfoSection extends StatelessWidget {
  const InfoSection({
    super.key,
    required this.product,
    required this.selectedOptionId,
    required this.onSelectOption,
    required this.scheme,
  });

  final Product product;
  final String? selectedOptionId;
  final ValueChanged<String?> onSelectOption;
  final ColorScheme scheme;

  Future<void> _openMap(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.horizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!context.isMobile && product.isOnSale)
            _DiscountRibbon(product: product, scheme: scheme),

          if (product.categories.any((c) => c.trim().isNotEmpty)) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: product.categories
                  .where((c) => c.trim().isNotEmpty)
                  .map((cat) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w500,
                            fontSize: context.responsive<double>(
                              mobile: 12,
                              tablet: 13,
                              desktop: 14,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            SizedBox(
              height: context.responsive<double>(
                mobile: 12,
                tablet: 16,
                desktop: 20,
              ),
            ),
          ],

          if (product.options.isNotEmpty) ...[
            Text(
              'Tuỳ chọn',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: context.responsive<double>(
                  mobile: 14,
                  tablet: 15,
                  desktop: 16,
                ),
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Mặc định'),
                  selected: selectedOptionId == null,
                  onSelected: (_) => onSelectOption(null),
                ),
                for (final o in product.options)
                  ChoiceChip(
                    label: Text(o.name),
                    selected: selectedOptionId == o.id,
                    onSelected: (_) => onSelectOption(o.id),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          Text(
            product.name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: context.responsive<double>(
                mobile: 20,
                tablet: 24,
                desktop: 28,
              ),
              color: scheme.onSurface,
              height: 1.3,
            ),
          ),
          SizedBox(
            height: context.responsive<double>(
              mobile: 12,
              tablet: 16,
              desktop: 20,
            ),
          ),
          _PriceRow(product: product, scheme: scheme),
          SizedBox(
            height: context.responsive<double>(
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          _StockCard(product: product, scheme: scheme),
          SizedBox(
            height: context.responsive<double>(
              mobile: 24,
              tablet: 28,
              desktop: 32,
            ),
          ),
          Text(
            'Mô tả sản phẩm',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: context.responsive<double>(
                mobile: 16,
                tablet: 18,
                desktop: 20,
              ),
              color: scheme.onSurface,
            ),
          ),
          SizedBox(
            height: context.responsive<double>(
              mobile: 8,
              tablet: 10,
              desktop: 12,
            ),
          ),
          MarkdownBody(
            data: product.description.isEmpty
                ? '_(Sản phẩm chưa có mô tả)_'
                : product.description,
            selectable: true,
            styleSheet:
                MarkdownStyleSheet.fromTheme(Theme.of(context)),
          ),
          SizedBox(
            height: context.responsive<double>(
              mobile: 24,
              tablet: 28,
              desktop: 32,
            ),
          ),
          if (product.specs.isNotEmpty) ...[
            Text(
              'Thông số kỹ thuật',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: context.responsive<double>(
                  mobile: 16,
                  tablet: 18,
                  desktop: 20,
                ),
                color: scheme.onSurface,
              ),
            ),
            SizedBox(
              height: context.responsive<double>(
                mobile: 12,
                tablet: 14,
                desktop: 16,
              ),
            ),
            ...product.specs.map((spec) => Padding(
                  padding: EdgeInsets.only(
                    bottom: context.responsive<double>(
                      mobile: 8,
                      tablet: 10,
                      desktop: 12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: scheme.primary,
                        size: context.responsive<double>(
                          mobile: 20,
                          tablet: 22,
                          desktop: 24,
                        ),
                      ),
                      SizedBox(
                        width: context.responsive<double>(
                          mobile: 12,
                          tablet: 14,
                          desktop: 16,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          spec,
                          style: TextStyle(
                            fontSize: context.responsive<double>(
                              mobile: 14,
                              tablet: 15,
                              desktop: 16,
                            ),
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
            SizedBox(
              height: context.responsive<double>(
                mobile: 24,
                tablet: 28,
                desktop: 32,
              ),
            ),
          ],
          Consumer<SiteConfigViewModel>(
            builder: (context, vm, _) {
              final info = vm.siteInfo;
              final url = resolveStoreMapUrl(info);
              if (url.isEmpty) return const SizedBox.shrink();
              final addressLine = info.address.isNotEmpty
                  ? info.address
                  : 'cửa hàng';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mua trực tiếp tại:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: context.responsive<double>(
                        mobile: 14,
                        tablet: 15,
                        desktop: 16,
                      ),
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    key: const Key('buy-at-store-cta'),
                    width: double.infinity,
                    height: context.responsive<double>(
                      mobile: 56,
                      tablet: 52,
                      desktop: 48,
                    ),
                    child: FilledButton.icon(
                      onPressed: () => _openMap(context, url),
                      icon: const Icon(Icons.place_outlined),
                      label: Text(addressLine),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _DiscountRibbon extends StatelessWidget {
  const _DiscountRibbon({required this.product, required this.scheme});
  final Product product;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          product.currentEvent != null
              ? 'GIÁ SỰ KIỆN: ${product.currentEvent!.formatDiscount()}'
                  '${product.currentEvent!.name.isEmpty ? '' : ' · ${product.currentEvent!.name}'}'
              : 'GIÁ CŨ: ${formatCurrency(product.originalPrice ?? 0)}',
          style: TextStyle(
            color: scheme.onError,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.product, required this.scheme});
  final Product product;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          formatCurrency(product.effectivePayPrice),
          style: TextStyle(
            color: scheme.error,
            fontWeight: FontWeight.bold,
            fontSize: context.responsive<double>(
              mobile: 24,
              tablet: 28,
              desktop: 32,
            ),
          ),
        ),
        if (product.isOnSale) ...[
          SizedBox(
            width: context.responsive<double>(
              mobile: 12,
              tablet: 16,
              desktop: 20,
            ),
          ),
          Flexible(
            child: Text(
              formatCurrency(product.price),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
                fontSize: context.responsive<double>(
                  mobile: 16,
                  tablet: 18,
                  desktop: 20,
                ),
              ),
            ),
          ),
          SizedBox(
            width: context.responsive<double>(
              mobile: 12,
              tablet: 16,
              desktop: 20,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.error,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '-${product.discountPercentage}%',
              style: TextStyle(
                color: scheme.onError,
                fontWeight: FontWeight.bold,
                fontSize: context.responsive<double>(
                  mobile: 12,
                  tablet: 13,
                  desktop: 14,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.product, required this.scheme});
  final Product product;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.responsive<double>(
        mobile: 12,
        tablet: 14,
        desktop: 16,
      )),
      decoration: BoxDecoration(
        color: product.isOutOfStock
            ? scheme.errorContainer
            : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            product.isOutOfStock
                ? Icons.do_disturb_alt_outlined
                : Icons.inventory_2_outlined,
            color: product.isOutOfStock
                ? scheme.onErrorContainer
                : scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              () {
                if (product.isOutOfStock) return 'Hết hàng';
                if (product.stock == null) {
                  return 'Số lượng không xác định';
                }
                return 'Còn ${product.stock} sản phẩm';
              }(),
              style: TextStyle(
                color: product.isOutOfStock
                    ? scheme.onErrorContainer
                    : scheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: context.responsive<double>(
                  mobile: 14,
                  tablet: 15,
                  desktop: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
