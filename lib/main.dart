import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'viewmodels/home_viewmodel.dart';
import 'viewmodels/admin_viewmodel.dart';
import 'views/home_screen.dart';
import 'views/product_detail_screen.dart';
import 'views/admin/admin_dashboard.dart';
import 'views/admin/admin_login.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => HomeViewModel()),
          ChangeNotifierProvider(create: (_) => AdminViewModel()),
        ],
        child: MaterialApp(
          title: 'Sample E-commerce App',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1E88E5),
              brightness: Brightness.light,
            ),
            fontFamily: 'Roboto',
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 2,
              centerTitle: false,
            ),
          ),
          home: const HomeScreen(),
          routes: {
            '/home': (context) => const HomeScreen(),
            '/product-detail': (context) => const ProductDetailScreen(),
            '/admin-login': (context) => const AdminLoginScreen(),
            '/admin': (context) => const AdminDashboard(),
          },
        ),
      );
}
