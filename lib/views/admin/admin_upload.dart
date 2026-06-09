import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../viewmodels/admin_viewmodel.dart';
import '../../viewmodels/home_viewmodel.dart';

/// Admin upload screen for adding a new product with image picker.
class AdminUploadScreen extends StatefulWidget {
  const AdminUploadScreen({super.key});

  @override
  State<AdminUploadScreen> createState() => _AdminUploadScreenState();
}

class _AdminUploadScreenState extends State<AdminUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _selectedImages = [];
  final List<Uint8List> _selectedImagesBytes = [];
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    // Use multi-image picker when available.
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      // Always read bytes for preview (works on web and mobile).
      final bytesList = await Future.wait(images.map((e) => e.readAsBytes()));
      setState(() {
        // Append new selections so user can add more later
        _selectedImages.addAll(images);
        _selectedImagesBytes.addAll(bytesList);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
        title: const Text('Upload sản phẩm'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnails grid (square tiles) with add tile; remove large primary frame
            Center(
              child: _selectedImagesBytes.isEmpty
                  ? GestureDetector(
                      onTap: _pickImages,
                      child: Container(
                        width: 150,
                        height: 150,
                        color: Colors.grey[200],
                        child: const Icon(Icons.add_a_photo, size: 40),
                      ),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0;
                              i < _selectedImagesBytes.length;
                              i++)
                            Stack(
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      _selectedImagesBytes[i],
                                      fit: BoxFit.contain,
                                      alignment: Alignment.center,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedImages.removeAt(i);
                                        _selectedImagesBytes.removeAt(i);
                                      });
                                    },
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          // Add tile
                          GestureDetector(
                            onTap: _pickImages,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(child: Icon(Icons.add)),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              decoration: const InputDecoration(labelText: 'Giá (đ)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Mô tả'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final name = _nameController.text.trim();
                  final priceText = _priceController.text.trim();
                  if (name.isEmpty ||
                      priceText.isEmpty ||
                      _selectedImages.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Vui lòng nhập đầy đủ thông tin và chọn ảnh')),
                    );
                    return;
                  }
                  final price = double.tryParse(priceText);
                  if (price == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Giá không hợp lệ')),
                    );
                    return;
                  }
                  final newProduct = Product(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: name,
                    description: _descriptionController.text.trim(),
                    price: price,
                    originalPrice: null,
                    imageUrl: '', // will be set after upload by the service
                    category: 'All',
                    rating: 0,
                    reviews: 0,
                    stock: 0,
                    specs: [],
                  );
                  // Pass image data to the viewmodel as bytes so upload is consistent
                  // across web and mobile and supports multiple images.
                  final imagePayload = _selectedImagesBytes;
                  await context.read<AdminViewModel>().addProduct(
                        newProduct,
                        imageFile: imagePayload,
                      );
                  // Refresh home product list so main menu updates immediately.
                  if (!context.mounted) return;
                  await context.read<HomeViewModel>().initialize();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Thêm sản phẩm thành công')),
                  );
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.upload),
                label: const Text('Upload'),
              ),
            ),
          ],
        ),
      ),
    );
}
