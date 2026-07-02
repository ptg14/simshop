import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/store_info.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../viewmodels/site_config_viewmodel.dart';
import '../views/admin/admin_auth_gate.dart';
import 'network_image.dart';

/// Reusable footer card displaying the site identity + contact info.
///
/// Renders nothing if [StoreInfo] is empty (i.e. backend unreachable and
/// no defaults). Otherwise shows: banner (optional), name, description,
/// address, phone, email. Used at the bottom of the home page and
/// product detail page.
///
/// Hidden admin entry-point: tapping the store banner 7 times in a row
/// (within 3 seconds of the first tap) opens [AdminAuthGate]. The
/// gesture is intentionally undocumented — casual users have no way
/// to discover the admin UI. Anyone who already knows the handshake
/// (a developer who set up the secret key, the store owner) will
/// remember it. Same pattern as Android's "tap Build Number 7 times
/// to unlock Developer Options".
class SiteInfoFooter extends StatefulWidget {
  const SiteInfoFooter({super.key});

  @override
  State<SiteInfoFooter> createState() => _SiteInfoFooterState();
}

class _SiteInfoFooterState extends State<SiteInfoFooter> {
  /// Tap counter — how many taps so far inside the active window.
  /// Reset when the window closes or the count hits [_requiredTaps].
  int _taps = 0;
  /// When the current window started (null = no active window).
  DateTime? _windowStart;

  /// Number of taps required to open the auth gate. Matches the
  /// Android "Developer Options" idiom so the gesture feels familiar
  /// to anyone who's worked on Android.
  static const int _requiredTaps = 7;

  /// Maximum gap between the first tap and the last one. Past this
  /// the counter resets so an accidental stray tap doesn't accumulate
  /// over days. Generous (3s) because the target is a banner (large
  /// hit zone) and ordinary tap cadence on a phone is roughly 1 tap
  /// per 200-300ms — 7 taps fits comfortably inside 3 seconds.
  static const Duration _windowDuration = Duration(seconds: 3);

  void _onBannerTap() {
    final now = DateTime.now();
    // Window expired (or never started) → start a new one.
    if (_windowStart == null ||
        now.difference(_windowStart!) > _windowDuration) {
      _taps = 1;
      _windowStart = now;
    } else {
      _taps += 1;
    }

    final remaining = _requiredTaps - _taps;
    if (remaining <= 0) {
      _taps = 0;
      _windowStart = null;
      // Push the auth gate. We don't await — the user is already
      // authenticated via the gate flow which has its own state.
      Navigator.of(context).push(
        fadeSlideRoute(const AdminAuthGate()),
      );
      return;
    }

    // Intentionally no feedback between taps. A counter SnackBar
    // would make the hidden gesture discoverable (random taps would
    // reveal "you're 4/7 in"), defeating the point of the
    // undocumented entry-point. The admin already knows the
    // handshake; everyone else shouldn't see anything happening.
  }

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
                // Banner — horizontal header image. When set, this
                // sits at the very top of the card and is the hit
                // target for the hidden admin entry. The
                // [GestureDetector] wraps the [ClipRRect] so the
                // entire visible banner is tappable; behavior is
                // `opaque` to swallow taps so they don't bubble up
                // to the parent card and look like a "broken" tap
                // target.
                if (info.bannerUrl.isNotEmpty) ...[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onBannerTap,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 3,
                        child: AppNetworkImage(
                          url: info.bannerUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Store name — plain text, no gesture detector. The
                // hidden admin entry-point lives on the banner above
                // (7 taps within 3 seconds).
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