import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/store_info.dart';
import '../../services/product_service.dart';
import '../../utils/responsive.dart';
import '../../viewmodels/site_config_viewmodel.dart';

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
                    DropdownMenuItem(
                        value: 'auto', child: Text('Tự động')),
                  ],
                  onChanged: (v) =>
                      setState(() => _theme = v ?? 'light'),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ngôn ngữ'),
                trailing: DropdownButton<String>(
                  value: _language,
                  items: const [
                    DropdownMenuItem(
                        value: 'vi', child: Text('Tiếng Việt')),
                    DropdownMenuItem(
                        value: 'en', child: Text('English')),
                  ],
                  onChanged: (v) =>
                      setState(() => _language = v ?? 'vi'),
                ),
              ),
            ],
          ),

          SettingsSection(
            title: 'Thông báo',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Email thông báo'),
                value: _emailNotifications,
                onChanged: (v) =>
                    setState(() => _emailNotifications = v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Thông báo đẩy'),
                value: _pushNotifications,
                onChanged: (v) =>
                    setState(() => _pushNotifications = v),
              ),
            ],
          ),

          // Site config form — backed by SiteConfigViewModel.
          const _SiteConfigSection(),

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

          // Local-only preferences save (theme/lang/notify toggles).
          // Site config is saved per-section by its own button above.
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Tùy chọn giao diện/ngôn ngữ/thông báo đã được lưu cục bộ')),
                );
              },
              icon: const Icon(Icons.save),
              label: const Text('Lưu tùy chọn'),
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
                  const SnackBar(
                      content: Text('Mật khẩu đã được cập nhật')),
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

/// Editable site identity / branding form.
///
/// Reads the singleton [StoreInfo] from [SiteConfigViewModel], pre-fills
/// the inputs on first load, and writes back to the backend on save.
/// The form is self-contained — local controllers and the upload
/// pipeline are managed inside this widget so the surrounding screen
/// doesn't have to know about logo uploads or the network.
class _SiteConfigSection extends StatefulWidget {
  const _SiteConfigSection();

  @override
  State<_SiteConfigSection> createState() => _SiteConfigSectionState();
}

class _SiteConfigSectionState extends State<_SiteConfigSection> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Logo upload state.
  String _logoUrl = '';
  XFile? _logoFile;
  Uint8List? _logoFileBytes;
  bool _uploadingLogo = false;

  bool _hydrated = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Hydrate controllers from the viewmodel on the next frame so we
    // pick up the initial load that ran in main.dart.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hydrated) return;
      final vm = context.read<SiteConfigViewModel>();
      _hydrateFrom(vm.siteInfo);
      _hydrated = true;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _hydrateFrom(StoreInfo info) {
    _nameCtrl.text = info.name;
    _descCtrl.text = info.description;
    _phoneCtrl.text = info.phone;
    _emailCtrl.text = info.email;
    _addressCtrl.text = info.address;
    _logoUrl = info.logoUrl;
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _logoFile = picked;
      if (kIsWeb) {
        _logoFileBytes = null; // resolved during upload
      } else {
        _logoFileBytes = null;
      }
    });
    if (kIsWeb) {
      _logoFileBytes = await picked.readAsBytes();
    }
    if (mounted) setState(() {});
  }

  Future<String?> _uploadLogo() async {
    if (_logoFile == null) return _logoUrl;
    setState(() => _uploadingLogo = true);
    try {
      final service = context.read<IProductService>();
      if (kIsWeb) {
        final bytes = _logoFileBytes ?? await _logoFile!.readAsBytes();
        return await service.uploadImage(
          bytes,
          productName: 'site-logo',
        );
      }
      return await service.uploadImage(
        File(_logoFile!.path),
        productName: 'site-logo',
      );
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên cửa hàng')),
      );
      return;
    }
    setState(() => _saving = true);
    // Capture the viewmodel and messenger before the first await so the
    // analyzer doesn't flag BuildContext use across an async gap.
    final vm = context.read<SiteConfigViewModel>();
    final messenger = ScaffoldMessenger.of(context);

    // Upload new logo first (if any), then save the row.
    String? logoUrl = _logoUrl;
    if (_logoFile != null) {
      logoUrl = await _uploadLogo();
      if (logoUrl == null) {
        if (mounted) {
          setState(() => _saving = false);
          messenger.showSnackBar(
            const SnackBar(
                content: Text('Tải logo thất bại, vui lòng thử lại')),
          );
        }
        return;
      }
    }

    final info = StoreInfo(
      name: name,
      description: _descCtrl.text.trim(),
      logoUrl: logoUrl,
      phone: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
    );

    final ok = await vm.update(info);
    if (!mounted) return;
    setState(() => _saving = false);

    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Đã lưu thông tin cửa hàng'
            : (vm.error ?? 'Lưu thất bại')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Consumer<SiteConfigViewModel>(
      builder: (context, vm, _) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thông tin cửa hàng',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo row: preview + pick button.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LogoPreview(
                          url: _logoUrl,
                          file: _logoFile,
                          bytes: _logoFileBytes,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Logo cửa hàng',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(
                                'PNG / JPG. Hiển thị trên trang chủ và trang chi tiết sản phẩm.',
                                style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.tonalIcon(
                                onPressed: _uploadingLogo ? null : _pickLogo,
                                icon: const Icon(Icons.image_outlined),
                                label: Text(_logoUrl.isEmpty && _logoFile == null
                                    ? 'Chọn logo'
                                    : 'Đổi logo'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),

                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên cửa hàng *',
                      ),
                      textInputAction: TextInputAction.next,
                      maxLength: 80,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mô tả',
                      ),
                      maxLines: 3,
                      maxLength: 500,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      keyboardType: TextInputType.phone,
                      maxLength: 50,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Email liên hệ',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      maxLength: 200,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addressCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ',
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                      maxLines: 2,
                      maxLength: 300,
                    ),

                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Lưu thông tin'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo preview tile. Shows the uploaded image if there is one (either
/// from a URL the backend already returned, or a freshly-picked local
/// file/bytes). Falls back to a placeholder icon.
class _LogoPreview extends StatelessWidget {
  const _LogoPreview({this.url, this.file, this.bytes});
  final String? url;
  final XFile? file;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = (url != null && url!.isNotEmpty) || file != null;
    Widget child;
    if (file != null) {
      if (kIsWeb && bytes != null) {
        child = Image.memory(bytes!, fit: BoxFit.cover);
      } else {
        child = Image.file(File(file!.path), fit: BoxFit.cover);
      }
    } else if (url != null && url!.isNotEmpty) {
      child = Image.network(url!, fit: BoxFit.cover);
    } else {
      child = Icon(Icons.storefront, size: 32, color: scheme.onSurfaceVariant);
    }
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: hasImage ? null : Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: child,
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
