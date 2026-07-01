import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../models/product.dart';
import '../../../../utils/responsive.dart';

/// Options editor that renders each option as a row with a name
/// field, an image-picker strip, and a delete button.
///
/// The image strip shows:
///   - [existingImages] as selectable URL thumbnails (the admin taps
///     a thumb to toggle it in/out of the option's `imageUrls`).
///   - [newImageBytes] as non-selectable thumbnail placeholders so
///     the admin can see the bytes they've just picked (for the
///     product's hero image grid) inside the option row, even
///     before those bytes are uploaded.
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

/// Horizontal scroll row of selectable thumbnails for a single option.
///
/// - URL thumbs (from [existingImages]) are selectable; tapping
///   toggles inclusion in the option's `imageUrls`.
/// - Bytes thumbs (from [newImageBytes]) are non-selectable
///   placeholders so the admin can see their freshly-picked images
///   inside the option row before those bytes are uploaded.
///
/// When no images are present at all, renders a "Không" button so
/// the row has a visible affordance.
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

  void _toggle(String url) {
    final imgs = List<String>.from(option.imageUrls);
    imgs.contains(url) ? imgs.remove(url) : imgs.add(url);
    onChanged(Option(id: option.id, name: option.name, imageUrls: imgs));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalThumbs = existingImages.length + newImageBytes.length;
    if (totalThumbs == 0) {
      return TextButton(
        onPressed: () => onChanged(
            Option(id: option.id, name: option.name, imageUrls: [])),
        child: const Text('Không'),
      );
    }

    // Use Wrap so thumbnails flow onto a new line when the row's
    // horizontal space isn't enough. A horizontal SingleChildScrollView
    // looked right for 1-2 thumbs but silently clipped anything past
    // the visible area (e.g. when flex:2 narrows the column and
    // there are 3+ images) — those hidden thumbs couldn't be tapped.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Selectable URL thumbs first.
        for (var idx = 0; idx < existingImages.length; idx++)
          _UrlThumb(
            url: existingImages[idx],
            selected: option.imageUrls.contains(existingImages[idx]),
            scheme: scheme,
            onTap: () => _toggle(existingImages[idx]),
          ),
        // Non-selectable bytes thumbs (placeholders for the
        // freshly-picked images that haven't been uploaded yet).
        for (var idx = 0; idx < newImageBytes.length; idx++)
          _BytesThumb(bytes: newImageBytes[idx], scheme: scheme),
      ],
    );
  }
}

class _UrlThumb extends StatelessWidget {
  const _UrlThumb({
    required this.url,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  final String url;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: 'Ảnh $url',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Stack(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? scheme.primary : Colors.transparent,
                      width: selected ? 2 : 0,
                    ),
                  ),
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
                if (selected)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Semantics(
                      button: true,
                      label: 'Bỏ chọn ảnh',
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onTap,
                          customBorder: const CircleBorder(),
                          child: const SizedBox(
                            width: 20,
                            height: 20,
                            child: Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
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
