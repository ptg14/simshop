# TTSHOP - Quick Start Guide

## 🚀 Getting Started

### Prerequisites

Make sure you have Flutter and Dart installed:

```bash
# Check Flutter version (requires 3.0.0+)
flutter --version

# Check Dart version (requires 3.0.0+)
dart --version
```

If not installed, follow the [Flutter installation guide](https://flutter.dev/docs/get-started/install).

### Setup Instructions

1. **Navigate to the project**
   ```bash
   cd /workspaces/simshop
   ```

2. **Get dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

   Or run on a specific device:
   ```bash
   # List available devices
   flutter devices
   
   # Run on specific device
   flutter run -d <device_id>
   ```

## 📱 Features Overview

### Home Screen
- Browse PC gaming products
- Search for products by name
- Filter by category (All, PC Gaming, PC Design, PC Accessories)
- View featured products on sale
- See promotional banners

### Product Details
- View product specifications
- Check stock availability
- Adjust quantity before adding to cart
- See discount percentages for sale items

### Shopping Cart
- Add/remove items
- Adjust quantities
- See order summary with tax and shipping
- Calculate total price

## 🛠️ Development

### Run in Debug Mode
```bash
flutter run
```

### Run in Release Mode
```bash
flutter run --release
```

### Run Tests
```bash
flutter test
```

### Code Analysis
```bash
flutter analyze
```

### Format Code
```bash
dart format lib/
```

## 📦 Project Structure

```
lib/
├── main.dart              # App entry point
├── models/                # Data models (Product, CartItem)
├── services/              # Business logic (ProductService)
├── viewmodels/            # State management (MVVM)
├── views/                 # UI screens (Home, Cart, Detail)
├── widgets/               # Reusable components
└── utils/                 # Helper functions
```

## 🎨 Customization

### Change App Colors
Edit the theme in `main.dart`:
```dart
colorScheme: ColorScheme.fromSeed(
  seedColor: const Color(0xFF1E88E5), // Change this color
)
```

### Update Product Data
Edit mock data in `lib/services/product_service.dart`:
```dart
final List<Product> _mockProducts = [
  // Add your products here
];
```

### Add New Categories
Update `_mockProducts` with new category strings:
```dart
Product(
  category: 'Your New Category',
  // ...
)
```

## 🐛 Troubleshooting

### App won't run
- Clean and rebuild: `flutter clean && flutter pub get && flutter run`
- Update Flutter: `flutter upgrade`
- Check device connection: `flutter devices`

### Build errors
- Run `flutter pub get` again
- Check `pubspec.yaml` for version conflicts
- See [Flutter troubleshooting](https://flutter.dev/docs/testing/troubleshooting)

### Images not showing
- Check internet connection
- Verify image URLs are valid
- Images use placeholder URLs - replace with real URLs in `product_service.dart`

## 📚 Project Architecture

### MVVM Pattern
- **Model**: `lib/models/` - Data structures
- **ViewModel**: `lib/viewmodels/` - Business logic & state
- **View**: `lib/views/` - UI screens
- **Service**: `lib/services/` - Data access

### State Management
Uses **Provider** package for reactive state management:
- `HomeViewModel`: Manages product listing, search, filtering
- `CartViewModel`: Manages shopping cart operations

## 🚢 Building for Deployment

### Android
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### iOS
```bash
flutter build ios --release
# Output: build/ios/iphoneos/Runner.app
```

## 📖 Documentation

- [README.md](README.md) - Project overview
- [DEVELOPMENT.md](DEVELOPMENT.md) - Detailed development guide
- [Effective Dart](https://dart.dev/effective-dart) - Dart conventions
- [Flutter Architecture Recommendations](https://docs.flutter.dev/app-architecture/recommendations)

## 💡 Tips

1. **Use hot reload** during development: Press `R` in terminal
2. **Use hot restart** when models change: Press `S` in terminal
3. **Use DevTools** for debugging: Run app first, then access DevTools
4. **Check logs** in terminal for detailed error messages
5. **Test on multiple devices** for consistency

## 🤝 Contributing

1. Create a feature branch: `git checkout -b feature/your-feature`
2. Make changes following Effective Dart guidelines
3. Test thoroughly: `flutter test`
4. Commit with clear messages: `git commit -m "Add feature description"`
5. Push and create a Pull Request

## ❓ FAQ

**Q: Can I use this with a real backend API?**
A: Yes! Update `ProductService` in `lib/services/product_service.dart` to call your API endpoints.

**Q: How do I add authentication?**
A: Create a `AuthViewModel` and `AuthService`, then wrap screens with auth checks.

**Q: Is this production-ready?**
A: This is a demo/starter project. Add proper error handling, validation, and testing before production.

**Q: How do I handle payments?**
A: Integrate a payment provider (Stripe, PayPal) in the cart checkout flow.

## 📞 Support

For issues or questions:
- Check [Flutter documentation](https://flutter.dev/docs)
- Open an issue on the repository
- Contact the development team

---

**Happy coding! 🎉**
