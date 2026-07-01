import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Image preview for the banner admin dialog.
///
/// Renders the right widget for the current source so the dialog
/// works on both mobile and Flutter Web:
///
///  - [bytes] non-null  → [Image.memory] (preferred on web after a
///                         file is picked and read into memory).
///  - [file] non-null + non-web → [Image.file] (mobile file path).
///  - [existingUrl] non-empty → [Image.network] with an
///                                  [Image.errorBuilder] fallback
///                                  (already-uploaded banner image).
///  - else             → [Icon] placeholder.
///
/// **Web safety**: the [Image.file] branch is gated on
/// `!isWeb && file != null` so the constructor is never reached on
/// Flutter Web. The previous in-place ternary
/// (`kIsWeb && bytes != null ? Image.memory : Image.file`) tripped
/// the SDK's `!kIsWeb` assert at build time on web, crashing the
/// banner dialog. Extracting the branch into a helper also makes
/// the choice unit-testable in isolation.
///
/// [isWeb] is passed in (instead of reading [kIsWeb] directly) so
/// tests can simulate the web environment.
Widget bannerImagePreview({
  required Uint8List? bytes,
  required XFile? file,
  required String existingUrl,
  required bool isWeb,
}) {
  if (bytes != null) {
    return Image.memory(bytes, fit: BoxFit.cover);
  }
  if (!isWeb && file != null) {
    return Image.file(File(file.path), fit: BoxFit.cover);
  }
  if (existingUrl.isNotEmpty) {
    // Use [Image.network] with an [Image.errorBuilder] so a broken
    // or unreachable URL (e.g. a legacy seed URL like
    // "http://example.com/img.jpg" that DNS-fails with statusCode 0)
    // renders the icon placeholder instead of throwing an exception
    // and crashing the dialog. The admin can still pick a real image
    // and re-save — the preview keeps working while they do.
    return Image.network(
      existingUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.image_not_supported_outlined),
    );
  }
  return const Icon(Icons.image_outlined);
}
