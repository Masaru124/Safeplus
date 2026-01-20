import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/user.dart';

/// Authentication state provider using Provider pattern
class AuthProvider with ChangeNotifier {
  User? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;

  // Token storage keys
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';

  // API base URL - should match your backend
  static const String baseUrl = 'http://192.168.29.220:8000';

  // Getters
  User? get user => _user;
  String? get token => _token;
  String? get userId => _user?.id;
  bool get isAuthenticated => _token != null && _user != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Initialize auth state from stored credentials
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString(_tokenKey);
      final storedUser = prefs.getString(_userKey);

      if (storedToken != null && storedUser != null) {
        _token = storedToken;
        _user = User.fromJson(jsonDecode(storedUser));
        _error = null;
      }
    } catch (e) {
      _error = 'Failed to restore session';
      _token = null;
      _user = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Login with email and password
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final authToken = AuthToken.fromJson(data);

        _token = authToken.accessToken;
        _user = authToken.user;

        // Save credentials
        await _saveCredentials();

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        final errorData = jsonDecode(response.body);
        _error = errorData['detail'] ?? 'Login failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Network error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Register a new user
  Future<bool> register(String email, String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final authToken = AuthToken.fromJson(data);

        _token = authToken.accessToken;
        _user = authToken.user;

        // Save credentials
        await _saveCredentials();

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        final errorData = jsonDecode(response.body);
        _error =
            errorData['detail'] ?? errorData['detail'] ?? 'Registration failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Network error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Logout and clear credentials
  Future<void> logout() async {
    _token = null;
    _user = null;
    _error = null;

    // Clear stored credentials
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);

    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Save credentials to local storage
  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, _token!);
    await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
  }

  /// Get authorization header for API requests
  Map<String, String> getAuthHeaders() {
    if (_token == null) return {};
    return {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
    };
  }
}
