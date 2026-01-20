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
