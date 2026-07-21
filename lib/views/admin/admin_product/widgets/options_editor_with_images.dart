import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../models/product.dart';
import '../../../../utils/responsive.dart';

/// Options editor that renders each option as a row with a name
/// field, a reorderable image strip (the admin's chosen images for
/// the option), a "more images" toggle strip (URLs + new bytes the
/// option isn't yet using), and a delete button.
///
/// The image strip shows:
///   - The option's currently-selected URLs in a **reorderable**
///     horizontal list — the admin drags tiles to change the order
///     in which the public product-detail carousel displays them.
///   - A non-reorderable "available" strip of unselected URLs +
///     freshly-picked bytes so the admin can add more images to the
///     option without scrolling back to the main gallery.
///
/// Both Add and Edit product dialogs use this widget so they share
/// one set of layout, IntrinsicHeight alignment, and image-row
/// rendering — any future change to option UX lands in one place.
class OptionsEditorWithImages extends StatelessWidget {
  const OptionsEditorWithImages({
    super.key,
    required this.options,
    required this.existingImages,
    required this.newImageBytes,
    required this.onChanged,
  });

  final List<Option> options;
  final List<String> existingImages;
  final List<Uint8List> newImageBytes;
  final ValueChanged<List<Option>> onChanged;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.dialogWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Options',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (var i = 0; i < options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: name field + delete button. The image
                    // picker is intentionally NOT in this Row because:
                    //   - Row's `crossAxisAlignment: center` would
                    //     vertically clip a multi-line Wrap (anything
                    //     below the first line of thumbs would be
                    //     cut off and untappable).
                    //   - The trailing IconButton's hit-target sits
                    //     at the right edge of the Row and would
                    //     visually cover the wrapped thumbnails on
                    //     subsequent lines.
                    // Putting the picker in its own full-width row
                    // below fixes both — the Wrap gets the entire
                    // dialog width to flow into, and the IconButton
                    // can't overlap any thumb.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            initialValue: options[i].name,
                            decoration: const InputDecoration(
                                labelText: 'Tên option'),
                            onChanged: (v) {
                              final updated = List<Option>.from(options);
                              updated[i] = Option(
                                id: options[i].id,
                                name: v,
                                // Preserve imageUrls across keystrokes —
                                // editing a name must never wipe an
                                // image assignment. This was a real
                                // bug in the original _OptionsEditor.
                                imageUrls:
                                    List<String>.from(options[i].imageUrls),
                              );
                              onChanged(updated);
                            },
                          ),
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            final updated = List<Option>.from(options)
                              ..removeAt(i);
                            onChanged(updated);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _OptionImageRow(
                      option: options[i],
                      existingImages: existingImages,
                      newImageBytes: newImageBytes,
                      onChanged: (updated) {
                        final list = List<Option>.from(options);
                        list[i] = updated;
                        onChanged(list);
                      },
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () {
                final updated = List<Option>.from(options)
                  ..add(Option(id: '', name: 'Option', imageUrls: []));
                onChanged(updated);
              },
              icon: const Icon(Icons.add),
              label: const Text('Thêm option'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
}

/// Two-strip image row for a single option.
///
/// Top strip: the option's currently-selected URLs in a horizontal
/// [ReorderableListView]. The admin drags a thumb to change the
/// order in which the product-detail carousel displays the option's
/// photos.
///
/// Bottom strip: every URL the option is *not* using, plus the
/// freshly-picked bytes that haven't been uploaded yet. Tapping a
/// thumb here adds it to the option (appending to the top strip);
/// tapping a thumb in the top strip removes it from the option.
class _OptionImageRow extends StatelessWidget {
  const _OptionImageRow({
    required this.option,
    required this.existingImages,
    required this.newImageBytes,
    required this.onChanged,
  });

  final Option option;
  final List<String> existingImages;
  final List<Uint8List> newImageBytes;
  final ValueChanged<Option> onChanged;

  void _add(String url) {
    final imgs = List<String>.from(option.imageUrls);
    if (imgs.contains(url)) return;
    imgs.add(url);
    onChanged(Option(id: option.id, name: option.name, imageUrls: imgs));
  }

  void _remove(String url) {
    final imgs = List<String>.from(option.imageUrls)
      ..remove(url);
    onChanged(Option(id: option.id, name: option.name, imageUrls: imgs));
  }

  void _reorder(int oldIndex, int newIndex) {
    final imgs = List<String>.from(option.imageUrls);
    final moved = imgs.removeAt(oldIndex);
    imgs.insert(newIndex, moved);
    onChanged(Option(id: option.id, name: option.name, imageUrls: imgs));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Unselected URLs: every existing image that isn't currently
    // in the option's imageUrls. Bytes have no URL, so they sit in
    // a separate constant-time list below.
    final unselected = existingImages
        .where((u) => !option.imageUrls.contains(u))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top: strip of selected URLs with explicit up/down
        // reorder buttons. We don't use [ReorderableListView]
        // here because it's a [Viewport] subclass, and an
        // `AlertDialog` queries the content's intrinsic
        // dimensions during layout — Viewports refuse to report
        // those, so the dialog throws on first build. Buttons
        // sidestep the constraint.
        if (option.imageUrls.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Chưa có ảnh cho option này — bấm vào ảnh bên dưới để thêm',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var idx = 0; idx < option.imageUrls.length; idx++)
                _ReorderableSelectedThumb(
                  url: option.imageUrls[idx],
                  index: idx,
                  isFirst: idx == 0,
                  isLast: idx == option.imageUrls.length - 1,
                  onRemove: () => _remove(option.imageUrls[idx]),
                  onMoveLeft: () => _reorder(idx, idx - 1),
                  // Insert at the slot one past the original
                  // index. [_reorder] does `removeAt(idx)` first,
                  // which already shifts every subsequent index
                  // down by one — so the slot we want is `idx`,
                  // NOT `idx + 2`. The old `+2` over-shot the
                  // list when the option had >= 2 images and the
                  // user clicked "right" on any item other than
                  // the very first, throwing `RangeError: Value
                  // not in range: <len>` from `List.insert`.
                  onMoveRight: () => _reorder(idx, idx + 1),
                ),
            ],
          ),
        const SizedBox(height: 6),
        // Bottom: pool of available images (unselected URLs +
        // freshly-picked bytes). Tapping adds the image to the
        // option's selected strip.
        if (unselected.isNotEmpty || newImageBytes.isNotEmpty) ...[
          Text(
            'Thêm ảnh cho option:',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final url in unselected)
                _AddableThumb(
                  url: url,
                  onTap: () => _add(url),
                ),
              for (final bytes in newImageBytes)
                _BytesThumb(bytes: bytes, scheme: scheme),
            ],
          ),
        ],
      ],
    );
  }
}

/// Selected (currently-in-option) thumbnail with up/down reorder
/// buttons (instead of drag) and a remove button. Buttons are used
/// instead of `ReorderableListView` because that widget is a
/// `Viewport`, which is incompatible with `AlertDialog`'s
/// intrinsic-dimension layout query — see [_OptionImageRow] for
/// details.
class _ReorderableSelectedThumb extends StatelessWidget {
  const _ReorderableSelectedThumb({
    required this.url,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.onRemove,
    required this.onMoveLeft,
    required this.onMoveRight,
  });

  final String url;
  final int index;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onRemove;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Ảnh $url — bấm mũi tên để sắp xếp, ✕ để bỏ',
      child: SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      color: scheme.surfaceContainerHighest),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Semantics(
                button: true,
                label: 'Bỏ chọn ảnh',
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onRemove,
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: 18,
                      height: 18,
                      child: Icon(Icons.close,
                          size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            // Reorder controls in the bottom-right corner. Up is
            // disabled at index 0, down at the last index — same
            // pattern as the gallery picker.
            Positioned(
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _OptionMoveButton(
                    icon: Icons.arrow_upward,
                    tooltip: 'Đưa lên trên',
                    onTap: isFirst ? null : onMoveLeft,
                  ),
                  _OptionMoveButton(
                    icon: Icons.arrow_downward,
                    tooltip: 'Đưa xuống dưới',
                    onTap: isLast ? null : onMoveRight,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiny square button used inside an option thumb.
class _OptionMoveButton extends StatelessWidget {
  const _OptionMoveButton({
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
              width: 16,
              height: 16,
              child: Icon(
                icon,
                size: 10,
                color: onTap == null
                    ? Colors.white.withValues(alpha: 0.4)
                    : Colors.white,
              ),
            ),
          ),
        ),
      );
}

/// Unselected URL thumb in the "available" pool. Tapping adds the
/// URL to the option.
class _AddableThumb extends StatelessWidget {
  const _AddableThumb({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Thêm ảnh $url vào option',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: scheme.outlineVariant,
                style: BorderStyle.solid,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      url,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          color: scheme.surfaceContainerHighest),
                    ),
                  ),
                ),
                // Subtle "+" hint in the corner so the admin
                // understands tapping the thumb adds it to the
                // option, rather than replacing the current
                // selection.
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BytesThumb extends StatelessWidget {
  const _BytesThumb({required this.bytes, required this.scheme});

  final Uint8List bytes;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Ảnh mới chọn (chưa upload)',
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              bytes,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
}
