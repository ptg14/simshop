import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/admin_viewmodel.dart';
import '../../models/product.dart';

/// Admin upload screen for adding a new product with image picker.
class AdminUploadScreen extends StatefulWidget {
  const AdminUploadScreen({super.key});

  @override
  State<AdminUploadScreen> createState() => _AdminUploadScreenState();
}

class _AdminUploadScreenState extends State<AdminUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
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

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            // Image preview & picker
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: _selectedImage == null
                    ? Container(
                        width: 150,
                        height: 150,
                        color: Colors.grey[200],
                        child: const Icon(Icons.add_a_photo, size: 40),
                      )
                    : Image.file(
                        File(_selectedImage!.path),
                        width: 150,
                        height: 150,
                        fit: BoxFit.cover,
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
                      _selectedImage == null) {
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
                    imageUrl:
                        _selectedImage!.path, // using local path as placeholder
                    category: 'All',
                    rating: 0,
                    reviews: 0,
                    stock: 0,
                    specs: [],
                  );
                  await context.read<AdminViewModel>().addProduct(newProduct);
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
}
