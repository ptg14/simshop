import 'package:flutter/foundation.dart';

/// Simple model representing a store (shop) in the multi‑store admin system.
@immutable
class Store {

  const Store({required this.id, required this.name});
  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Store && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
