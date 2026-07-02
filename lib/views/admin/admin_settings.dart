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
/// doesn't have to know about banner uploads or the network.
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

  // Banner upload state.
  String _bannerUrl = '';
  XFile? _bannerFile;
  Uint8List? _bannerFileBytes;
  bool _uploadingBanner = false;

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
    // setState around the banner URL assignment so the preview rebuilds
    // after the post-frame hydration kicks in. Without this the field
    // updates silently and the preview stays empty until the next
    // setState from something else (eg. typing in a text field).
    setState(() => _bannerUrl = info.bannerUrl);
  }

  Future<void> _pickBanner() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _bannerFile = picked;
      if (kIsWeb) {
        _bannerFileBytes = null; // resolved during upload
      } else {
        _bannerFileBytes = null;
      }
    });
    if (kIsWeb) {
      _bannerFileBytes = await picked.readAsBytes();
    }
    if (mounted) setState(() {});
  }

  Future<String?> _uploadBanner() async {
    if (_bannerFile == null) return _bannerUrl;
    setState(() => _uploadingBanner = true);
    try {
      final service = context.read<IProductService>();
      if (kIsWeb) {
        final bytes = _bannerFileBytes ?? await _bannerFile!.readAsBytes();
        return await service.uploadImage(
          bytes,
          productName: 'site-banner',
        );
      }
      return await service.uploadImage(
        File(_bannerFile!.path),
        productName: 'site-banner',
      );
    } finally {
      if (mounted) setState(() => _uploadingBanner = false);
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

    // Upload new banner first (if any), then save the row.
    String? bannerUrl = _bannerUrl;
    if (_bannerFile != null) {
      bannerUrl = await _uploadBanner();
      if (bannerUrl == null) {
        if (mounted) {
          setState(() => _saving = false);
          messenger.showSnackBar(
            const SnackBar(
                content: Text('Tải banner thất bại, vui lòng thử lại')),
          );
        }
        return;
      }
    }

    final info = StoreInfo(
      name: name,
      description: _descCtrl.text.trim(),
      bannerUrl: bannerUrl,
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
                    // Banner row: preview + pick button.
                    //
                    // The banner is horizontal (header-style) so the
                    // preview is rendered as a wide card, not a square
                    // thumbnail. We use a Column (not Row) so the
                    // preview can stretch to a useful width on tablet
                    // / desktop without squeezing the pick button.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _BannerPreview(
                          url: _bannerUrl,
                          file: _bannerFile,
                          bytes: _bannerFileBytes,
                        ),
                        const SizedBox(height: 12),
                        const Text('Banner cửa hàng',
                            style: TextStyle(
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          'PNG / JPG, nên chọn ảnh ngang (ví dụ 1200×400). Hiển thị trên AppBar trang chủ và footer.',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed:
                              _uploadingBanner ? null : _pickBanner,
                          icon: const Icon(Icons.image_outlined),
                          label: Text(_bannerUrl.isEmpty && _bannerFile == null
                              ? 'Chọn banner'
                              : 'Đổi banner'),
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

/// Banner preview tile. Shows the uploaded image if there is one
/// (either from a URL the backend already returned, or a freshly-picked
/// local file/bytes). Falls back to a placeholder icon.
///
/// The preview is intentionally horizontal (3:1 aspect) to mirror how
/// the banner is rendered on the home AppBar / footer.
class _BannerPreview extends StatelessWidget {
  const _BannerPreview({this.url, this.file, this.bytes});
  final String? url;
  final XFile? file;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = (url != null && url!.isNotEmpty) || file != null;
    Widget child;
    if (file != null) {
      // On web we can't read from a file path — wait until the bytes
      // are resolved (see `_pickBanner`). Falling through to
      // `Image.file(File(...))` on web throws because the dart:io
      // File path never points to a real file. Show the placeholder
      // while bytes are in flight.
      if (kIsWeb) {
        if (bytes != null) {
          child =
              Image.memory(bytes!, fit: BoxFit.cover, width: double.infinity);
        } else {
          child = Center(
            child: Icon(Icons.image_outlined,
                size: 40, color: scheme.onSurfaceVariant),
          );
        }
      } else {
        child = Image.file(File(file!.path),
            fit: BoxFit.cover, width: double.infinity);
      }
    } else if (url != null && url!.isNotEmpty) {
      child = Image.network(url!, fit: BoxFit.cover, width: double.infinity);
    } else {
      child = Center(
        child: Icon(Icons.image_outlined,
            size: 40, color: scheme.onSurfaceVariant),
      );
    }
    return AspectRatio(
      aspectRatio: 3,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: hasImage ? null : Border.all(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}