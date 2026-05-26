# Troubleshooting Guide

## Common Issues and Solutions

### Build & Installation Issues

#### Error: "Flutter command not found"
```bash
# Add Flutter to PATH
export PATH="$PATH:/path/to/flutter/bin"

# Or on Windows, add to system environment variables
```

#### Error: "Android SDK not found"
```bash
flutter doctor --android-licenses
flutter doctor
```

#### Error: "CocoaPods dependency resolution error" (iOS)
```bash
cd ios
rm -rf Pods
cd ..
flutter clean
flutter pub get
flutter run
```

### Runtime Issues

#### Widgets not updating after state change
**Problem**: UI doesn't reflect ViewModel changes

**Solution**: 
- Ensure you're calling `notifyListeners()` in ViewModel
- Check that Consumer is properly wrapping the widget
- Verify using `flutter run -d <device> --verbose`

```dart
// ✅ Correct
void updateData() {
  _data = newData;
  notifyListeners(); // Don't forget this!
}

// ❌ Wrong
void updateData() {
  _data = newData;
  // Missing notifyListeners()
}
```

#### Images not loading
**Problem**: Product images show error icon

**Solution**:
- Check image URLs are valid
- Verify internet connection
- Allow app to access network in Android manifest
- Use error builders for graceful degradation

```dart
Image.network(
  imageUrl,
  errorBuilder: (context, error, stackTrace) {
    return Icon(Icons.image_not_supported);
  },
)
```

#### Cart not persisting after app restart
**Problem**: Shopping cart is cleared when app closes

**Solution**: 
- This is expected with current implementation (in-memory storage)
- To persist data, implement:
  - Local database (Hive, SQLite)
  - Shared preferences
  - Cloud backend

```dart
// Example with shared_preferences
import 'package:shared_preferences/shared_preferences.dart';

// Save cart
final prefs = await SharedPreferences.getInstance();
await prefs.setString('cart', jsonEncode(cartItems));

// Load cart
final cartJson = prefs.getString('cart');
```

#### Search or filter not working
**Problem**: Category filter or search doesn't respond

**Solution**:
- Check HomeViewModel methods are being called
- Verify search query is being passed correctly
- Add debug prints to trace the flow

```dart
void searchProducts(String query) async {
  print('Searching for: $query'); // Debug
  _searchQuery = query;
  notifyListeners();
}
```

### Performance Issues

#### App is slow or freezing
**Problem**: UI is laggy or unresponsive

**Solution**:
1. Use `flutter run --profile` to profile
2. Avoid heavy operations on main thread
3. Use `FutureBuilder` or `StreamBuilder` for async work
4. Check for rebuild loops using Flutter DevTools

#### High memory usage
**Problem**: App consumes too much memory

**Solution**:
- Cache only necessary images
- Dispose of controllers and streams
- Use `ListView.builder` instead of `ListView`
- Profile with DevTools: Memory view

```dart
// ✅ Use builder
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => ItemTile(items[index]),
)

// ❌ Avoid - loads all items
ListView(
  children: items.map((item) => ItemTile(item)).toList(),
)
```

### Network Issues

#### "Connection refused" or "No network"
**Problem**: App can't reach API/mock service

**Solution**:
- Check internet connection
- Verify backend is running
- Check firewall/proxy settings
- Add timeout and retry logic

```dart
try {
  final response = await http.get(
    Uri.parse(url),
    headers: {'Content-Type': 'application/json'},
  ).timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw TimeoutException('Request timeout'),
  );
} catch (e) {
  debugPrint('Network error: $e');
  // Handle error
}
```

#### JSON parsing error
**Problem**: "Exception: type '_JsonMap' has no instance getter 'field'"

**Solution**:
- Verify API response matches expected structure
- Add null checks and defaults
- Log response for debugging

```dart
try {
  final data = jsonDecode(response.body);
  final product = Product.fromJson(data); // Add proper error handling
} on FormatException {
  throw Exception('Invalid JSON response');
}
```

### UI Issues

#### Text not fitting properly
**Problem**: Text overflows or is cut off

**Solution**:
```dart
// ✅ Correct
Text(
  productName,
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(fontSize: 14),
)

// ❌ Wrong - no overflow handling
Text(productName)
```

#### Navigation not working
**Problem**: Screen doesn't change when navigating

**Solution**:
- Check route is registered in main.dart
- Verify navigation code is correct
- Use named routes consistently

```dart
// ✅ Correct
Navigator.pushNamed(context, '/product-detail', arguments: product);

// ❌ Wrong - route not defined
Navigator.pushNamed(context, '/nonexistent-route');
```

#### Keyboard covering input
**Problem**: TextField hidden when keyboard appears

**Solution**:
```dart
// Use SingleChildScrollView
SingleChildScrollView(
  child: Column(
    children: [
      // Your widgets
      TextField(
        // Your text field
      ),
    ],
  ),
)

// Or use MediaQuery to adjust padding
Padding(
  padding: EdgeInsets.only(
    bottom: MediaQuery.of(context).viewInsets.bottom,
  ),
  child: TextField(),
)
```

### Debugging Tools

#### Enable verbose logging
```bash
flutter run -v
```

#### Open DevTools
```bash
# Terminal 1: Run app
flutter run

# Terminal 2: Open DevTools
flutter pub global activate devtools
flutter pub global run devtools
```

#### Check system logs
```bash
# Android
flutter logs

# iOS  
log stream --predicate 'process == "Runner"'
```

#### Add custom logging
```dart
import 'dart:developer' as developer;

// In your code
developer.log('Debug message', name: 'ttshop');

// Or use debugPrint
debugPrint('ViewModel state changed: $state');
```

## Performance Optimization Checklist

- [ ] Use `const` constructors where possible
- [ ] Implement `ListView.builder` for lists
- [ ] Cache network images
- [ ] Use `FutureBuilder` for async operations
- [ ] Avoid rebuilds with proper state management
- [ ] Use `--split-debug-info` for smaller APK
- [ ] Enable code shrinking for release builds
- [ ] Profile with DevTools
- [ ] Test on real devices, not just emulator

## Testing Issues

#### Tests failing to run
```bash
# Clean and retry
flutter clean
flutter pub get
flutter test
```

#### Test timeouts
```dart
test('My test', () async {
  // Add timeout
}, timeout: Timeout(Duration(seconds: 30)));
```

#### Mock data not working
Ensure mocks are properly set up in `product_service.dart`:
```dart
// ✅ Good
class MockProductService implements IProductService {
  final List<Product> _mockProducts = [...];
  // Implement all methods
}

// ❌ Bad
class MockProductService {
  // Missing interface implementation
}
```

## Getting More Help

1. **Check Flutter documentation**: https://flutter.dev/docs
2. **Search Stack Overflow**: Tag with `flutter`
3. **Review example code**: Check `lib/` for patterns
4. **Check package documentation**: https://pub.dev
5. **Open an issue** with:
   - `flutter doctor` output
   - Full error message
   - Minimal code reproduction
   - Steps to reproduce

## Emergency Reset

If everything is broken:

```bash
# Complete clean
flutter clean
rm -rf pubspec.lock

# Reinstall
flutter pub get

# Run doctor to check system
flutter doctor

# Try running again
flutter run --no-fast-start
```
