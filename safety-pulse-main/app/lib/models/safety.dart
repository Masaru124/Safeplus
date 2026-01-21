import 'dart:math';

enum SafetyLevel { safe, caution, unsafe }

class SafetyReport {
  final String id;
  final double latitude;
  final double longitude;
  final SafetyLevel level;
  final String category;
  final String? description;
  final DateTime timestamp;
  final double opacity;
  final double? trustScore;
  final String? reporterUsername; // Added field for reporter info
  final String?
  userId; // ID of the user who created this report (for ownership check)

  // Vote-related fields for trust score calculation
  final int trueVotes;
  final int falseVotes;
  final bool?
  userVote; // User's vote: true = accurate, false = inaccurate, null = no vote

  // New fields for confidence and trust
  final double confidenceScore; // Derived confidence (0.0-1.0)
  final double severityWeight; // Weight based on report type/severity
  final DateTime? lastActivityAt; // Last vote/edit timestamp
  final DateTime? expiresAt; // Expiration timestamp

  SafetyReport({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.level,
    required this.category,
    this.description,
    required this.timestamp,
    required this.opacity,
    this.trustScore,
    this.reporterUsername,
    this.userId,
    this.trueVotes = 0,
    this.falseVotes = 0,
    this.userVote,
    this.confidenceScore = 0.5,
    this.severityWeight = 0.5,
    this.lastActivityAt,
    this.expiresAt,
  });

  /// Total number of votes
  int get totalVotes => trueVotes + falseVotes;

  /// Trust ratio (true votes / total votes)
  double get trustRatio => totalVotes > 0 ? trueVotes / totalVotes : 0.5;

  /// Whether the current user has voted on this report
  bool get hasUserVoted => userVote != null;

  /// Whether the current user owns this report
  bool isOwnedBy(String? currentUserId) {
    return currentUserId != null && userId != null && currentUserId == userId;
  }

  /// Create SafetyReport from backend JSON response
  factory SafetyReport.fromBackendJson(Map<String, dynamic> json) {
    final signalType = json['signal_type'] as String? ?? 'other';
    final severity = json['severity'] as int? ?? 3;
    final createdAt =
        json['created_at'] as String? ?? DateTime.now().toIso8601String();
    final trustScore = (json['trust_score'] as num?)?.toDouble() ?? 0.5;

    // Vote fields
    final trueVotes = json['true_votes'] as int? ?? 0;
    final falseVotes = json['false_votes'] as int? ?? 0;
    final userVote = json['user_vote'] as bool?;

    // User ID for ownership check
    final userId = json['user_id'] as String?;

    // Determine safety level from severity
    SafetyLevel level;
    if (severity >= 4) {
      level = SafetyLevel.unsafe;
    } else if (severity >= 2) {
      level = SafetyLevel.caution;
    } else {
      level = SafetyLevel.safe;
    }

    // Parse datetime as UTC (backend sends timezone-aware UTC timestamps)
    final timestamp = DateTime.parse(createdAt).toUtc();

    // Parse new confidence and activity fields
    final confidenceScore =
        (json['confidence_score'] as num?)?.toDouble() ?? 0.5;
    final severityWeight = (json['severity_weight'] as num?)?.toDouble() ?? 0.5;
    final lastActivityAtStr = json['last_activity_at'] as String?;
    final lastActivityAt = lastActivityAtStr != null
        ? DateTime.parse(lastActivityAtStr).toUtc()
        : null;
    final expiresAtStr = json['expires_at'] as String?;
    final expiresAt = expiresAtStr != null
        ? DateTime.parse(expiresAtStr).toUtc()
        : null;

    // Calculate opacity based on age using UTC times
    final nowUtc = DateTime.now().toUtc();
    final hoursAgo = nowUtc.difference(timestamp).inHours.toDouble();
    final opacity = max(0.3, 1 - (hoursAgo / 24));

    return SafetyReport(
      id:
          (json['id'] as String?) ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      level: level,
      category: _formatSignalType(signalType),
      description: null,
      timestamp: timestamp,
      opacity: opacity,
      trustScore: trustScore,
      reporterUsername: json['reporter_username'] as String?,
      userId: userId,
      trueVotes: trueVotes,
      falseVotes: falseVotes,
      userVote: userVote,
      confidenceScore: confidenceScore,
      severityWeight: severityWeight,
      lastActivityAt: lastActivityAt,
      expiresAt: expiresAt,
    );
  }

  static String _formatSignalType(String signalType) {
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
}

class MapLocation {
  final double latitude;
  final double longitude;
  final double? zoom;

  const MapLocation({
    required this.latitude,
    required this.longitude,
    this.zoom,
  });
}

const Map<SafetyLevel, Map<String, int>> safetyColors = {
  SafetyLevel.safe: {'main': 0xFF22C55E, 'glow': 0x6622C55E},
  SafetyLevel.caution: {'main': 0xFFF59E0B, 'glow': 0x66F59E0B},
  SafetyLevel.unsafe: {'main': 0xFFEF4444, 'glow': 0x66EF4444},
};

const List<Map<String, dynamic>> reportCategories = [
  {
    'id': 'felt-unsafe',
    'label': 'Felt unsafe here',
    'icon': '⚠️',
    'level': SafetyLevel.caution,
  },
  {
    'id': 'followed',
    'label': 'Followed',
    'icon': '👁️',
    'level': SafetyLevel.unsafe,
  },
  {
    'id': 'poor-lighting',
    'label': 'Poor lighting',
    'icon': '💡',
    'level': SafetyLevel.caution,
  },
  {
    'id': 'suspicious-activity',
    'label': 'Suspicious activity',
    'icon': '🚨',
    'level': SafetyLevel.unsafe,
  },
  {
    'id': 'harassment',
    'label': 'Harassment',
    'icon': '🚫',
    'level': SafetyLevel.unsafe,
  },
  {
    'id': 'safe-area',
    'label': 'Feels safe',
    'icon': '✓',
    'level': SafetyLevel.safe,
  },
];

/// Pulse model - represents a safety pulse tile from the backend
/// This is the SINGLE source of truth for map rendering
class Pulse {
  final double lat;
  final double lng;
  final int radius; // in meters
  final double intensity; // 0.0-1.0
  final String confidence; // HIGH, MEDIUM, LOW
  final String? dominantReason;
  final DateTime lastUpdated;

  Pulse({
    required this.lat,
    required this.lng,
    required this.radius,
    required this.intensity,
    required this.confidence,
    this.dominantReason,
    required this.lastUpdated,
  });

  /// Get safety level based on intensity
  SafetyLevel get safetyLevel {
    if (intensity >= 0.7) return SafetyLevel.unsafe;
    if (intensity >= 0.4) return SafetyLevel.caution;
    return SafetyLevel.safe;
  }

  /// Get display color based on intensity
  int get colorHex {
    final colors = safetyColors[safetyLevel]!;
    return colors['main']!;
  }

  /// Get animation speed based on intensity (stronger pulses animate faster)
  Duration get animationDuration {
    // Stronger intensity = faster animation (shorter duration)
    final baseDuration = 2000; // 2 seconds base
    final adjustedDuration = (baseDuration * (1 - intensity * 0.5)).round();
    return Duration(milliseconds: adjustedDuration);
  }

  /// Get opacity based on intensity and confidence
  double get displayOpacity {
    // Base opacity from intensity
    final baseOpacity = intensity;

    // Boost for high confidence
    final confidenceBoost = confidence == 'HIGH'
        ? 0.2
        : confidence == 'MEDIUM'
        ? 0.1
        : 0.0;

    return (baseOpacity + confidenceBoost).clamp(0.3, 1.0);
  }

  /// Create Pulse from backend JSON response
  factory Pulse.fromBackendJson(Map<String, dynamic> json) {
    final lastUpdatedStr =
        json['last_updated'] as String? ?? DateTime.now().toIso8601String();
    final lastUpdated =
        DateTime.tryParse(lastUpdatedStr)?.toUtc() ?? DateTime.now().toUtc();

    return Pulse(
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      radius: json['radius'] as int? ?? 200,
      intensity: (json['intensity'] as num?)?.toDouble() ?? 0.0,
      confidence: json['confidence'] as String? ?? 'MEDIUM',
      dominantReason: json['dominant_reason'] as String?,
      lastUpdated: lastUpdated,
    );
  }

  /// Get formatted confidence display text
  String get confidenceDisplay {
    return 'Community confidence: $confidence';
  }

  /// Get formatted reason display text
  String? get reasonDisplay {
    return dominantReason;
  }

  /// Check if pulse is recent (within last hour)
  bool get isRecent {
    final now = DateTime.now().toUtc();
    final oneHourAgo = now.subtract(const Duration(hours: 1));
    return lastUpdated.isAfter(oneHourAgo);
  }

  /// Check if pulse is expiring soon (within 6 hours)
  bool get isExpiringSoon {
    final now = DateTime.now().toUtc();
    final sixHoursAgo = now.subtract(const Duration(hours: 6));
    return lastUpdated.isBefore(sixHoursAgo);
  }
}

/// Pulse list response from backend
class PulseListResponse {
  final List<Pulse> pulses;
  final int count;
  final String generatedAt;

  PulseListResponse({
    required this.pulses,
    required this.count,
    required this.generatedAt,
  });

  factory PulseListResponse.fromBackendJson(Map<String, dynamic> json) {
    final List<dynamic> pulsesJson = json['pulses'] ?? [];

    return PulseListResponse(
      pulses: pulsesJson.map((p) => Pulse.fromBackendJson(p)).toList(),
      count: json['count'] as int? ?? pulsesJson.length,
      generatedAt:
          json['generated_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
}
