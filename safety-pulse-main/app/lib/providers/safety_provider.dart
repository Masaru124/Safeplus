import 'package:flutter/foundation.dart';
import 'dart:math';
import '../models/safety.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';

/// Zoom level thresholds for smart display
const double kZoomShowPulses = 11.0; // Show pulse clusters at this zoom
const double kZoomShowIndividual = 14.0; // Show individual reports at deep zoom
const double kZoomShowDetails = 16.0; // Show full details

/// Minimum intensity for pulse visibility
const double kMinPulseIntensity = 0.1;

/// Confidence thresholds
const double kHighConfidenceThreshold = 0.7;
const double kMediumConfidenceThreshold = 0.4;

class SafetyProvider with ChangeNotifier {
  List<SafetyReport> _reports = [];
  List<Pulse> _pulses = [];
  List<PulseTile> _pulseTiles = [];
  MapLocation? _userLocation;
  bool _isLoading = false;
  String? _errorMessage;

  // Zoom level for smart display
  double _currentZoom = 13.0;

  // Trust signal helpers
  bool _showTrustScores = true;

  // Spike animation state
  bool _isSpikeActive = false;
  DateTime? _spikeDetectedAt;

  // Real-time services
  RealtimeService? _realtimeService;
  PollingService? _pollingService;
  bool _useRealtime = false;

  // Stream subscriptions
  dynamic _newReportSubscription;
  dynamic _pulseUpdateSubscription;
  dynamic _spikeAlertSubscription;
  dynamic _locationAlertSubscription;

  final ApiService _apiService = ApiService();

  // ============ Getters ============

  List<SafetyReport> get reports => _reports;
  List<Pulse> get pulses => _pulses;
  List<PulseTile> get pulseTiles => _pulseTiles;
  MapLocation? get userLocation => _userLocation;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get useRealtime => _useRealtime;

  // Smart zoom getters
  double get currentZoom => _currentZoom;

  /// Whether to show pulses on the map
  bool get showPulses => true; // Always show pulses

  /// Whether to show individual reports (only at deep zoom)
  bool get showIndividualReports => _currentZoom >= kZoomShowIndividual;

  /// Whether to show full details (deepest zoom)
  bool get showFullDetails => _currentZoom >= kZoomShowDetails;

  /// Whether pulses are aggregated or granular
  bool get aggregatedMode => _currentZoom < kZoomShowIndividual;

  // Trust signal getters
  bool get showTrustScores => _showTrustScores;

  // Spike animation getters
  bool get isSpikeActive => _isSpikeActive;
  DateTime? get spikeDetectedAt => _spikeDetectedAt;

  // ============ Visibility Filters ============

  /// Get visible pulses filtered by intensity threshold
  List<Pulse> get visiblePulses {
    if (_currentZoom < kZoomShowPulses) {
      // At low zoom, show only high-intensity pulses
      return _pulses.where((p) => p.intensity >= 0.5).toList();
    }
    // At medium/high zoom, show all pulses above threshold
    return _pulses.where((p) => p.intensity >= kMinPulseIntensity).toList();
  }

  /// Get pulses with adjusted intensity based on confidence
  List<Pulse> get adjustedPulses {
    return visiblePulses.map((pulse) {
      // Adjust opacity based on confidence
      double adjustedIntensity = pulse.intensity;

      // High confidence boosts visibility
      if (pulse.confidence == 'HIGH') {
        adjustedIntensity = min(1.0, adjustedIntensity * 1.1);
      }

      return Pulse(
        lat: pulse.lat,
        lng: pulse.lng,
        radius: pulse.radius,
        intensity: adjustedIntensity,
        confidence: pulse.confidence,
        dominantReason: pulse.dominantReason,
        lastUpdated: pulse.lastUpdated,
      );
    }).toList();
  }

  /// Get reports filtered by current zoom level
  List<SafetyReport> get visibleReports {
    // Only show individual reports at deep zoom
    if (_currentZoom < kZoomShowIndividual) {
      return [];
    }

    // At deep zoom, show all reports with confidence-based filtering
    return _reports
        .where((r) => r.confidenceScore >= kMediumConfidenceThreshold)
        .toList();
  }

  /// Get pulse tiles filtered by confidence
  List<PulseTile> get visiblePulseTiles {
    if (_currentZoom < kZoomShowPulses) {
      // Show only high-intensity pulses at low zoom
      return _pulseTiles.where((t) => t.pulseScore >= 50).toList();
    }
    return _pulseTiles;
  }

  // ============ Confidence & Trust Helpers ============

  /// Get confidence level for a report
  String getConfidenceLevel(SafetyReport report) {
    final score = report.confidenceScore;
    if (score >= kHighConfidenceThreshold) return 'HIGH';
    if (score >= kMediumConfidenceThreshold) return 'MEDIUM';
    return 'LOW';
  }

  /// Get confidence level for a pulse
  String getPulseConfidence(Pulse pulse) {
    return pulse.confidence;
  }

  /// Get trust ratio text (without showing raw numbers)
  String getTrustRatioText(SafetyReport report) {
    final total = report.trueVotes + report.falseVotes;
    if (total == 0) return 'Community confidence: Not yet verified';
    if (total < 3) return 'Community confidence: Building';
    if (total < 10) return 'Community confidence: Growing';
    return 'Community confidence: Established';
  }

  /// Calculate dynamic opacity based on age and confidence
  double getDisplayOpacity(SafetyReport report) {
    // Base opacity from age
    final ageOpacity = report.opacity;

    // Boost opacity for high confidence reports
    final confidenceBoost = report.confidenceScore * 0.2;

    return (ageOpacity + confidenceBoost).clamp(0.2, 1.0);
  }

  // ============ Zoom Control ============

  /// Set current zoom level (for smart display)
  void setZoomLevel(double zoom) {
    if (_currentZoom != zoom) {
      _currentZoom = zoom;
      notifyListeners();
    }
  }

  /// Toggle trust score display
  void toggleTrustScores() {
    _showTrustScores = !_showTrustScores;
    notifyListeners();
  }

  // ============ Spike Animation ============

  /// Trigger spike animation
  void triggerSpikeAnimation() {
    _isSpikeActive = true;
    _spikeDetectedAt = DateTime.now();
    notifyListeners();

    // Auto-clear after animation
    Future.delayed(const Duration(seconds: 5), () {
      _isSpikeActive = false;
      notifyListeners();
    });
  }

  /// Clear spike animation
  void clearSpikeAnimation() {
    _isSpikeActive = false;
    notifyListeners();
  }

  // ============ Real-Time Setup ============

  /// Initialize with real-time updates
  void initializeWithRealtime({
    required String serverUrl,
    required String token,
    bool useWebSocket = true,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    _useRealtime = useWebSocket;

    if (useWebSocket) {
      _setupRealtimeConnection(serverUrl, token);
    } else {
      _startPolling(serverUrl, token);
    }

    await refreshAllData(token: token);
  }

  void _setupRealtimeConnection(String serverUrl, String token) {
    _realtimeService = RealtimeService();

    // Subscribe to streams
    _newReportSubscription = _realtimeService!.newReports.listen((reportData) {
      _handleNewReportFromRealtime(reportData);
    });

    _pulseUpdateSubscription = _realtimeService!.pulseUpdates.listen((
      pulseData,
    ) {
      _handlePulseUpdateFromRealtime(pulseData);
    });

    _spikeAlertSubscription = _realtimeService!.spikeAlerts.listen((spikeData) {
      _handleSpikeAlert(spikeData);
    });

    _locationAlertSubscription = _realtimeService!.locationAlerts.listen((
      alertData,
    ) {
      _handleLocationAlert(alertData);
    });

    // Listen for connection state changes
    _realtimeService!.connectionState.listen((connected) {
      if (!connected) {
        _errorMessage = 'Real-time connection lost. Switching to polling...';
        _useRealtime = false;
        _startPolling(serverUrl, token);
      }
      notifyListeners();
    });

    _realtimeService!.connect(serverUrl, token: token).catchError((e) {
      _errorMessage = 'WebSocket connection failed: $e';
      _useRealtime = false;
      notifyListeners();
    });
  }

  void _startPolling(String serverUrl, String token) {
    _pollingService = PollingService(
      baseUrl: serverUrl,
      onNewReports: (reports) {
        for (var report in reports) {
          _handleNewReportFromRealtime(report);
        }
      },
      onPulseUpdates: (updates) {
        for (var update in updates) {
          _handlePulseUpdateFromRealtime(update);
        }
      },
      onSpikes: (spikes) {
        for (var spike in spikes) {
          _handleSpikeAlert(spike);
        }
      },
    )..token = token;

    _pollingService!.start();
  }

  // ============ Real-Time Handlers ============

  void _handleNewReportFromRealtime(Map<String, dynamic> reportData) {
    final report = SafetyReport(
      id:
          reportData['signal_id'] ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      latitude: (reportData['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (reportData['longitude'] as num?)?.toDouble() ?? 0.0,
      level: _severityToLevel(reportData['severity'] as int? ?? 3),
      category: reportData['signal_type'] ?? 'other',
      description: reportData['context']?['description'],
      timestamp: DateTime.now(),
      opacity: 1.0,
      trustScore: (reportData['trust_score'] as num?)?.toDouble() ?? 0.5,
    );

    _reports.insert(0, report);
    notifyListeners();
  }

  void _handlePulseUpdateFromRealtime(Map<String, dynamic> pulseData) {
    // Update existing pulse or add new one
    final existingIndex = _pulses.indexWhere(
      (p) => p.lat == pulseData['lat'] && p.lng == pulseData['lng'],
    );

    if (existingIndex >= 0) {
      _pulses[existingIndex] = Pulse(
        lat: pulseData['lat'] ?? _pulses[existingIndex].lat,
        lng: pulseData['lng'] ?? _pulses[existingIndex].lng,
        radius: pulseData['radius'] ?? _pulses[existingIndex].radius,
        intensity: pulseData['intensity'] ?? _pulses[existingIndex].intensity,
        confidence:
            pulseData['confidence'] ?? _pulses[existingIndex].confidence,
        dominantReason:
            pulseData['dominant_reason'] ??
            _pulses[existingIndex].dominantReason,
        lastUpdated: DateTime.now().toUtc(),
      );
    } else if (pulseData['intensity'] != null &&
        pulseData['intensity'] > kMinPulseIntensity) {
      // Add new pulse if intensity is significant
      _pulses.add(
        Pulse(
          lat: pulseData['lat'] ?? 0.0,
          lng: pulseData['lng'] ?? 0.0,
          radius: pulseData['radius'] ?? 200,
          intensity: pulseData['intensity'] ?? 0.0,
          confidence: pulseData['confidence'] ?? 'MEDIUM',
          dominantReason: pulseData['dominant_reason'],
          lastUpdated: DateTime.now().toUtc(),
        ),
      );
    }
    notifyListeners();
  }

  void _handleSpikeAlert(Map<String, dynamic> spikeData) {
    _errorMessage =
        spikeData['message'] ?? 'Safety spike detected in your area';
    triggerSpikeAnimation();
    notifyListeners();
  }

  void _handleLocationAlert(Map<String, dynamic> alertData) {
    _errorMessage = alertData['message'];
    notifyListeners();
  }

  SafetyLevel _severityToLevel(int severity) {
    if (severity >= 4) return SafetyLevel.unsafe;
    if (severity >= 2) return SafetyLevel.caution;
    return SafetyLevel.safe;
  }

  // ============ Data Loading ============

  /// Initialize reports - fetch pulses as primary source for map
  void initializeReports({required String token}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final centerLat = _userLocation?.latitude ?? 40.7484;
    final centerLng = _userLocation?.longitude ?? -73.9857;

    try {
      // Fetch PULSES as primary source for map
      final pulses = await _apiService.fetchActivePulses(
        lat: centerLat,
        lng: centerLng,
        radius: 10.0,
        token: token,
      );
      _pulses = pulses.pulses;

      // Also fetch individual reports for detailed view (when zoomed in)
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
      _reports = [];
      _pulses = [];
      _isLoading = false;
      _errorMessage = 'Could not load safety data: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Set user location and fetch nearby pulses
  void setUserLocation(MapLocation location, {required String token}) {
    _userLocation = location;
    initializeReports(token: token);
    _realtimeService?.updateLocation(location.latitude, location.longitude);
  }

  /// Refresh all data from API (PULSE-ONLY for map)
  Future<void> refreshAllData({required String token}) async {
    final centerLat = _userLocation?.latitude ?? 40.7484;
    final centerLng = _userLocation?.longitude ?? -73.9857;

    try {
      // Fetch PULSES as primary source for map
      final pulses = await _apiService.fetchActivePulses(
        lat: centerLat,
        lng: centerLng,
        radius: 10.0,
        token: token,
      );
      _pulses = pulses.pulses;

      // Also fetch individual reports for detailed view
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
      _errorMessage = 'Failed to refresh: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh pulses only (for map updates)
  Future<void> refreshPulses({required String token}) async {
    final centerLat = _userLocation?.latitude ?? 40.7484;
    final centerLng = _userLocation?.longitude ?? -73.9857;

    try {
      final pulses = await _apiService.fetchActivePulses(
        lat: centerLat,
        lng: centerLng,
        radius: 10.0,
        token: token,
      );
      _pulses = pulses.pulses;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to refresh pulses: ${e.toString()}';
      notifyListeners();
    }
  }

  // ============ Report Actions ============

  /// Add a new report (submits to API, requires authentication)
  void addReport(SafetyReport report, {required String token}) async {
    final signalType = categoryToSignalType[report.category] ?? 'other';
    final severity = categoryToSeverity[report.category] ?? 3;

    try {
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

      _reports.add(report);
      // Refresh pulses to reflect new report
      await refreshPulses(token: token);
      notifyListeners();
    } catch (e) {
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

      // Also refresh pulses
      final pulses = await _apiService.fetchActivePulses(
        lat: _userLocation!.latitude,
        lng: _userLocation!.longitude,
        radius: 10.0,
        token: token,
      );
      _pulses = pulses.pulses;
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

  // ============ Report Voting ============

  void voteOnReport({
    required String signalId,
    required bool isTrue,
    required String token,
  }) async {
    try {
      final response = await _apiService.voteOnReport(
        signalId: signalId,
        isTrue: isTrue,
        token: token,
      );

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

  void removeVote({required String signalId, required String token}) async {
    try {
      final response = await _apiService.removeVote(
        signalId: signalId,
        token: token,
      );

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
          userVote: null,
        );
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Failed to remove vote: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<VoteSummary> getVoteSummary({
    required String signalId,
    required String token,
  }) async {
    return await _apiService.getVoteSummary(signalId: signalId, token: token);
  }

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

  Future<bool> deleteReport({
    required String signalId,
    required String token,
  }) async {
    try {
      await _apiService.deleteReport(signalId: signalId, token: token);
      _reports.removeWhere((r) => r.id == signalId);
      // Refresh pulses after deletion
      await refreshPulses(token: token);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete report: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // ============ Cleanup ============

  /// Dispose real-time services
  void disposeRealtime() {
    _newReportSubscription?.cancel();
    _pulseUpdateSubscription?.cancel();
    _spikeAlertSubscription?.cancel();
    _locationAlertSubscription?.cancel();

    _realtimeService?.dispose();
    _realtimeService = null;
    _pollingService?.stop();
    _pollingService = null;
  }
}
