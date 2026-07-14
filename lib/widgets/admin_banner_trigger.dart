import 'package:flutter/material.dart';
import '../utils/page_transitions.dart';
import '../views/admin/admin_auth_gate.dart';

/// Hidden admin entry-point: wraps [child] in a `GestureDetector` that
/// counts taps and, after [_requiredTaps] taps inside [_windowDuration],
/// pushes [AdminAuthGate] on the nearest `Navigator`.
///
/// The gesture is intentionally undocumented — casual users have no way
/// to discover the admin UI. Anyone who already knows the handshake
/// (a developer who set up the secret key, the store owner) will
/// remember it. Same pattern as Android's "tap Build Number 7 times
/// to unlock Developer Options".
///
/// Used in three places so the admin entry-point stays reachable on
/// every home-page state:
///   * `SiteInfoFooter` — wraps the live + placeholder banner card.
///   * `HomeSkeleton`   — wraps the banner placeholder painted during
///                        the initial network round-trip on a fresh DB.
///   * `_buildEmpty`    — wraps the banner placeholder shown when the
///                        products endpoint returned `[]`.
///
/// Each instance owns its own counter — that's deliberate. Three
/// independent `State`s means three independent counters, so casual
/// taps on the live banner don't "consume" taps that were meant for
/// the skeleton placeholder. The tap count required is the same
/// (7 taps within 3 s) regardless of which instance is counting, so
/// an admin who knows the handshake can use any of the three.
class AdminBannerTrigger extends StatefulWidget {
  const AdminBannerTrigger({super.key, required this.child});

  final Widget child;

  @override
  State<AdminBannerTrigger> createState() => _AdminBannerTriggerState();
}

class _AdminBannerTriggerState extends State<AdminBannerTrigger> {
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

  void _onTap() {
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
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: widget.child,
      );
}