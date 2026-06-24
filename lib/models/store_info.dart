import 'package:flutter/foundation.dart';

/// Editable site identity / branding information.
///
/// A singleton record (one row in the backend). Edited from admin
/// settings and rendered on the home page and product detail. Distinct
/// from the [Store] class which represents a per-product seller tag.
@immutable
class StoreInfo {
  const StoreInfo({
    this.name = 'simshop',
    this.description = '',
    this.logoUrl = '',
    this.phone = '',
    this.email = '',
    this.address = '',
  });

  /// Empty / blank constructor used when the API returns no row.
  /// Keeps the home page from showing an unsightly placeholder.
  const StoreInfo.empty()
      : name = '',
        description = '',
        logoUrl = '',
        phone = '',
        email = '',
        address = '';

  factory StoreInfo.fromJson(Map<String, dynamic> json) => StoreInfo(
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        logoUrl: (json['logo_url'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        address: (json['address'] as String?) ?? '',
      );

  final String name;
  final String description;
  final String logoUrl;
  final String phone;
  final String email;
  final String address;

  /// True when no fields have been populated. Used by the UI to show
  /// a fallback rather than empty strings.
  bool get isEmpty =>
      name.isEmpty &&
      description.isEmpty &&
      logoUrl.isEmpty &&
      phone.isEmpty &&
      email.isEmpty &&
      address.isEmpty;

  StoreInfo copyWith({
    String? name,
    String? description,
    String? logoUrl,
    String? phone,
    String? email,
    String? address,
  }) =>
      StoreInfo(
        name: name ?? this.name,
        description: description ?? this.description,
        logoUrl: logoUrl ?? this.logoUrl,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        address: address ?? this.address,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'logo_url': logoUrl,
        'phone': phone,
        'email': email,
        'address': address,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoreInfo &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          description == other.description &&
          logoUrl == other.logoUrl &&
          phone == other.phone &&
          email == other.email &&
          address == other.address;

  @override
  int get hashCode =>
      Object.hash(name, description, logoUrl, phone, email, address);
}
