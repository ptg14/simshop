import 'package:flutter/material.dart';
import '../../utils/responsive.dart';

/// Admin settings screen.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  bool _emailNotifications = true;
  bool _pushNotifications = false;
  String _theme = 'light';
  String _language = 'vi';

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
            'Quản lý giao diện, thông báo và tài khoản',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          SettingsSection(
            title: 'Giao diện',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Chủ đề'),
                trailing: DropdownButton<String>(
                  value: _theme,
                  items: const [
                    DropdownMenuItem(value: 'light', child: Text('Sáng')),
                    DropdownMenuItem(value: 'dark', child: Text('Tối')),
                    DropdownMenuItem(value: 'auto', child: Text('Tự động')),
                  ],
                  onChanged: (value) {
                    setState(() => _theme = value ?? 'light');
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ngôn ngữ'),
                trailing: DropdownButton<String>(
                  value: _language,
                  items: const [
                    DropdownMenuItem(value: 'vi', child: Text('Tiếng Việt')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (value) {
                    setState(() => _language = value ?? 'vi');
                  },
                ),
              ),
            ],
          ),

          SettingsSection(
            title: 'Thông báo',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Thông báo email'),
                subtitle: const Text('Nhận thông báo qua email'),
                value: _emailNotifications,
                onChanged: (value) {
                  setState(() => _emailNotifications = value);
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Thông báo push'),
                subtitle: const Text('Nhận thông báo trên trình duyệt'),
                value: _pushNotifications,
                onChanged: (value) {
                  setState(() => _pushNotifications = value);
                },
              ),
            ],
          ),

          SettingsSection(
            title: 'Cài đặt trang web',
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Tên trang web'),
                subtitle: Text('simshop'),
              ),
              const Divider(height: 1),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Email liên hệ'),
                subtitle: Text('contact@simshop.com'),
              ),
              const Divider(height: 1),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Số điện thoại'),
                subtitle: Text('0123456789'),
              ),
            ],
          ),

          SettingsSection(
            title: 'Bảo mật & Sao lưu',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sao lưu dữ liệu'),
                trailing: FilledButton.tonal(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đang sao lưu...')),
                    );
                  },
                  child: const Text('Sao lưu'),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Đổi mật khẩu'),
                trailing: FilledButton.tonal(
                  onPressed: () => _showChangePasswordDialog(context),
                  child: const Text('Đổi'),
                ),
              ),
            ],
          ),

          SettingsSection(
            title: 'Về ứng dụng',
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Phiên bản'),
                trailing: Text('1.0.0'),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Chính sách bảo mật'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {},
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Điều khoản dịch vụ'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {},
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Save button.
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cài đặt đã được lưu')),
                );
              },
              icon: const Icon(Icons.save),
              label: const Text('Lưu cài đặt'),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: AlertDialog(
          title: const Text('Đổi mật khẩu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              TextField(
                decoration: InputDecoration(labelText: 'Mật khẩu cũ'),
                obscureText: true,
              ),
              SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(labelText: 'Mật khẩu mới'),
                obscureText: true,
              ),
              SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(labelText: 'Xác nhận mật khẩu'),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mật khẩu đã được cập nhật')),
                );
              },
              child: const Text('Cập nhật'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A grouped card of settings tiles, with a section header above it.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
