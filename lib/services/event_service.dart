import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/event.dart';
import '_http_with_admin_token.dart';
import 'admin_auth_service.dart';

/// Contract for the events feature (time-boxed promotions).
///
/// Mirrors the article service shape: a thin HTTP wrapper around the
/// Go backend's `/api/events` endpoints. The admin dashboard owns
/// the only callers right now — customers read effective prices
/// indirectly through the decorated product payload.
abstract class IEventService {
  /// Fetches every event (active + expired) newest-first. The admin
  /// UI renders both with different badges, so we don't filter here.
  Future<List<Event>> getEvents();

  /// Admin: create. Returns the persisted record (server may mint
  /// `created_at`).
  Future<Event> createEvent(Event event);

  /// Admin: replace. The id on [event] must match the URL.
  Future<Event> updateEvent(Event event);

  /// Admin: delete. Idempotent on the server side.
  Future<void> deleteEvent(String id);
}

/// Real implementation that talks to the Go backend.
class RealEventService implements IEventService {
  RealEventService({
    String? baseUrl,
    http.Client? client,
    IAdminAuthService? authService,
  })  : _baseUrl = baseUrl ?? 'http://localhost:8080',
        _client = client ?? http.Client(),
        _auth = authService;

  final String _baseUrl;
  final http.Client _client;
  // Optional — admin write endpoints attach the bearer token when set.
  final IAdminAuthService? _auth;

  Uri _listUri() => Uri.parse('$_baseUrl/api/events');
  Uri _itemUri(String id) => Uri.parse('$_baseUrl/api/events/$id');

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed (${response.statusCode}): ${response.body}');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<List<Event>> getEvents() async {
    final response = await _client.get(_listUri());
    final body = _decode(response);
    final raw = body['events'] as List<dynamic>? ?? const [];
    return raw
        .map((e) => Event.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<Event> createEvent(Event event) async {
    final headers = await withAdminAuth(
      _auth,
      const {'Content-Type': 'application/json'},
    );
    final response = await _client.post(
      _listUri(),
      headers: headers,
      body: json.encode(event.toJson()),
    );
    final body = _decode(response);
    return Event.fromJson(body);
  }

  @override
  Future<Event> updateEvent(Event event) async {
    final headers = await withAdminAuth(
      _auth,
      const {'Content-Type': 'application/json'},
    );
    final response = await _client.put(
      _itemUri(event.id),
      headers: headers,
      body: json.encode(event.toJson()),
    );
    final body = _decode(response);
    return Event.fromJson(body);
  }

  @override
  Future<void> deleteEvent(String id) async {
    final response = await _client.delete(_itemUri(id),
        headers: await withAdminAuth(_auth, const {}));
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Delete event failed (${response.statusCode})');
    }
  }
}