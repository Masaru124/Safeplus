import 'dart:math';
import '../models/safety.dart';

List<SafetyReport> generateMockReports(
  double centerLat,
  double centerLng,
  int count,
) {
  final reports = <SafetyReport>[];
  final levels = [
    SafetyLevel.safe,
    SafetyLevel.safe,
    SafetyLevel.safe,
    SafetyLevel.caution,
    SafetyLevel.caution,
    SafetyLevel.unsafe,
  ];
  const categories = [
    'Felt unsafe here',
    'Poor lighting',
    'Suspicious activity',
    'Followed',
    'Feels safe',
    'Harassment',
  ];

  for (int i = 0; i < count; i++) {
    final offsetLat = (Random().nextDouble() - 0.5) * 0.02;
    final offsetLng = (Random().nextDouble() - 0.5) * 0.02;
    final hoursAgo = Random().nextDouble() * 24;
    final opacity = max(0.3, 1 - (hoursAgo / 24));

    reports.add(
      SafetyReport(
        id: 'report-$i',
        latitude: centerLat + offsetLat,
        longitude: centerLng + offsetLng,
        level: levels[Random().nextInt(levels.length)],
        category: categories[Random().nextInt(categories.length)],
        timestamp: DateTime.now().subtract(Duration(hours: hoursAgo.toInt())),
        opacity: opacity,
      ),
    );
  }

  return reports;
}

String getTimeAgo(DateTime date) {
  // Convert both dates to UTC for consistent comparison
  final nowUtc = DateTime.now().toUtc();
  final dateUtc = date.toUtc();
  final seconds = nowUtc.difference(dateUtc).inSeconds;

  if (seconds < 60) return 'Just now';
  if (seconds < 3600) return '${seconds ~/ 60}m ago';
  if (seconds < 86400) return '${seconds ~/ 3600}h ago';
  return '${seconds ~/ 86400}d ago';
}

Map<String, dynamic> calculateAreaSafetyScore(List<SafetyReport> reports) {
  if (reports.isEmpty) {
    return {'score': 100, 'level': SafetyLevel.safe};
  }

  double totalWeight = 0;
  double safetySum = 0;

  for (final report in reports) {
    final weight = report.opacity;
    totalWeight += weight;

    switch (report.level) {
      case SafetyLevel.safe:
        safetySum += 100 * weight;
        break;
      case SafetyLevel.caution:
        safetySum += 50 * weight;
        break;
      case SafetyLevel.unsafe:
        safetySum += 0 * weight;
        break;
    }
  }

  final score = (safetySum / totalWeight).round();
  final level = score >= 70
      ? SafetyLevel.safe
      : score >= 40
      ? SafetyLevel.caution
      : SafetyLevel.unsafe;

  return {'score': score, 'level': level};
}
