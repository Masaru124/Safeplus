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
  });

  /// Create SafetyReport from backend JSON response
  factory SafetyReport.fromBackendJson(Map<String, dynamic> json) {
    final signalType = json['signal_type'] as String? ?? 'other';
    final severity = json['severity'] as int? ?? 3;
    final createdAt =
        json['created_at'] as String? ?? DateTime.now().toIso8601String();
    final trustScore = (json['trust_score'] as num?)?.toDouble() ?? 0.5;

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
