import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/store_info.dart';
import '../utils/responsive.dart';
import '../viewmodels/site_config_viewmodel.dart';
import 'admin_banner_trigger.dart';
import 'network_image.dart';
import 'shimmer_placeholder.dart';

/// Reusable footer card displaying the site identity + contact info.
///
/// Always renders the banner slot, even when [StoreInfo] is empty —
/// on a freshly initialized backend the footer shows a banner
/// placeholder whose shape + shimmer **match the skeleton banner at
/// the top of the home page** (same `carouselHeight`, same 16-dp
/// corner radius, same `ShimmerPlaceholder` pulse). That visual
/// parallelism tells the user the page is still loading from end to
/// end, instead of leaving a static "missing image" panel dangling
/// below a pulsing top banner.
///
/// When [StoreInfo] has content, the same card additionally renders:
/// name, description, address, phone, email. Used at the bottom of
/// the home page and product detail page.
///
/// Hidden admin entry-point: the banner is wrapped in
/// [AdminBannerTrigger], which opens the admin auth gate after 7
/// taps within 3 seconds. The gesture is intentionally undocumented
/// — casual users have no way to discover the admin UI. Same
/// pattern as Android's "tap Build Number 7 times to unlock
/// Developer Options". Three copies of the trigger live on the home
/// page (the footer banner, the skeleton banner placeholder, the
/// empty-state banner placeholder) so the admin entry-point is
/// reachable from every state — see [AdminBannerTrigger] for the
/// rationale on the per-instance counter.
class SiteInfoFooter extends StatelessWidget {
  const SiteInfoFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Consumer<SiteConfigViewModel>(
      builder: (context, vm, _) {
        final info = vm.siteInfo;
        // Always render the footer card. On a freshly-initialized DB
        // (info.isEmpty) the card holds only the banner placeholder
        // so the hidden 7-tap admin entry-point stays reachable for
        // first-time setup. Once the admin uploads store info via
        // the dashboard, the same card grows the name + contact
        // sections below.
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
                // Banner slot — always mounted so the 7-tap gesture
                // is reachable regardless of whether a banner URL
                // has been uploaded yet. The AdminBannerTrigger
                // wraps the [ClipRRect] so the entire visible banner
                // is tappable (HitTestBehavior.opaque inside the
                // trigger swallows stray taps so they don't bubble
                // up to the parent card).
                //
                // Shape + animation match the home-page skeleton
                // banner ([HomeSkeleton]): `carouselHeight` (180 /
                // 250 / 350 dp), 16-dp corner radius, and a
                // `ShimmerPlaceholder` pulse when the banner URL is
                // empty. The empty-DB state is permanent until the
                // admin uploads a banner, so a pulsing shimmer here
                // is *correct* visual language: from the user's
                // perspective the whole page IS still settling —
                // top and bottom banners reading the same is what
                // makes the page feel like one loading unit rather
                // than two disconnected cards.
                AdminBannerTrigger(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: context.carouselHeight,
                      width: double.infinity,
                      child: info.bannerUrl.isNotEmpty
                          // Real banner — load via AppNetworkImage so
                          // it picks up the shared disk cache and
                          // error treatment for free.
                          ? AppNetworkImage(
                              url: info.bannerUrl,
                              fit: BoxFit.cover,
                            )
                          // Empty DB — keep the dimmed image icon as
                          // a visual anchor, but wrap it in the
                          // skeleton-style shimmer so the empty
                          // footer banner reads as "still loading"
                          // instead of "missing image".
                          : const _EmptyBannerPlaceholder(),
                    ),
                  ),
                ),
                // Trailing spacer only when there's text below —
                // when the card is banner-only it would just be
                // dead space at the bottom.
                if (!info.isEmpty) ...[
                  const SizedBox(height: 12),
                  // Store name — plain text, no gesture detector. The
                  // hidden admin entry-point lives on the banner
                  // above (7 taps within 3 seconds).
                  Text(
                    info.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
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
                    _ContactLine(
                        icon: Icons.place_outlined, text: info.address),
                  if (info.phone.isNotEmpty)
                    _ContactLine(
                        icon: Icons.phone_outlined, text: info.phone),
                  if (info.email.isNotEmpty)
                    _ContactLine(
                        icon: Icons.email_outlined, text: info.email),
                ],
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

/// Empty-DB banner placeholder. Reuses the skeleton's
/// [ShimmerPlaceholder] machinery so the top + bottom banners pulse
/// in lockstep when the home page first paints. The dimmed
/// `Icons.image_outlined` is kept as a visual anchor — without it a
/// pure shimmer box would be ambiguous (loading? missing?).
///
/// The parent [SiteInfoFooter] already sizes this widget to
/// `carouselHeight` × full width with a 16-dp [ClipRRect]; this
/// widget only fills that box, so its child doesn't need to know
/// the dimensions.
class _EmptyBannerPlaceholder extends StatelessWidget {
  const _EmptyBannerPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ShimmerPlaceholder(
      child: Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.image_outlined,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
          size: 32,
        ),
      ),
    );
  }
}