import 'package:flutter/foundation.dart';
import '../models/event.dart';
import '../services/event_service.dart';

/// ViewModel for the admin "Sự kiện" tab.
///
/// Holds the cached list of events (active + expired — both render
/// in the UI with different badges). CRUD goes through here so the
/// local list stays in sync after each mutation, avoiding a refetch.
class EventsViewModel extends ChangeNotifier {
  EventsViewModel({IEventService? service})
      : _service = service ?? RealEventService();

  final IEventService _service;

  List<Event> _events = const [];
  bool _isLoading = false;
  String? _error;

  List<Event> get events => _events;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Active events sorted by soonest-ending first. Useful for
  /// dashboard widgets.
  List<Event> get activeEvents {
    final now = DateTime.now().toUtc();
    final active = _events.where((e) => e.isActive(now)).toList()
      ..sort((a, b) {
        final aT = a.endTime;
        final bT = b.endTime;
        if (aT == null && bT == null) return 0;
        if (aT == null) return 1;
        if (bT == null) return -1;
        return aT.compareTo(bT);
      });
    return active;
  }

  /// Fetch the latest event list. Safe to call multiple times.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _events = await _service.getEvents();
    } catch (e) {
      _error = 'Lỗi tải sự kiện: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Admin: create. On success the new event is prepended to the
  /// local list (server returns newest-first).
  Future<bool> createEvent(Event event) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _service.createEvent(event);
      _events = [saved, ..._events];
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Lỗi tạo sự kiện: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Admin: replace. The id on [event] must match the URL — the
  /// server treats the URL id as authoritative.
  Future<bool> updateEvent(Event event) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _service.updateEvent(event);
      _events = [
        for (final e in _events)
          if (e.id == saved.id) saved else e,
      ];
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Lỗi cập nhật sự kiện: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Admin: delete. Returns true on success.
  Future<bool> deleteEvent(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _service.deleteEvent(id);
      _events = _events.where((e) => e.id != id).toList();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Lỗi xóa sự kiện: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}