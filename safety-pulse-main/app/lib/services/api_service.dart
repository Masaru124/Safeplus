import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/safety.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';

/// API Service for Safety Pulse Backend
class ApiService {
  static const String baseUrl = 'http://192.168.29.220:8000';

  /// Get device hash for API authentication
  String getDeviceHash(String deviceId) {
    final bytes = utf8.encode(deviceId);
    return sha256.convert(bytes).toString();
  }

  // ==================== Authentication ====================

  /// Login with email and password
  Future<AuthToken> login(String email, String password) async {
    final url = Uri.parse('$baseUrl/api/v1/auth/login');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return AuthToken.fromJson(data);
    } else {
      final errorData = jsonDecode(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: errorData['detail'] ?? 'Login failed',
      );
    }
  }

  /// Register a new user
  Future<AuthToken> register(
    String email,
    String username,
    String password,
  ) async {
    final url = Uri.parse('$baseUrl/api/v1/auth/register');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return AuthToken.fromJson(data);
    } else {
      final errorData = jsonDecode(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: errorData['detail'] ?? 'Registration failed',
      );
    }
  }

  /// Get current user info
  Future<User> getCurrentUser(String token) async {
    final url = Uri.parse('$baseUrl/api/v1/auth/me');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return User.fromJson(data);
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to get user info',
      );
    }
  }

  // ==================== Safety Reports ====================

  /// Submit a safety report to the backend (requires authentication)
  Future<ReportResponse> submitReport({
    required String signalType,
    required int severity,
    required double latitude,
    required double longitude,
    Map<String, dynamic>? context,
    required String token,
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
        'Authorization': 'Bearer $token',
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

  /// Fetch safety reports from the backend (requires authentication)
  Future<List<SafetyReport>> fetchReports({
    required double lat,
    required double lng,
    double radius = 10.0,
    String timeWindow = '24h',
    required String token,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/reports').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radius': radius.toString(),
        'time_window': timeWindow,
      },
    );

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

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

  // ==================== Report Voting ====================

  /// Vote on a report (true = accurate, false = inaccurate)
  /// Requires authentication
  Future<VoteResponse> voteOnReport({
    required String signalId,
    required bool isTrue,
    required String token,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/reports/$signalId/vote');

    final body = jsonEncode({'is_true': isTrue});

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      return VoteResponse.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message:
            jsonDecode(response.body)['detail'] ?? 'Failed to vote on report',
      );
    }
  }

  /// Remove vote from a report
  /// Requires authentication
  Future<VoteResponse> removeVote({
    required String signalId,
    required String token,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/reports/$signalId/vote');

    final response = await http.delete(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return VoteResponse.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: jsonDecode(response.body)['detail'] ?? 'Failed to remove vote',
      );
    }
  }

  /// Get vote summary for a report
  /// Requires authentication
  Future<VoteSummary> getVoteSummary({
    required String signalId,
    required String token,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/reports/$signalId/votes');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return VoteSummary.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message:
            jsonDecode(response.body)['detail'] ?? 'Failed to get vote summary',
      );
    }
  }

  /// Check if current user has voted on a report
  /// Requires authentication
  Future<VoteCheckResponse> checkUserVote({
    required String signalId,
    required String token,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/reports/$signalId/vote/check');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return VoteCheckResponse.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: jsonDecode(response.body)['detail'] ?? 'Failed to check vote',
      );
    }
  }

  /// Delete a report (only the owner can delete their report)
  /// Requires authentication
  Future<DeleteReportResponse> deleteReport({
    required String signalId,
    required String token,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/reports/$signalId');

    final response = await http.delete(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return DeleteReportResponse.fromJson(jsonDecode(response.body));
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message:
            jsonDecode(response.body)['detail'] ?? 'Failed to delete report',
      );
    }
  }

  // ==================== Pulse Data ====================

  /// Fetch pulse data from the backend (requires authentication)
  Future<List<PulseTile>> fetchPulseData({
    required double lat,
    required double lng,
    double radius = 10.0,
    String timeWindow = '24h',
    required String token,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/pulse').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radius': radius.toString(),
        'time_window': timeWindow,
      },
    );

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

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

  /// Fetch active pulses from the backend (SINGLE source of truth for map)
  /// This endpoint returns pulse tiles with intensity, confidence, and dominant_reason
  Future<PulseListResponse> fetchActivePulses({
    required double lat,
    required double lng,
    double? radius,
    required String token,
  }) async {
    final params = <String, String>{
      // Optional location-based filtering
      if (lat != 0) 'lat': lat.toString(),
      if (lng != 0) 'lng': lng.toString(),
      if (radius != null) 'radius': radius.toString(),
    };

    final url = Uri.parse(
      '$baseUrl/api/v1/pulses/active',
    ).replace(queryParameters: params);

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return PulseListResponse.fromBackendJson(data);
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message:
            jsonDecode(response.body)['detail'] ??
            'Failed to fetch active pulses',
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
      // ISO 8601 format from JSON - try to parse
      timestamp = DateTime.tryParse(createdAtValue) ?? DateTime.now();
    } else if (createdAtValue is int) {
      // Unix timestamp in milliseconds
      timestamp = DateTime.fromMillisecondsSinceEpoch(createdAtValue);
    } else if (createdAtValue is Map<String, dynamic>) {
      // Pydantic datetime dict format
      final isoString = createdAtValue[r'$date'];
      if (isoString != null && isoString is String) {
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

    // Get trust score from response - ensure it's not null
    double trustScoreValue = 0.5;
    final trustScoreRaw = json['trust_score'];
    if (trustScoreRaw != null) {
      if (trustScoreRaw is double) {
        trustScoreValue = trustScoreRaw;
      } else if (trustScoreRaw is int) {
        trustScoreValue = trustScoreRaw.toDouble();
      } else if (trustScoreRaw is num) {
        trustScoreValue = trustScoreRaw.toDouble();
      }
    }

    // Get reporter username
    String? reporterUsername = json['reporter_username'] as String?;

    // Get user ID (report owner's ID) - can be string or UUID object
    String? userId;
    final userIdValue = json['user_id'];
    if (userIdValue is String) {
      userId = userIdValue;
    } else if (userIdValue != null) {
      userId = userIdValue.toString();
    }

    // Get vote counts
    int trueVotes = json['true_votes'] as int? ?? 0;
    int falseVotes = json['false_votes'] as int? ?? 0;
    bool? userVote = json['user_vote'] as bool?;

    return SafetyReport(
      id: id,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      level: level,
      category: _formatSignalType(signalType),
      description: description,
      timestamp: timestamp,
      opacity: opacity,
      trustScore: trustScoreValue,
      reporterUsername: reporterUsername,
      userId: userId,
      trueVotes: trueVotes,
      falseVotes: falseVotes,
      userVote: userVote,
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

/// Vote Response model
class VoteResponse {
  final String message;
  final String signalId;
  final bool isTrue;
  final int newTrueVotes;
  final int newFalseVotes;
  final double updatedTrustScore;

  VoteResponse({
    required this.message,
    required this.signalId,
    required this.isTrue,
    required this.newTrueVotes,
    required this.newFalseVotes,
    required this.updatedTrustScore,
  });

  factory VoteResponse.fromJson(Map<String, dynamic> json) {
    return VoteResponse(
      message: json['message'],
      signalId: json['signal_id'],
      isTrue: json['is_true'],
      newTrueVotes: json['new_true_votes'],
      newFalseVotes: json['new_false_votes'],
      updatedTrustScore: json['updated_trust_score'].toDouble(),
    );
  }
}

/// Vote Summary model
class VoteSummary {
  final String signalId;
  final int trueVotes;
  final int falseVotes;
  final int totalVotes;
  final double trustRatio;
  final double trustScore;

  VoteSummary({
    required this.signalId,
    required this.trueVotes,
    required this.falseVotes,
    required this.totalVotes,
    required this.trustRatio,
    required this.trustScore,
  });

  factory VoteSummary.fromJson(Map<String, dynamic> json) {
    return VoteSummary(
      signalId: json['signal_id'],
      trueVotes: json['true_votes'],
      falseVotes: json['false_votes'],
      totalVotes: json['total_votes'],
      trustRatio: json['trust_ratio'].toDouble(),
      trustScore: json['trust_score'].toDouble(),
    );
  }
}

/// Vote Check Response model
class VoteCheckResponse {
  final bool hasVoted;
  final bool? isTrue;

  VoteCheckResponse({required this.hasVoted, this.isTrue});

  factory VoteCheckResponse.fromJson(Map<String, dynamic> json) {
    return VoteCheckResponse(
      hasVoted: json['has_voted'],
      isTrue: json['is_true'],
    );
  }
}

/// Delete Report Response model
class DeleteReportResponse {
  final String message;
  final String deletedSignalId;
  final DateTime deletedAt;

  DeleteReportResponse({
    required this.message,
    required this.deletedSignalId,
    required this.deletedAt,
  });

  factory DeleteReportResponse.fromJson(Map<String, dynamic> json) {
    return DeleteReportResponse(
      message: json['message'],
      deletedSignalId: json['deleted_signal_id'],
      deletedAt: DateTime.tryParse(json['deleted_at']) ?? DateTime.now(),
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
