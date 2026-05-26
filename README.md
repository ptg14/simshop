# TTSHOP - Flutter E-Commerce Mobile App

A modern e-commerce mobile application built with Flutter, featuring PC gaming products and accessories. This app demonstrates clean architecture principles using the MVVM (Model-View-ViewModel) pattern.

## Features

### 🛍️ Core Features
- **Product Catalog**: Browse PC gaming components, accessories, and peripherals
- **Search & Filter**: Search products by name and filter by category
- **Product Details**: Detailed product information with specifications
- **Shopping Cart**: Add/remove items, adjust quantities
- **Order Summary**: Calculate subtotal, tax, and shipping fees
- **Responsive Design**: Optimized for various screen sizes

### 🎨 UI Components
- Modern Material Design 3
- Promotional banners
- Category selector with smooth scrolling
- Product cards with discount badges
- Stock status indicators
- Rating and reviews display

### 🏗️ Architecture
- **MVVM Pattern**: Clean separation of concerns
- **Provider State Management**: Efficient state management
- **Repository Pattern**: Data access abstraction
- **Service Layer**: Business logic encapsulation
- **Immutable Models**: Predictable data flow

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/                   # Data models
│   ├── product.dart
│   └── cart_item.dart
├── services/                 # API and data services
│   └── product_service.dart
├── viewmodels/               # MVVM ViewModels
│   ├── home_viewmodel.dart
│   └── cart_viewmodel.dart
├── views/                    # UI screens
│   ├── home_screen.dart
│   ├── cart_screen.dart
│   └── product_detail_screen.dart
├── widgets/                  # Reusable widgets
│   ├── search_bar.dart
│   ├── product_card.dart
│   ├── promo_banner.dart
│   └── category_selector.dart
└── utils/                    # Utility functions
    └── currency_formatter.dart
```

## Dependencies

- **provider**: State management
- **go_router**: Navigation and routing
- **cached_network_image**: Image caching
- **intl**: Internationalization (Vietnamese support)
- **http**: HTTP client for API calls

## Getting Started

### Prerequisites
- Flutter 3.0.0 or higher
- Dart 3.0.0 or higher

### Installation

1. **Clone the repository**
```bash
git clone <repository-url>
cd simshop
```

2. **Install dependencies**
```bash
flutter pub get
```

3. **Run the app**
```bash
flutter run
```

### Building

**For Android:**
```bash
flutter build apk --release
```

**For iOS:**
```bash
flutter build ios --release
```

## Code Standards

This project follows the [Effective Dart](https://dart.dev/effective-dart) guidelines and [Flutter Architecture Recommendations](https://docs.flutter.dev/app-architecture/recommendations):

- ✅ Consistent naming conventions (lowerCamelCase, UpperCamelCase)
- ✅ Proper documentation with doc comments (`///`)
- ✅ Strong typing with null safety
- ✅ Immutable data models
- ✅ Separation of concerns (UI, business logic, data)

## Features in Development

- [ ] User authentication
- [ ] Order history
- [ ] Wishlist/Favorites
- [ ] Payment gateway integration
- [ ] Real-time order tracking
- [ ] Product reviews and ratings
- [ ] Push notifications

## API Integration

Currently uses mock data. To integrate with a real API:

1. Update `IProductService` in `lib/services/product_service.dart`
2. Implement real HTTP calls in a new service class
3. Handle error states and loading states appropriately

## Testing

To run tests:
```bash
flutter test
```

## Performance Optimization

- Image caching with `cached_network_image`
- Lazy loading for product lists
- Efficient state management with Provider
- Minimal rebuilds using ChangeNotifier

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Support

For support, email support@ttshop.com or open an issue in the repository.

---

**Built with ❤️ using Flutter**