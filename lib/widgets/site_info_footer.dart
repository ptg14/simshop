import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/store_info.dart';
import '../utils/responsive.dart';
import '../viewmodels/site_config_viewmodel.dart';
import 'network_image.dart';

/// Reusable footer card displaying the site identity + contact info.
///
/// Renders nothing if [StoreInfo] is empty (i.e. backend unreachable and
/// no defaults). Otherwise shows: logo (optional), name, address, phone,
/// email. Used at the bottom of the home page and product detail page.
class SiteInfoFooter extends StatelessWidget {
  const SiteInfoFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Consumer<SiteConfigViewModel>(
      builder: (context, vm, _) {
        final info = vm.siteInfo;
        if (info.isEmpty) return const SizedBox.shrink();

        return Card(
          margin: EdgeInsets.symmetric(
            horizontal: context.horizontalPadding,
            vertical: 16,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: logo + name.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (info.logoUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AppNetworkImage(
                          url: info.logoUrl,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.storefront,
                            color: scheme.onPrimaryContainer),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        info.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                if (info.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    info.description,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 12),
                if (info.address.isNotEmpty)
                  _ContactLine(icon: Icons.place_outlined, text: info.address),
                if (info.phone.isNotEmpty)
                  _ContactLine(icon: Icons.phone_outlined, text: info.phone),
                if (info.email.isNotEmpty)
                  _ContactLine(icon: Icons.email_outlined, text: info.email),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ContactLine extends StatelessWidget {
  const _ContactLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
