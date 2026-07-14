import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:simshop/views/admin/banner_image_preview.dart';

void main() {
  group('bannerImagePreview', () {
    test('returns Image.memory when bytes are provided', () {
      final widget = bannerImagePreview(
        bytes: Uint8List.fromList([1, 2, 3]),
        file: null,
        existingUrl: '',
        isWeb: false,
      );
      expect(widget, isA<Image>());
      expect((widget as Image).image, isA<MemoryImage>());
    });

    test(
        'on web, returns Icon placeholder (not Image.file) when only a '
        'file path is available', () {
      // The bug: on web, with bytes==null and file!=null, the old
      // ternary fell through to Image.file which asserts !kIsWeb
      // and crashes the dialog. After the fix, web returns the
      // Icon placeholder.
      final widget = bannerImagePreview(
        bytes: null,
        file: XFile('/tmp/fake.png'),
        existingUrl: '',
        isWeb: true,
      );
      expect(widget, isA<Icon>());
      expect(widget, isNot(isA<Image>()));
    });

    test('on mobile, returns Image.file when only a file is provided', () {
      final widget = bannerImagePreview(
        bytes: null,
        file: XFile('/tmp/fake.png'),
        existingUrl: '',
        isWeb: false,
      );
      expect(widget, isA<Image>());
      expect((widget as Image).image, isA<FileImage>());
    });

    test('returns Image.network when an existing URL is provided', () {
      final widget = bannerImagePreview(
        bytes: null,
        file: null,
        existingUrl: 'https://example.com/banner.jpg',
        isWeb: false,
      );
      expect(widget, isA<Image>());
      expect((widget as Image).image, isA<NetworkImage>());
    });

    test('returns Icon placeholder when nothing is provided', () {
      final widget = bannerImagePreview(
        bytes: null,
        file: null,
        existingUrl: '',
        isWeb: false,
      );
      expect(widget, isA<Icon>());
      expect((widget as Icon).icon, Icons.image_outlined);
    });

    test('bytes take precedence over an existing URL', () {
      final widget = bannerImagePreview(
        bytes: Uint8List.fromList([0xFF]),
        file: null,
        existingUrl: 'https://example.com/banner.jpg',
        isWeb: true,
      );
      // Image.memory wins over Image.network.
      expect(widget, isA<Image>());
      expect((widget as Image).image, isA<MemoryImage>());
    });
  });
}
