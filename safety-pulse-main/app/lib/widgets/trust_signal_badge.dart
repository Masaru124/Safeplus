import 'package:flutter/material.dart';
import '../models/safety.dart';

/// Trust Signal Badge Widget
///
/// Shows "Verified by X people" with a confidence indicator
class TrustSignalBadge extends StatelessWidget {
  final SafetyReport report;
  final bool showDetailed;
  final double fontSize;
  final Color? customColor;

  const TrustSignalBadge({
    super.key,
    required this.report,
    this.showDetailed = false,
    this.fontSize = 12.0,
    this.customColor,
  });

  @override
  Widget build(BuildContext context) {
    final totalVotes = report.trueVotes + report.falseVotes;
    final trustRatio = report.trustRatio;
    final confidenceLevel = _getConfidenceLevel(trustRatio);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: _getConfidenceColor(confidenceLevel).withOpacity(0.15),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: _getConfidenceColor(confidenceLevel).withOpacity(0.3),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getConfidenceIcon(confidenceLevel),
            size: fontSize * 0.9,
            color: customColor ?? _getConfidenceColor(confidenceLevel),
          ),
          SizedBox(width: 4.0),
          Text(
            showDetailed
                ? _getDetailedText(totalVotes)
                : _getShortText(totalVotes),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: customColor ?? _getConfidenceColor(confidenceLevel),
            ),
          ),
        ],
      ),
    );
  }

  String _getShortText(int totalVotes) {
    if (totalVotes == 0) return 'New';
    if (totalVotes == 1) return '1 verified';
    return '$totalVotes verified';
  }

  String _getDetailedText(int totalVotes) {
    if (totalVotes == 0) return 'No votes yet';
    if (totalVotes == 1) return 'Verified by 1 person';
    return 'Verified by $totalVotes people';
  }

  String _getConfidenceLevel(double ratio) {
    if (ratio >= 0.7) return 'high';
    if (ratio >= 0.4) return 'medium';
    return 'low';
  }

  Color _getConfidenceColor(String level) {
    switch (level) {
      case 'high':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getConfidenceIcon(String level) {
    switch (level) {
      case 'high':
        return Icons.verified_user;
      case 'medium':
        return Icons.verified;
      case 'low':
        return Icons.warning;
      default:
        return Icons.help;
    }
  }
}

/// Compact Trust Row - shows trust info in a row
class TrustSignalRow extends StatelessWidget {
  final SafetyReport report;
  final double spacing;

  const TrustSignalRow({super.key, required this.report, this.spacing = 8.0});

  @override
  Widget build(BuildContext context) {
    final totalVotes = report.trueVotes + report.falseVotes;
    final trustRatio = report.trustRatio;
    final confidenceLevel = _getConfidenceLevel(trustRatio);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Verified count
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people, size: 14.0, color: Colors.grey[600]),
            SizedBox(width: 2.0),
            Text(
              '$totalVotes',
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        SizedBox(width: spacing),
        // Confidence level
        Container(
          padding: EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
          decoration: BoxDecoration(
            color: _getConfidenceColor(confidenceLevel).withOpacity(0.15),
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: Text(
            confidenceLevel.toUpperCase(),
            style: TextStyle(
              fontSize: 10.0,
              fontWeight: FontWeight.w700,
              color: _getConfidenceColor(confidenceLevel),
              letterSpacing: 0.5,
            ),
          ),
        ),
        SizedBox(width: spacing),
        // Trust score
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.trending_up,
              size: 14.0,
              color: _getTrustColor(report.trustScore ?? 0.5),
            ),
            SizedBox(width: 2.0),
            Text(
              '${((report.trustScore ?? 0.5) * 100).toInt()}%',
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
                color: _getTrustColor(report.trustScore ?? 0.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getConfidenceLevel(double ratio) {
    if (ratio >= 0.7) return 'high';
    if (ratio >= 0.4) return 'medium';
    return 'low';
  }

  Color _getConfidenceColor(String level) {
    switch (level) {
      case 'high':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getTrustColor(double score) {
    if (score >= 0.7) return Colors.green;
    if (score >= 0.4) return Colors.orange;
    return Colors.red;
  }
}
