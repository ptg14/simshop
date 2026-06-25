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
          const _SiteConfigSection(),

          const SizedBox(height: 16),
        ],
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
  final _googleMapsUrlCtrl = TextEditingController();

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
    _googleMapsUrlCtrl.dispose();
    super.dispose();
  }

  void _hydrateFrom(StoreInfo info) {
    _nameCtrl.text = info.name;
    _descCtrl.text = info.description;
    _phoneCtrl.text = info.phone;
    _emailCtrl.text = info.email;
    _addressCtrl.text = info.address;
    _googleMapsUrlCtrl.text = info.googleMapsUrl;
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
      googleMapsUrl: _googleMapsUrlCtrl.text.trim(),
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
                    const SizedBox(height: 12),
                    // Google Maps URL — when set, takes precedence over
                    // the address above as the destination the product
                    // detail CTA opens. Leave empty to fall back to
                    // the address (client builds a directions URL).
                    TextField(
                      controller: _googleMapsUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Google Maps URL',
                        helperText:
                            'Khi khách ấn nút mua tại cửa hàng sẽ mở URL này. Để trống nếu muốn dùng địa chỉ ở trên.',
                        prefixIcon: Icon(Icons.map_outlined),
                        hintText:
                            'https://www.google.com/maps/dir/?api=1&destination=...',
                      ),
                      keyboardType: TextInputType.url,
                      maxLength: 1000,
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
