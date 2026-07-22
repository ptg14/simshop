import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/page_transitions.dart';
import '../../viewmodels/admin_auth_viewmodel.dart';
import 'admin_shell.dart';

/// Full-screen auth gate shown before the admin shell.
///
/// Visible to anyone who knows the secret handshake (long-press site
/// name in the footer 3×). Casual users have no UI hint that this
/// screen exists — that's intentional. After a successful challenge →
/// verify roundtrip we [Navigator.pushReplacement] into [AdminShell];
/// a bad key file or stale token leaves the user here with a retry
/// button.
class AdminAuthGate extends StatefulWidget {
  const AdminAuthGate({super.key});

  @override
  State<AdminAuthGate> createState() => _AdminAuthGateState();
}

class _AdminAuthGateState extends State<AdminAuthGate> {
  bool _alreadyCheckedStoredToken = false;

  @override
  void initState() {
    super.initState();
    // Defer the stored-token check until after the first build so a
    // returning admin (already verified in a previous session) gets
    // sent straight through the gate without seeing a flash of the
    // "Pick file" UI.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _alreadyCheckedStoredToken) return;
      _alreadyCheckedStoredToken = true;
      final vm = context.read<AdminAuthViewModel>();
      if (await vm.hasStoredToken()) {
        _openAdmin();
      }
    });
  }

  Future<void> _pickAndVerify() async {
    // FilePicker lets the user pick any file (the .key binary the
    // admin generated with the backend's `keygen` command). We pass
    // `withData: true` so the bytes come back inline — works on web
    // and mobile without a separate dart:io read path.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không đọc được file, vui lòng thử lại')),
      );
      return;
    }

    if (!mounted) return;
    final vm = context.read<AdminAuthViewModel>();
    final ok = await vm.authenticateWithSecretKey(
      Uint8List.fromList(bytes),
    );
    if (!mounted) return;
    if (ok) _openAdmin();
  }

  void _openAdmin() {
    Navigator.of(context).pushReplacement(
      fadeSlideRoute(const AdminShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xác thực quản trị'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Quay lại',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Consumer<AdminAuthViewModel>(
          builder: (context, vm, _) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.vpn_key_outlined,
                        size: 96,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Yêu cầu xác thực',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Chọn file secret key (.key)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 32),
                      if (vm.isLoading)
                        const Center(child: CircularProgressIndicator())
                      else
                        FilledButton.icon(
                          onPressed: _pickAndVerify,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Chọn file secret key'),
                        ),
                      if (vm.state == AdminAuthState.error && vm.error != null) ...[
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline,
                                  color: scheme.onErrorContainer, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  vm.error!,
                                  style: TextStyle(color: scheme.onErrorContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: vm.reset,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ),
      ),
    );
  }
}