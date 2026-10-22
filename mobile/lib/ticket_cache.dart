import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class TicketCache {
  static Future<void> save(String userId, List<Booking> bookings) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = bookings.map((booking) => booking.toJson()).toList();
    await prefs.setString('eventflow_bookings_$userId', jsonEncode(payload));
  }

  static Future<List<Booking>> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('eventflow_bookings_$userId');
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => Booking.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('eventflow_bookings_$userId');
  }
}
