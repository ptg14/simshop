import 'package:flutter/material.dart';

/// A subtle fade + 3% slide transition used for in-app navigation.
///
/// Replace direct `Navigator.pushNamed` calls with
/// `Navigator.of(context).push(fadeSlideRoute(...))` for a smoother feel.
Route<T> fadeSlideRoute<T>(Widget page) => PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut),
          ),
          child: child,
        ),
      ),
  );
