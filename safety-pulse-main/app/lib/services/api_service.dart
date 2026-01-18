import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/safety.dart';

/// API Service for Safety Pulse Backend
class ApiService {
  static const String baseUrl = 'http://192.168.29.220:8000';

  /// Get device hash for API authentication
  String getDeviceHash(String deviceId) {
    final bytes = utf8.encode(deviceId);
    return sha256.convert(bytes).toString();
  }

  /// Submit a safety report to the backend
  Future<ReportResponse> submitReport({
    required String signalType,
    required int severity,
    required double latitude,
    required double longitude,
    Map<String, dynamic>? context,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/report');

    final body = jsonEncode({
      'signal_type': signalType,
      'severity': severity,
      'latitude': latitude,
      'longitude': longitude,
      'context': context ?? {},
    });

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-Device-Hash': getDeviceHash(
          'flutter-device-${DateTime.now().millisecondsSinceEpoch}',
        ),
      },
      body: body,
    );

    if (response.statusCode == 200) {
      return ReportResponse.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message:
            jsonDecode(response.body)['detail'] ?? 'Failed to submit report',
      );
    }
  }

  /// Fetch pulse data from the backend
  Future<List<PulseTile>> fetchPulseData({
    required double lat,
    required double lng,
    double radius = 10.0,
    String timeWindow = '24h',
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/pulse').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radius': radius.toString(),
        'time_window': timeWindow,
      },
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> tiles = data['tiles'] ?? [];
      return tiles.map((tile) => PulseTile.fromJson(tile)).toList();
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message:
            jsonDecode(response.body)['detail'] ?? 'Failed to fetch pulse data',
      );
    }
  }

  /// Fetch safety reports from the backend
  Future<List<SafetyReport>> fetchReports({
    required double lat,
    required double lng,
    double radius = 10.0,
    String timeWindow = '24h',
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/reports').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radius': radius.toString(),
        'time_window': timeWindow,
      },
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> reports = data['reports'] ?? [];
      return reports.map((report) => _parseReportItem(report)).toList();
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message:
            jsonDecode(response.body)['detail'] ?? 'Failed to fetch reports',
      );
    }
  }

  /// Parse report item from backend response
  SafetyReport _parseReportItem(Map<String, dynamic> json) {
    // Handle UUID as string or object
    String id;
    final idValue = json['id'];
    if (idValue is String) {
      id = idValue;
    } else if (idValue is Map<String, dynamic>) {
      id =
          idValue['uuid'] ??
          idValue['hex'] ??
          DateTime.now().millisecondsSinceEpoch.toString();
    } else if (idValue != null) {
      id = idValue.toString();
    } else {
      id = DateTime.now().millisecondsSinceEpoch.toString();
    }

    final signalType = json['signal_type'] as String? ?? 'other';
    final severity = (json['severity'] as num?)?.toInt() ?? 3;

    // Handle created_at - can be ISO string, datetime object, or dict
    DateTime timestamp;
    final createdAtValue = json['created_at'];
    if (createdAtValue is String) {
      // ISO 8601 format from JSON
      timestamp = DateTime.tryParse(createdAtValue) ?? DateTime.now();
    } else if (createdAtValue is int) {
      // Unix timestamp in milliseconds
      timestamp = DateTime.fromMillisecondsSinceEpoch(createdAtValue);
    } else if (createdAtValue is Map<String, dynamic>) {
      // Pydantic datetime dict format
      final isoString = createdAtValue[r'$date'];
      if (isoString != null) {
        timestamp = DateTime.tryParse(isoString) ?? DateTime.now();
      } else {
        timestamp = DateTime.now();
      }
    } else {
      timestamp = DateTime.now();
    }

    // Determine safety level from severity
    SafetyLevel level;
    if (severity >= 4) {
      level = SafetyLevel.unsafe;
    } else if (severity >= 2) {
      level = SafetyLevel.caution;
    } else {
      level = SafetyLevel.safe;
    }

    // Calculate opacity based on age
    final hoursAgo = DateTime.now().difference(timestamp).inHours.toDouble();
    final opacity = max(0.3, 1 - (hoursAgo / 24));

    // Get description from context if available
    Map<String, dynamic>? context =
        json['context_tags'] as Map<String, dynamic>?;
    String? description = context?['description'] as String?;

    // Get trust score from response
    final trustScore = (json['trust_score'] as num?)?.toDouble() ?? 0.5;

    return SafetyReport(
      id: id,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      level: level,
      category: _formatSignalType(signalType),
      description: description,
      timestamp: timestamp,
      opacity: opacity,
      trustScore: trustScore,
    );
  }

  String _formatSignalType(String signalType) {
    switch (signalType) {
      case 'followed':
        return 'Followed';
      case 'suspicious_activity':
        return 'Suspicious activity';
      case 'harassment':
        return 'Harassment';
      default:
        return 'Felt unsafe here';
    }
  }

  /// Check backend health
  Future<bool> checkHealth() async {
    final url = Uri.parse('$baseUrl/health');
    final response = await http.get(url);
    return response.statusCode == 200;
  }
}

/// API Response model
class ReportResponse {
  final String message;
  final String signalId;
  final double trustScore;

  ReportResponse({
    required this.message,
    required this.signalId,
    required this.trustScore,
  });

  factory ReportResponse.fromJson(Map<String, dynamic> json) {
    return ReportResponse(
      message: json['message'],
      signalId: json['signal_id'],
      trustScore: json['trust_score'].toDouble(),
    );
  }
}

/// Pulse Tile model
class PulseTile {
  final String tileId;
  final int pulseScore;
  final String confidence;

  PulseTile({
    required this.tileId,
    required this.pulseScore,
    required this.confidence,
  });

  factory PulseTile.fromJson(Map<String, dynamic> json) {
    return PulseTile(
      tileId: json['tile_id'],
      pulseScore: json['pulse_score'],
      confidence: json['confidence'],
    );
  }
}

/// API Exception
class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}

/// Category to signal type mapping
Map<String, String> categoryToSignalType = {
  'Felt unsafe here': 'other',
  'Followed': 'followed',
  'Poor lighting': 'other',
  'Suspicious activity': 'suspicious_activity',
  'Harassment': 'harassment',
  'Feels safe': 'other',
};

/// Category to severity mapping based on safety level
Map<String, int> categoryToSeverity = {
  'Felt unsafe here': 3,
  'Followed': 5,
  'Poor lighting': 2,
  'Suspicious activity': 4,
  'Harassment': 5,
  'Feels safe': 1,
};
