import 'package:flutter/foundation.dart';
import '../models/safety.dart';
import '../services/api_service.dart';
import '../utils/safety_utils.dart';

class SafetyProvider with ChangeNotifier {
  List<SafetyReport> _reports = [];
  MapLocation? _userLocation;
  bool _isLoading = false;
  String? _errorMessage;

  final ApiService _apiService = ApiService();

  List<SafetyReport> get reports => _reports;
  MapLocation? get userLocation => _userLocation;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Initialize reports - fetch only from API
  void initializeReports() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final centerLat = _userLocation?.latitude ?? 40.7484;
    final centerLng = _userLocation?.longitude ?? -73.9857;

    try {
      // Fetch from backend
      final reports = await _apiService.fetchReports(
        lat: centerLat,
        lng: centerLng,
        radius: 10.0,
        timeWindow: '24h',
      );

      _reports = reports;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      // No mock fallback - show empty state
      _reports = [];
      _isLoading = false;
      _errorMessage = 'Could not load reports: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Set user location and fetch nearby reports
  void setUserLocation(MapLocation location) {
    _userLocation = location;
    initializeReports();
  }

  /// Add a new report (submits to API)
  void addReport(SafetyReport report) async {
    // Get the signal type and severity from the category
    final signalType = categoryToSignalType[report.category] ?? 'other';
    final severity = categoryToSeverity[report.category] ?? 3;

    try {
      // Submit to backend
      await _apiService.submitReport(
        signalType: signalType,
        severity: severity,
        latitude: report.latitude,
        longitude: report.longitude,
        context: {
          'category': report.category,
          'description': report.description,
        },
      );

      // Add to local list for immediate feedback
      _reports.add(report);
      notifyListeners();
    } catch (e) {
      // Still add locally if API fails (offline mode)
      _reports.add(report);
      _errorMessage = 'Saved locally: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Refresh reports from API
  Future<void> refreshReports() async {
    if (_userLocation == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final reports = await _apiService.fetchReports(
        lat: _userLocation!.latitude,
        lng: _userLocation!.longitude,
        radius: 10.0,
        timeWindow: '24h',
      );
      _reports = reports;
    } catch (e) {
      _errorMessage = 'Failed to refresh: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
