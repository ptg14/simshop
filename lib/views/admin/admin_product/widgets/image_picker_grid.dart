import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../utils/responsive.dart';

/// One tile in the gallery grid. The grid is a single ordered list
/// mixing already-uploaded URLs with freshly-picked bytes so the
/// admin can reorder across both groups (e.g. promote a newly-picked
/// image to position 0 to make it the cover).
///
/// Sealed class so callers can pattern-match on the variant
/// (see `whereType<GalleryExistingImage>` /
/// `whereType<GalleryNewImage>`).
sealed class GalleryItem {
  const GalleryItem();
}

/// An already-uploaded image (URL returned by the backend).
class GalleryExistingImage extends GalleryItem {
  const GalleryExistingImage(this.url);
  final String url;
}

/// An image picked in this edit session that hasn't been uploaded
/// yet. [xfile] is kept for the mobile path (`File(xfile.path)`);
/// [bytes] is used on web.
class GalleryNewImage extends GalleryItem {
  const GalleryNewImage({required this.xfile, required this.bytes});
  final XFile xfile;
  final Uint8List bytes;
}

/// Image grid for picking, previewing, removing, and reordering
/// images using up/down buttons.
///
/// Why buttons instead of drag-and-drop:
///   `ReorderableListView` is a `Viewport` subclass, and Flutter's
///   `AlertDialog` queries the intrinsic dimensions of its content
///   to size itself — `Viewport`s refuse to report intrinsic
///   dimensions, so the dialog layout throws an assertion. Rather
///   than fight the framework, we expose explicit ↑/↓ buttons per
///   tile (disabled at the ends) so the admin can still reorder
///   predictably.
///
/// State design:
///   * The widget is a pure [StatelessWidget] — the parent owns the
///     ordered list [items] and reacts to [onAdd], [onRemoveAt], and
///     [onReorder] callbacks.
class ImagePickerGrid extends StatelessWidget {
  const ImagePickerGrid({
    super.key,
    required this.items,
    required this.onPickImages,
    required this.onRemoveAt,
    required this.onReorder,
    this.tileSize = 72,
  });

  /// Ordered list of every image currently in the gallery. Index 0
  /// is the cover.
  final List<GalleryItem> items;

  /// Open the system multi-image picker and append the chosen
  /// files to the gallery. The parent decides the resulting order
  /// (typically: append to the end).
  final VoidCallback onPickImages;

  /// Remove the tile at [index]. The parent is responsible for
  /// tracking which URLs were removed (for backend cleanup on
  /// submit) — this widget just notifies the index.
  final void Function(int index) onRemoveAt;

  /// Move the tile at [oldIndex] to [newIndex] (both 0-based, into
  /// the same [items] list). Standard `List.move` semantics: the
  /// `newIndex` is the post-removal slot, identical to
  /// `ReorderableListView.onReorderItem`.
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Edge length of each square tile.
  final double tileSize;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.dialogWidth),
        // Use [Wrap] rather than a horizontal scroll view so the
        // grid flows onto a new line when the dialog is narrow.
        // Wrap is intrinsic-friendly — no `Viewport` involved — so
        // it works inside an `AlertDialog` body without throwing.
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var index = 0; index < items.length; index++)
              _ReorderableTile(
                item: items[index],
                size: tileSize,
                index: index,
                isFirst: index == 0,
                isLast: index == items.length - 1,
                onRemove: () => onRemoveAt(index),
                onMoveLeft: () => onReorder(index, index - 1),
                // Insert at the slot one past the original
                // index. [onReorder] does `removeAt(oldIndex)`
                // first, which already shifts every subsequent
                // index down by one — so the slot we want is
                // `index`, NOT `index + 2`. The old `+2` over-shot
                // the list whenever the gallery had >= 2 images
                // and the user clicked "right" on any item other
                // than the first, throwing `RangeError: Value
                // not in range: <len>` from `List.insert`.
                onMoveRight: () => onReorder(index, index + 1),
              ),
            _AddTile(onTap: onPickImages, size: tileSize),
          ],
        ),
      );
}

/// One image tile with remove + reorder buttons.
///
/// Left button (▲) moves the tile one slot up in the gallery;
/// right button (▼) moves it one slot down. Both are disabled at
/// the ends so the admin can't push a tile off the list. The
/// remove button (✕) sits in the top-right corner so the
/// affordances don't compete for space.
class _ReorderableTile extends StatelessWidget {
  const _ReorderableTile({
    required this.item,
    required this.size,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.onRemove,
    required this.onMoveLeft,
    required this.onMoveRight,
  });

  final GalleryItem item;
  final double size;
  final int index;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onRemove;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget thumb;
    if (item is GalleryExistingImage) {
      final url = (item as GalleryExistingImage).url;
      thumb = Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey[200],
          child: const Icon(Icons.image_not_supported),
        ),
      );
    } else {
      final bytes = (item as GalleryNewImage).bytes;
      thumb = Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        alignment: Alignment.center,
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: thumb,
            ),
          ),
          // Cover badge on index 0 so the admin can see at a
          // glance which image is currently the hero. Without
          // this they would have to remember the dialog's
          // "index 0 = cover" rule while scrolling.
          if (isFirst)
            Positioned(
              left: 0,
              bottom: 0,
              child: Semantics(
                label: 'Ảnh đại diện',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Cover',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          // Reorder controls. Vertical column on the right edge so
          // the up/down buttons don't overlap the remove button
          // (top-right). Disabled buttons render at reduced
          // opacity so the admin sees why a move isn't possible.
          Positioned(
            right: 2,
            top: 2,
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
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: Icon(Icons.close,
                        size: 14, color: scheme.onPrimary),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MoveButton(
                  icon: Icons.arrow_upward,
                  tooltip: 'Đưa lên trên',
                  onTap: isFirst ? null : onMoveLeft,
                ),
                _MoveButton(
                  icon: Icons.arrow_downward,
                  tooltip: 'Đưa xuống dưới',
                  onTap: isLast ? null : onMoveRight,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny square button used inside a tile. Matches the
/// `Colors.black54` palette of the remove button so the four
/// controls (✕, ▲, ▼, future) read as one toolbar.
class _MoveButton extends StatelessWidget {
  const _MoveButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black54,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 18,
              height: 18,
              child: Icon(
                icon,
                size: 12,
                color: onTap == null
                    ? Colors.white.withValues(alpha: 0.4)
                    : Colors.white,
              ),
            ),
          ),
        ),
      );
}

/// "+" tile that opens the multi-image picker.
class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap, required this.size});
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Thêm ảnh',
        child: Material(
          color: Colors.grey[100],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey.shade400),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: SizedBox(
              width: size,
              height: size,
              child: const Center(child: Icon(Icons.add)),
            ),
          ),
        ),
      );
}

/// Picks multiple images and returns (XFile list, bytes list).
///
/// Kept exported (top-level) so the dialogs can call it directly —
/// the widget above is purely presentational.
Future<(List<XFile>, List<Uint8List>)> pickMultipleImages() async {
  final picker = ImagePicker();
  final images = await picker.pickMultiImage(imageQuality: 85);
  if (images.isEmpty) return (<XFile>[], <Uint8List>[]);

  final bytes = <Uint8List>[];
  for (final img in images) {
    bytes.add(await img.readAsBytes());
  }
  return (images, bytes);
}
