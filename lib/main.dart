import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ttshop/viewmodels/home_viewmodel.dart';
import 'package:ttshop/viewmodels/cart_viewmodel.dart';
import 'package:ttshop/views/home_screen.dart';
import 'package:ttshop/views/cart_screen.dart';
import 'package:ttshop/views/product_detail_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HomeViewModel()),
        ChangeNotifierProvider(create: (_) => CartViewModel()),
      ],
      child: MaterialApp(
        title: 'TTSHOP - PC Gaming Store',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E88E5),
            brightness: Brightness.light,
          ),
          fontFamily: 'Roboto',
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 2,
            centerTitle: false,
          ),
        ),
        home: const HomeScreen(),
        routes: {
          '/home': (context) => const HomeScreen(),
          '/cart': (context) => const CartScreen(),
          '/product-detail': (context) => const ProductDetailScreen(),
        },
      ),
    );
  }
}
