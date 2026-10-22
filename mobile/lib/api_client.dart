import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.code = 'ERROR'});

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? AppConfig.defaultApiBaseUrl;

  String baseUrl;
  String? token;
  final http.Client _client = http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse('$normalized$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      late http.Response response;
      final uri = _uri(path, query);
      final headers = {..._headers, ...?extraHeaders};

      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers);
        case 'POST':
          response = await _client.post(uri, headers: headers, body: jsonEncode(body ?? {}));
        case 'PATCH':
          response = await _client.patch(uri, headers: headers, body: jsonEncode(body ?? {}));
        case 'DELETE':
          response = await _client.delete(uri, headers: headers);
        default:
          throw ApiException(0, 'Unsupported HTTP method $method');
      }

      dynamic decoded;
      if (response.body.isNotEmpty) {
        try {
          decoded = jsonDecode(response.body);
        } on FormatException {
          throw ApiException(response.statusCode, 'The server sent an invalid response');
        }
      }

      if (response.statusCode >= 400) {
        final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
        final message = error is Map<String, dynamic>
            ? error['message'] as String? ?? 'Request failed'
            : 'Request failed (${response.statusCode})';
        final code = error is Map<String, dynamic>
            ? error['code'] as String? ?? 'ERROR'
            : 'ERROR';
        throw ApiException(response.statusCode, message, code: code);
      }

      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'];
        if (data is Map<String, dynamic>) return data;
        return decoded;
      }
      return const {};
    } on ApiException {
      rethrow;
    } on SocketException {
      throw ApiException(
        0,
        'Cannot reach the EventFlow server. Check your Wi-Fi and the API address in Profile.',
        code: 'OFFLINE',
      );
    } on http.ClientException {
      throw ApiException(
        0,
        'Cannot reach the EventFlow server. Check your Wi-Fi and the API address in Profile.',
        code: 'OFFLINE',
      );
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) {
    return _request('POST', '/api/auth/login', body: {'email': email, 'password': password});
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String role,
  }) {
    return _request('POST', '/api/auth/register', body: {
      'email': email,
      'password': password,
      'full_name': fullName,
      'phone': phone,
      'role': role,
    });
  }

  Future<User> me() async {
    final data = await _request('GET', '/api/auth/me');
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<List<Event>> getEvents({String search = ''}) async {
    final data = await _request('GET', '/api/events', query: {
      if (search.trim().isNotEmpty) 'search': search.trim(),
      'limit': '50',
    });
    final events = data['events'] as List<dynamic>? ?? const [];
    return events.map((item) => Event.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<Event> getEvent(String eventId) async {
    final data = await _request('GET', '/api/events/$eventId');
    return Event.fromJson(data['event'] as Map<String, dynamic>);
  }

  Future<Booking> createBooking({
    required String eventId,
    required List<Map<String, dynamic>> items,
    required String idempotencyKey,
    String? attendeeName,
  }) async {
    final data = await _request(
      'POST',
      '/api/events/$eventId/bookings',
      body: {
        'items': items,
        if (attendeeName != null && attendeeName.trim().isNotEmpty)
          'attendee_name': attendeeName.trim(),
      },
      extraHeaders: {'Idempotency-Key': idempotencyKey},
    );
    return Booking.fromJson(data['booking'] as Map<String, dynamic>);
  }

  Future<List<Booking>> getBookings() async {
    final data = await _request('GET', '/api/bookings');
    final bookings = data['bookings'] as List<dynamic>? ?? const [];
    return bookings.map((item) => Booking.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<Booking> getBooking(String bookingId) async {
    final data = await _request('GET', '/api/bookings/$bookingId');
    return Booking.fromJson(data['booking'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> initiatePayment(
    String bookingId, {
    String? phone,
    String? network,
  }) {
    return _request('POST', '/api/bookings/$bookingId/pay', body: {
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (network != null && network.isNotEmpty) 'network': network,
    });
  }

  Future<Booking> simulatePayment(String reference) async {
    final data = await _request('POST', '/api/payments/$reference/simulate');
    return Booking.fromJson(data['booking'] as Map<String, dynamic>);
  }

  Future<Booking> cancelBooking(String bookingId) async {
    final data = await _request('POST', '/api/bookings/$bookingId/cancel');
    return Booking.fromJson(data['booking'] as Map<String, dynamic>);
  }

  Future<List<OrganizerEvent>> getOrganizerEvents() async {
    final data = await _request('GET', '/api/organizer/events');
    final events = data['events'] as List<dynamic>? ?? const [];
    return events
        .map((item) => OrganizerEvent.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Event> getOrganizerEvent(String eventId) async {
    final data = await _request('GET', '/api/organizer/events/$eventId');
    return Event.fromJson(data['event'] as Map<String, dynamic>);
  }

  Future<Event> createEvent(Map<String, dynamic> payload) async {
    final data = await _request('POST', '/api/events', body: payload);
    return Event.fromJson(data['event'] as Map<String, dynamic>);
  }

  Future<Event> publishEvent(String eventId) async {
    final data = await _request('POST', '/api/events/$eventId/publish');
    return Event.fromJson(data['event'] as Map<String, dynamic>);
  }

  Future<Event> cancelEvent(String eventId) async {
    final data = await _request('POST', '/api/events/$eventId/cancel');
    return Event.fromJson(data['event'] as Map<String, dynamic>);
  }

  Future<SalesSnapshot> getSales(String eventId) async {
    final data = await _request('GET', '/api/events/$eventId/sales');
    return SalesSnapshot.fromJson(data);
  }

  Future<ScanOutcome> scanTicket(String token, {String? eventId}) async {
    final data = await _request('POST', '/api/tickets/scan', body: {
      'token': token,
      'event_id': ?eventId,
    });
    return ScanOutcome.fromJson(data['result'] as Map<String, dynamic>);
  }

  Future<ScanOutcome> scanShortCode(String shortCode, {String? eventId}) async {
    final data = await _request('POST', '/api/tickets/scan-code', body: {
      'short_code': shortCode,
      'event_id': ?eventId,
    });
    return ScanOutcome.fromJson(data['result'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getAdminStats() async {
    final data = await _request('GET', '/api/admin/stats');
    return data['stats'] as Map<String, dynamic>? ?? const {};
  }
}
