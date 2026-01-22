import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Real-Time Service for Safety Pulse
///
/// Provides:
/// - WebSocket connections for live updates
/// - Polling fallback for clients without WebSocket support
/// - Pulse delta for efficient updates
class RealtimeService {
  String? _serverUrl;
  String? _token;
  WebSocket? _socket;
  Timer? _heartbeatTimer;

  // Controllers for streams
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final _newReportController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _pulseUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _spikeAlertController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _locationAlertController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _voteCastController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Connection state
  bool _isConnected = false;

  RealtimeService();

  /// Stream of all messages
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Stream of connection state changes
  Stream<bool> get connectionState => _connectionStateController.stream;

  /// Stream of new report events
  Stream<Map<String, dynamic>> get newReports => _newReportController.stream;

  /// Stream of pulse updates
  Stream<Map<String, dynamic>> get pulseUpdates =>
      _pulseUpdateController.stream;

  /// Stream of spike alerts
  Stream<Map<String, dynamic>> get spikeAlerts => _spikeAlertController.stream;

  /// Stream of location alerts
  Stream<Map<String, dynamic>> get locationAlerts =>
      _locationAlertController.stream;

  /// Stream of vote cast events
  Stream<Map<String, dynamic>> get voteCasts => _voteCastController.stream;

  /// Check if connected
  bool get isConnected => _isConnected;

  /// Connect to WebSocket server
  Future<void> connect(String serverUrl, {String? token}) async {
    if (_isConnected) {
      await disconnect();
    }

    _serverUrl = serverUrl;
    _token = token;

    try {
      final wsUrl = 'ws://${Uri.parse(serverUrl).host}:8000/api/v1/realtime/ws';
      _socket = await WebSocket.connect(wsUrl);

      _isConnected = true;
      _connectionStateController.add(true);

      // Authenticate if token provided
      if (token != null) {
        sendMessage({'type': 'auth', 'token': token});
      }

      // Start listening
      _socket!.listen(
        (dynamic message) => _handleMessage(message as String),
        onError: (error) {
          _isConnected = false;
          _connectionStateController.add(false);
        },
        onDone: () {
          _isConnected = false;
          _connectionStateController.add(false);
        },
      );

      // Start heartbeat
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => ping(),
      );
    } catch (e) {
      _isConnected = false;
      _connectionStateController.add(false);
      rethrow;
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    await _socket?.close();
    _socket = null;

    _isConnected = false;
    _connectionStateController.add(false);
  }

  /// Send message to server
  void sendMessage(Map<String, dynamic> message) {
    if (_socket != null && _isConnected) {
      _socket!.add(jsonEncode(message));
    }
  }

  /// Subscribe to topics
  void subscribe(List<String> topics) {
    sendMessage({'type': 'subscribe', 'topics': topics});
  }

  /// Unsubscribe from topics
  void unsubscribe(List<String> topics) {
    sendMessage({'type': 'unsubscribe', 'topics': topics});
  }

  /// Update location for targeted alerts
  void updateLocation(double latitude, double longitude) {
    sendMessage({
      'type': 'location_update',
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  /// Request pulse data
  void requestPulse(double latitude, double longitude, {double radius = 10.0}) {
    sendMessage({
      'type': 'request_pulse',
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
    });
  }

  /// Send ping to keep connection alive
  void ping() {
    sendMessage({'type': 'ping'});
  }

  /// Handle incoming messages
  void _handleMessage(String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final messageType = data['type'] as String?;

      // Add to general stream
      _messageController.add(data);

      // Handle specific types
      switch (messageType) {
        case 'new_report':
          final reportData = data['data'] as Map<String, dynamic>;
          _newReportController.add(reportData);
          break;
        case 'pulse_update':
          final pulseData = data['data'] as Map<String, dynamic>;
          _pulseUpdateController.add(pulseData);
          break;
        case 'spike_detected':
          final spikeData = data['data'] as Map<String, dynamic>;
          _spikeAlertController.add(spikeData);
          break;
        case 'location_alert':
          final alertData = data['data'] as Map<String, dynamic>;
          _locationAlertController.add(alertData);
          break;
        case 'vote_cast':
          final voteData = data['data'] as Map<String, dynamic>;
          _voteCastController.add(voteData);
          break;
        case 'pulse_updated':
          final pulseData = data['data'] as Map<String, dynamic>;
          _pulseUpdateController.add(pulseData);
          break;
        case 'pong':
          // Handle pong
          break;
      }
    } catch (e) {
      // Ignore parse errors
    }
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _messageController.close();
    _connectionStateController.close();
    _newReportController.close();
    _pulseUpdateController.close();
    _spikeAlertController.close();
    _locationAlertController.close();
    _voteCastController.close();
  }
}

/// Polling Service for clients without WebSocket support
class PollingService {
  final String baseUrl;
  String? _token;
  Timer? _timer;
  Duration _interval = const Duration(seconds: 30);

  DateTime? _lastUpdate;
  int _lastVersion = 0;

  // Callbacks
  final Function(List<Map<String, dynamic>>)? onNewReports;
  final Function(List<Map<String, dynamic>>)? onPulseUpdates;
  final Function(List<Map<String, dynamic>>)? onSpikes;

  PollingService({
    required this.baseUrl,
    this.onNewReports,
    this.onPulseUpdates,
    this.onSpikes,
  });

  set token(String? token) => _token = token;
  set interval(Duration interval) => _interval = interval;

  /// Start polling
  void start() {
    stop();
    _timer = Timer.periodic(_interval, (_) => _poll());
  }

  /// Stop polling
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Fetch updates using polling
  Future<void> poll({
    required double lat,
    required double lng,
    double radius = 10.0,
  }) async {
    try {
      final params = <String, String>{
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radius': radius.toString(),
      };

      if (_lastUpdate != null) {
        params['since'] = _lastUpdate!.toIso8601String();
      }

      final url = Uri.parse(
        '$baseUrl/api/v1/realtime/updates',
      ).replace(queryParameters: params);

      final response = await http.get(
        url,
        headers: {
          if (_token != null) 'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (onNewReports != null) {
          final reports = List<Map<String, dynamic>>.from(
            data['new_reports'] ?? [],
          );
          onNewReports!(reports);
        }

        if (onPulseUpdates != null) {
          final updates = List<Map<String, dynamic>>.from(
            data['pulse_updates'] ?? [],
          );
          onPulseUpdates!(updates);
        }

        if (onSpikes != null) {
          final spikes = List<Map<String, dynamic>>.from(data['spikes'] ?? []);
          onSpikes!(spikes);
        }

        _lastUpdate = DateTime.parse(data['server_time'] as String);
      }
    } catch (e) {
      // Ignore network errors
    }
  }

  /// Fetch pulse delta (more efficient)
  Future<void> fetchPulseDelta({
    required double lat,
    required double lng,
    double radius = 10.0,
  }) async {
    try {
      final params = <String, String>{
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radius': radius.toString(),
      };

      if (_lastVersion > 0) {
        params['version'] = _lastVersion.toString();
      }

      final url = Uri.parse(
        '$baseUrl/api/v1/realtime/pulse-delta',
      ).replace(queryParameters: params);

      final response = await http.get(
        url,
        headers: {
          if (_token != null) 'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (data['has_updates'] == true && onPulseUpdates != null) {
          final tiles = List<Map<String, dynamic>>.from(data['tiles'] ?? []);
          onPulseUpdates!(tiles);
        }

        _lastVersion = data['version'] as int? ?? 0;
      }
    } catch (e) {
      // Ignore network errors
    }
  }

  void _poll() {
    // Default implementation - should be overridden or use defaults
  }
}
