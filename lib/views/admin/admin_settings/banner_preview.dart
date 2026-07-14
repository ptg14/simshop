import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Banner preview tile. Shows the uploaded image if there is one
/// (either from a URL the backend already returned, or a freshly-picked
/// local file/bytes). Falls back to a placeholder icon.
///
/// The preview is intentionally horizontal (3:1 aspect) to mirror how
/// the banner is rendered on the home AppBar / footer.
class BannerPreview extends StatelessWidget {
  const BannerPreview({super.key, this.url, this.file, this.bytes});
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
      // Surface a placeholder instead of crashing if the URL 404s
      // (e.g. an upload was removed from disk). A 404 from
      // [Image.network] would otherwise throw and break the preview
      // tile.
      child = Image.network(
        url!,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(Icons.image_not_supported_outlined,
              size: 40, color: scheme.onSurfaceVariant),
        ),
      );
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
