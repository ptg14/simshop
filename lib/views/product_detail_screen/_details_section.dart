import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/product.dart';
import '../../utils/responsive.dart';
import '../../viewmodels/site_config_viewmodel.dart';
import '../product_detail_screen.dart' show resolveStoreMapUrl;

/// Description + specs + Buy CTA block — the bottom half of the
/// product-detail info column.
///
/// On mobile / iPad portrait the screen mounts this widget
/// implicitly via `InfoSection(compact: false)`. On PC / laptop
/// (≥1024 dp) the screen mounts it DIRECTLY below the gallery
/// row so the description and the Buy CTA sit at full content
/// width under the gallery, not squeezed inside the right column.
///
/// Stateless. Reads site config via [Consumer] for the Buy CTA
/// URL — same pattern as the previous inline `_openMap`.
class DetailsSection extends StatelessWidget {
  const DetailsSection({
    super.key,
    required this.product,
    required this.scheme,
  });

  final Product product;
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