# TTSHOP Development Guide

This guide provides comprehensive information for developers working on the TTSHOP Flutter application.

## Architecture Overview

### MVVM Pattern

The application follows the Model-View-ViewModel (MVVM) pattern:

- **Model**: Data structures (`lib/models/`)
- **View**: UI screens (`lib/views/`)
- **ViewModel**: Business logic and state management (`lib/viewmodels/`)
- **Service**: Data access and external API calls (`lib/services/`)

### State Management

We use the **Provider** package for state management:

```dart
// Listen to a ViewModel
Consumer<HomeViewModel>(
  builder: (context, viewModel, _) {
    return Text(viewModel.products.length.toString());
  },
)

// Update state in ViewModel
viewModel.selectCategory(category);
```

## Project Conventions

### Naming Conventions

- **Files**: `snake_case.dart`
- **Classes**: `UpperCamelCase`
- **Methods/Functions**: `lowerCamelCase`
- **Constants**: `lowerCamelCase`
- **Private members**: `_leadingUnderscore`

### File Organization

```
lib/
├── models/           # Data models
├── services/         # Business logic & API calls
├── viewmodels/       # State management & logic
├── views/            # UI screens
├── widgets/          # Reusable widgets
└── utils/            # Utility functions
```

### Documentation

All public APIs should have documentation:

```dart
/// Fetches all products from the store.
/// 
/// Returns a list of [Product] objects sorted by rating.
/// Throws [Exception] if the network request fails.
Future<List<Product>> getAllProducts() async {
  // implementation
}
```

## Adding New Features

### 1. Create a Model

```dart
// lib/models/new_model.dart
class NewModel {
  final String id;
  final String name;
  
  NewModel({
    required this.id,
    required this.name,
  });
}
```

### 2. Create a Service

```dart
// lib/services/new_service.dart
abstract class INewService {
  Future<List<NewModel>> getAll();
}

class NewService implements INewService {
  @override
  Future<List<NewModel>> getAll() async {
    // implementation
  }
}
```

### 3. Create a ViewModel

```dart
// lib/viewmodels/new_viewmodel.dart
class NewViewModel extends ChangeNotifier {
  final INewService _service;
  List<NewModel> _items = [];
  
  NewViewModel({required INewService service}) : _service = service;
  
  List<NewModel> get items => _items;
  
  Future<void> loadItems() async {
    _items = await _service.getAll();
    notifyListeners();
  }
}
```

### 4. Create a View

```dart
// lib/views/new_view.dart
class NewView extends StatelessWidget {
  const NewView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<NewViewModel>(
      builder: (context, viewModel, _) {
        return ListView.builder(
          itemCount: viewModel.items.length,
          itemBuilder: (context, index) {
            return Text(viewModel.items[index].name);
          },
        );
      },
    );
  }
}
```

## API Integration

### Mock Data

Currently, the app uses `MockProductService`. For development and testing.

### Real API Integration

To integrate with a real backend:

1. Create a new service class
2. Update the service interface
3. Implement HTTP requests using the `http` package
4. Handle errors and loading states

Example:

```dart
class ProductApiService implements IProductService {
  final String baseUrl = 'https://api.example.com';
  
  @override
  Future<List<Product>> getAllProducts() async {
    final response = await http.get(Uri.parse('$baseUrl/products'));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List;
      return data.map((item) => Product.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load products');
    }
  }
}
```

## Testing

### Unit Tests

Test ViewModels and services:

```dart
test('HomeViewModel loads products', () async {
  final viewModel = HomeViewModel();
  await viewModel.loadProducts();
  
  expect(viewModel.products, isNotEmpty);
  expect(viewModel.isLoading, isFalse);
});
```

### Widget Tests

Test UI components:

```dart
testWidgets('ProductCard displays product name', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ProductCard(
        product: mockProduct,
        onTap: () {},
        onAddToCart: () {},
      ),
    ),
  );
  
  expect(find.text(mockProduct.name), findsOneWidget);
});
```

### Integration Tests

Test full user flows.

## Performance Tips

1. **Use const constructors** where possible
2. **Lazy load data** - don't load everything upfront
3. **Cache images** using `cached_network_image`
4. **Use ListView.builder** instead of ListView
5. **Minimize rebuilds** using ChangeNotifier selectively
6. **Profile your app** using Flutter DevTools

## Debugging

### Flutter DevTools

```bash
flutter pub global activate devtools
flutter pub global run devtools
```

Then connect your app to DevTools.

### Debug Print

```dart
debugPrint('Debug message: $variable');
```

### Breaking on Exceptions

```dart
dart run lib/main.dart --checked
```

## Code Quality

### Run Analysis

```bash
flutter analyze
```

### Format Code

```bash
dart format lib/
```

### Sort Dependencies

```bash
flutter pub get
```

## Git Workflow

1. Create a feature branch: `git checkout -b feature/feature-name`
2. Make changes and commit: `git commit -m "Implement feature"`
3. Push: `git push origin feature/feature-name`
4. Create a Pull Request for review

## Common Issues & Solutions

### Issue: Widgets not rebuilding
**Solution**: Ensure you're calling `notifyListeners()` in your ViewModel

### Issue: Images not loading
**Solution**: Check image URLs, ensure network access, and use error handlers

### Issue: Memory leaks
**Solution**: Dispose of controllers and close streams properly

## Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)
- [Provider Package](https://pub.dev/packages/provider)
- [Effective Dart](https://dart.dev/effective-dart)
- [Flutter Architecture Recommendations](https://docs.flutter.dev/app-architecture/recommendations)

## Support

For questions or issues, please open an issue or contact the team.
