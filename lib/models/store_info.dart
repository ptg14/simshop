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
    this.googleMapsUrl = '',
  });

  /// Empty / blank constructor used when the API returns no row.
  /// Keeps the home page from showing an unsightly placeholder.
  const StoreInfo.empty()
      : name = '',
        description = '',
        logoUrl = '',
        phone = '',
        email = '',
        address = '',
        googleMapsUrl = '';

  factory StoreInfo.fromJson(Map<String, dynamic> json) => StoreInfo(
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        logoUrl: (json['logo_url'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        address: (json['address'] as String?) ?? '',
        googleMapsUrl: (json['google_maps_url'] as String?) ?? '',
      );

  final String name;
  final String description;
  final String logoUrl;
  final String phone;
  final String email;
  final String address;

  /// Google Maps URL that the product detail "Buy at store" CTA
  /// launches directly. When empty, the CTA falls back to building
  /// a directions URL from [address]. Edited in admin settings.
  final String googleMapsUrl;

  /// True when no fields have been populated. Used by the UI to show
  /// a fallback rather than empty strings.
  bool get isEmpty =>
      name.isEmpty &&
      description.isEmpty &&
      logoUrl.isEmpty &&
      phone.isEmpty &&
      email.isEmpty &&
      address.isEmpty &&
      googleMapsUrl.isEmpty;

  StoreInfo copyWith({
    String? name,
    String? description,
    String? logoUrl,
    String? phone,
    String? email,
    String? address,
    String? googleMapsUrl,
  }) =>
      StoreInfo(
        name: name ?? this.name,
        description: description ?? this.description,
        logoUrl: logoUrl ?? this.logoUrl,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        address: address ?? this.address,
        googleMapsUrl: googleMapsUrl ?? this.googleMapsUrl,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'logo_url': logoUrl,
        'phone': phone,
        'email': email,
        'address': address,
        'google_maps_url': googleMapsUrl,
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
          address == other.address &&
          googleMapsUrl == other.googleMapsUrl;

  @override
  int get hashCode => Object.hash(name, description, logoUrl, phone, email,
      address, googleMapsUrl);
}
