import 'package:flutter/foundation.dart';

import '../viewmodels/site_config_viewmodel.dart';
import 'document_title.dart';

/// Keeps the browser tab / window title in sync with the admin-saved
/// store name.
///
/// Lives at the [MyApp] level so it survives navigation between home
/// and product detail (otherwise the framework's MaterialApp.title
/// fallback would resurface when the user pushes a new route).
///
/// The previous implementation registered a post-frame callback
/// inside [HomeScreen.build], which had two problems:
///
///   1. [context.read] is a one-shot — it doesn't subscribe to
///      future updates. The callback fires once with whatever
///      [siteInfo] was at the very first build, which is the empty
///      default. The title then either stays as 'simshop' (the
///      fallback) or never updates once the real load resolves.
///   2. Even if it had worked, each navigation push to ProductDetail
///      tore down HomeScreen's post-frame chain.
///
/// Listening to the [ChangeNotifier] here instead means the title
/// updates exactly once per [siteInfo.name] change, regardless of
/// which route is on top.
class BrowserTitleManager {
  BrowserTitleManager({required SiteConfigViewModel siteConfig})
      : _siteConfig = siteConfig {
    _siteConfig.addListener(_onSiteConfigChanged);
    _onSiteConfigChanged();
  }

  final SiteConfigViewModel _siteConfig;

  void _onSiteConfigChanged() {
    final name = _siteConfig.siteInfo.name.trim();
    // Fall back to a generic app name when the backend hasn't
    // returned a name yet, so the tab never stays blank.
    setBrowserDocumentTitle(name.isEmpty ? 'simshop' : name);
  }

  void dispose() {
    _siteConfig.removeListener(_onSiteConfigChanged);
  }
}