import 'package:flutter/foundation.dart';
import '../models/safety.dart';
import '../services/api_service.dart';

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

  /// Initialize reports - fetch only from API (requires token)
  void initializeReports({required String token}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final centerLat = _userLocation?.latitude ?? 40.7484;
    final centerLng = _userLocation?.longitude ?? -73.9857;

    try {
      // Fetch from backend with authentication
      final reports = await _apiService.fetchReports(
        lat: centerLat,
        lng: centerLng,
        radius: 10.0,
        timeWindow: '24h',
        token: token,
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
  void setUserLocation(MapLocation location, {required String token}) {
    _userLocation = location;
    initializeReports(token: token);
  }

  /// Add a new report (submits to API, requires authentication)
  void addReport(SafetyReport report, {required String token}) async {
    // Get the signal type and severity from the category
    final signalType = categoryToSignalType[report.category] ?? 'other';
    final severity = categoryToSeverity[report.category] ?? 3;

    try {
      // Submit to backend with authentication
      await _apiService.submitReport(
        signalType: signalType,
        severity: severity,
        latitude: report.latitude,
        longitude: report.longitude,
        context: {
          'category': report.category,
          'description': report.description,
        },
        token: token,
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
  Future<void> refreshReports({required String token}) async {
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
        token: token,
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

  // ==================== Report Voting ====================

  /// Vote on a report (true = accurate, false = inaccurate)
  void voteOnReport({
    required String signalId,
    required bool isTrue,
    required String token,
  }) async {
    try {
      // Call API to vote
      final response = await _apiService.voteOnReport(
        signalId: signalId,
        isTrue: isTrue,
        token: token,
      );

      // Update the report in local list
      final index = _reports.indexWhere((r) => r.id == signalId);
      if (index != -1) {
        final report = _reports[index];
        _reports[index] = SafetyReport(
          id: report.id,
          latitude: report.latitude,
          longitude: report.longitude,
          level: report.level,
          category: report.category,
          description: report.description,
          timestamp: report.timestamp,
          opacity: report.opacity,
          trustScore: response.updatedTrustScore,
          reporterUsername: report.reporterUsername,
          trueVotes: response.newTrueVotes,
          falseVotes: response.newFalseVotes,
          userVote: isTrue,
        );
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to vote: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Remove vote from a report
  void removeVote({required String signalId, required String token}) async {
    try {
      // Call API to remove vote
      final response = await _apiService.removeVote(
        signalId: signalId,
        token: token,
      );

      // Update the report in local list
      final index = _reports.indexWhere((r) => r.id == signalId);
      if (index != -1) {
        final report = _reports[index];
        _reports[index] = SafetyReport(
          id: report.id,
          latitude: report.latitude,
          longitude: report.longitude,
          level: report.level,
          category: report.category,
          description: report.description,
          timestamp: report.timestamp,
          opacity: report.opacity,
          trustScore: response.updatedTrustScore,
          reporterUsername: report.reporterUsername,
          trueVotes: response.newTrueVotes,
          falseVotes: response.newFalseVotes,
          userVote: null, // No vote after removal
        );
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to remove vote: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Get vote summary for a report
  Future<VoteSummary> getVoteSummary({
    required String signalId,
    required String token,
  }) async {
    return await _apiService.getVoteSummary(signalId: signalId, token: token);
  }

  /// Check if user has voted on a report
  Future<bool> hasUserVoted({
    required String signalId,
    required String token,
  }) async {
    try {
      final response = await _apiService.checkUserVote(
        signalId: signalId,
        token: token,
      );
      return response.hasVoted;
    } catch (e) {
      return false;
    }
  }

  /// Delete a report (only owner can delete)
  Future<bool> deleteReport({
    required String signalId,
    required String token,
  }) async {
    try {
      await _apiService.deleteReport(signalId: signalId, token: token);
      // Remove from local list
      _reports.removeWhere((r) => r.id == signalId);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete report: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }
}
