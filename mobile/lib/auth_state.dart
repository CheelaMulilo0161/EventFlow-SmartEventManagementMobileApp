import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';

class AuthState extends ChangeNotifier {
  AuthState({ApiClient? api}) : api = api ?? ApiClient();

  final ApiClient api;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _tokenKey = 'eventflow_token';
  static const _baseUrlKey = 'eventflow_api_base_url';

  User? user;
  String? error;
  bool initializing = true;
  bool busy = false;

  bool get isLoggedIn => user != null && api.token != null;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_baseUrlKey);
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        api.baseUrl = savedUrl.trim();
      }

      final token = await _storage.read(key: _tokenKey);
      if (token != null && token.isNotEmpty) {
        api.token = token;
        try {
          user = await api.me();
        } catch (e) {
          api.token = null;
          await _storage.delete(key: _tokenKey);
          if (e is ApiException && e.code != 'INVALID_TOKEN' && e.statusCode != 401) {
            error = e.message;
          }
        }
      }
    } finally {
      initializing = false;
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.login(email.trim(), password);
      final token = data['token'] as String;
      user = User.fromJson(data['user'] as Map<String, dynamic>);
      api.token = token;
      await _storage.write(key: _tokenKey, value: token);
      return true;
    } catch (e) {
      error = e is ApiException ? e.message : 'Could not log in. Try again.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required String role,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.register(
        email: email.trim(),
        password: password,
        fullName: fullName.trim(),
        phone: phone.trim(),
        role: role,
      );
      final token = data['token'] as String;
      user = User.fromJson(data['user'] as Map<String, dynamic>);
      api.token = token;
      await _storage.write(key: _tokenKey, value: token);
      return true;
    } catch (e) {
      error = e is ApiException ? e.message : 'Could not create the account. Try again.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    user = null;
    api.token = null;
    await _storage.delete(key: _tokenKey);
    notifyListeners();
  }

  Future<bool> updateApiBaseUrl(String value) async {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      error = 'Enter a full URL such as http://192.168.1.10:3000';
      notifyListeners();
      return false;
    }
    api.baseUrl = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, api.baseUrl);
    error = null;
    notifyListeners();
    return true;
  }

  Future<void> refreshUser() async {
    if (api.token == null) return;
    try {
      user = await api.me();
      notifyListeners();
    } catch (_) {
      // Keep the cached session; the next API call will surface a clear error.
    }
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}
