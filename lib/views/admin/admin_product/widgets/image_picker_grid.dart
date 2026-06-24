import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../utils/responsive.dart';

/// Reusable image grid widget for picking, previewing, and removing images.
///
/// Shows:
///  - [newImagesBytes]  : newly selected images (memory bytes, web & mobile)
///  - [existingImages]  : already-uploaded image URLs (edit mode only)
///  - An "add" tile that triggers [onPickImages]
class ImagePickerGrid extends StatelessWidget {
  const ImagePickerGrid({
    super.key,
    required this.newImagesBytes,
    this.existingImages = const [],
    required this.onPickImages,
    required this.onRemoveNewImage,
    this.onRemoveExistingImage,
  });

  final List<Uint8List> newImagesBytes;
  final List<String> existingImages;
  final VoidCallback onPickImages;
  final void Function(int index) onRemoveNewImage;
  final void Function(int index)? onRemoveExistingImage;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: context.dialogWidth),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // New (locally selected) images
          for (var i = 0; i < newImagesBytes.length; i++)
            _ImageTile(
              child: Image.memory(
                newImagesBytes[i],
                fit: BoxFit.contain,
                alignment: Alignment.center,
              ),
              onRemove: () => onRemoveNewImage(i),
            ),

          // Existing (network) images — edit mode
          for (var j = 0; j < existingImages.length; j++)
            _ImageTile(
              onRemove: onRemoveExistingImage != null
                  ? () => onRemoveExistingImage!(j)
                  : null,
              child: Image.network(
                existingImages[j],
                fit: BoxFit.contain,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey[200],
                  child: const Icon(Icons.image_not_supported),
                ),
              ),
            ),

          // "Add image" tile
          Semantics(
            button: true,
            label: 'Thêm ảnh',
            child: Material(
              color: Colors.grey[100],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade400),
              ),
              child: InkWell(
                onTap: onPickImages,
                customBorder: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const SizedBox(
                  width: 72,
                  height: 72,
                  child: Center(child: Icon(Icons.add)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
}

/// Single 72×72 image tile with an optional remove button.
class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.child, this.onRemove});

  final Widget child;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Stack(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey[100],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: child,
          ),
        ),
        if (onRemove != null)
          Positioned(
            right: 0,
            top: 0,
            child: Semantics(
              button: true,
              label: 'Xóa ảnh',
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onRemove,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
}

/// Picks multiple images and returns (XFile list, bytes list).
Future<(List<XFile>, List<Uint8List>)> pickMultipleImages() async {
  final picker = ImagePicker();
  final images = await picker.pickMultiImage(imageQuality: 85);
  if (images.isEmpty) return (<XFile>[], <Uint8List>[]);

  if (kIsWeb) {
    final bytes = await Future.wait(images.map((e) => e.readAsBytes()));
    return (images, bytes);
  }
  // Mobile / desktop: return empty bytes; callers use File(xfile.path) directly
  return (images, <Uint8List>[]);
}