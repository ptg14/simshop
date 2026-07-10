import 'package:flutter/material.dart';

import '../../utils/responsive.dart';
import 'admin_settings/site_config_section.dart';

/// Admin settings screen.
///
/// Now hosts only the persisted "Thông tin cửa hàng" form. The previous
/// shell sections (Giao diện, Thông báo, Bảo mật & Sao lưu, Về ứng dụng)
/// were removed: they held local-only state and showed fake snackbars —
/// see git history for context.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.all(context.horizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header.
          Text(
            'Cài đặt',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Thông tin cửa hàng hiển thị trên trang chủ và trang chi tiết',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          // Site config form — backed by SiteConfigViewModel.
          const SiteConfigSection(),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
