import 'package:flutter/material.dart';
import '../models/safety.dart';
import '../screens/report_list_screen.dart';

/// Pulse Details Bottom Sheet with high contrast text
class PulseBottomSheet extends StatefulWidget {
  final Pulse pulse;
  final VoidCallback onClose;

  const PulseBottomSheet({
    super.key,
    required this.pulse,
    required this.onClose,
  });

  @override
  State<PulseBottomSheet> createState() => _PulseBottomSheetState();
}

class _PulseBottomSheetState extends State<PulseBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = SafetyStatus.forIntensity(widget.pulse.intensity);
    final statusColor = SafetyStatus.colorForStatus(status);
    final confidenceColor = ConfidenceLabels.colorForLevel(
      widget.pulse.confidence,
    );

    return GestureDetector(
      onVerticalDragStart: (_) {},
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, (1 - _animation.value) * 30),
            child: Opacity(opacity: _animation.value, child: child),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 3,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header with status
              _buildHeader(status, statusColor),
              // Confidence badge
              _buildConfidenceBadge(confidenceColor),
              // Divider
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                height: 1,
                color: Colors.grey[300],
              ),
              // Details section - scrollable
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: _buildDetails(),
                ),
              ),
              // Disclaimer
              _buildDisclaimer(),
              // Buttons
              _buildButtons(),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String status, Color statusColor) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor.withOpacity(0.15),
              border: Border.all(color: statusColor, width: 2),
            ),
            child: Icon(_getStatusIcon(status), color: statusColor, size: 26),
          ),
          const SizedBox(width: 16),
          // Status text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Area Status',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Intensity indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(widget.pulse.intensity * 100).toInt()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'intensity',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceBadge(Color confidenceColor) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [confidenceColor.withOpacity(0.1), Colors.transparent],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: confidenceColor.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user, color: confidenceColor, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Community Confidence',
                  style: TextStyle(color: Colors.grey[700], fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  ConfidenceLabels.displayText(widget.pulse.confidence),
                  style: TextStyle(
                    color: confidenceColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          // Confidence level badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: confidenceColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.pulse.confidence,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails() {
    final primaryConcern = widget.pulse.dominantReason;
    final isRecent = widget.pulse.isRecent;
    final lastActivity = _formatTimeAgo(widget.pulse.lastUpdated);
    final location =
        '${widget.pulse.lat.toStringAsFixed(4)}, ${widget.pulse.lng.toStringAsFixed(4)}';
    final radius = '${widget.pulse.radius}m';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Primary concern
        _buildDetailItem(
          icon: Icons.info_outline,
          label: 'Primary concern',
          value: primaryConcern ?? 'Not specified',
          valueColor: Colors.black87,
        ),
        const SizedBox(height: 16),
        // Last activity
        _buildDetailItem(
          icon: Icons.access_time,
          label: 'Last activity',
          value: lastActivity,
          valueColor: Colors.black87,
          badge: isRecent ? 'RECENT' : null,
        ),
        const SizedBox(height: 16),
        // Location
        _buildDetailItem(
          icon: Icons.location_on,
          label: 'Location',
          value: location,
          valueColor: Colors.black87,
        ),
        const SizedBox(height: 16),
        // Radius
        _buildDetailItem(
          icon: Icons.social_distance,
          label: 'Radius',
          value: radius,
          valueColor: Colors.black87,
        ),
        const SizedBox(height: 16),
        // Reports indicator
        _buildDetailItem(
          icon: Icons.people,
          label: 'Community reports',
          value: 'Aggregated from multiple users',
          valueColor: Colors.black87,
        ),
      ],
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
    String? badge,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: Colors.grey[700]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: valueColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDisclaimer() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.info, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This represents aggregated community feelings, not verified incidents.',
              style: TextStyle(color: Colors.blue[800], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // View Reports button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ReportListScreen(
                      pulseLat: widget.pulse.lat,
                      pulseLng: widget.pulse.lng,
                      radius: widget.pulse.radius,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.list_alt, size: 20),
              label: const Text(
                'View all reports',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Close button
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                _controller.reverse().then((_) {
                  widget.onClose();
                });
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                'Close',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Calm':
        return Icons.check_circle;
      case 'Moderate':
        return Icons.info;
      case 'Cautious':
        return Icons.warning;
      case 'Unsafe':
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now().toUtc();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} hours ago';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${difference.inDays ~/ 7} weeks ago';
  }
}

/// Show pulse bottom sheet
Future<void> showPulseDetails({
  required BuildContext context,
  required Pulse pulse,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => PulseBottomSheet(
      pulse: pulse,
      onClose: () => Navigator.of(context).pop(),
    ),
  );
}

// ============ Report Bottom Sheet ============

/// Report Details Bottom Sheet - shown when clicking on individual report markers
class ReportBottomSheet extends StatefulWidget {
  final SafetyReport report;
  final VoidCallback onClose;

  const ReportBottomSheet({
    super.key,
    required this.report,
    required this.onClose,
  });

  @override
  State<ReportBottomSheet> createState() => _ReportBottomSheetState();
}

class _ReportBottomSheetState extends State<ReportBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mainColor = SafetyColors.forLevel(widget.report.level);
    final confidenceColor = _getConfidenceColor();

    return GestureDetector(
      onVerticalDragStart: (_) {},
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, (1 - _animation.value) * 30),
            child: Opacity(opacity: _animation.value, child: child),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 3,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header with category
              _buildHeader(mainColor),
              // Confidence badge
              _buildConfidenceBadge(confidenceColor),
              // Divider
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                height: 1,
                color: Colors.grey[300],
              ),
              // Details section - scrollable
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: _buildDetails(),
                ),
              ),
              // Disclaimer
              _buildDisclaimer(),
              // Buttons
              _buildButtons(mainColor),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color mainColor) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Category indicator
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: mainColor.withOpacity(0.15),
              border: Border.all(color: mainColor, width: 2),
            ),
            child: Icon(_getCategoryIcon(), color: mainColor, size: 26),
          ),
          const SizedBox(width: 16),
          // Category text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Report Category',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.report.category,
                  style: TextStyle(
                    color: mainColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Severity indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: mainColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getSeverityLabel(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'level',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceBadge(Color confidenceColor) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [confidenceColor.withOpacity(0.1), Colors.transparent],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: confidenceColor.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user, color: confidenceColor, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Community Confidence',
                  style: TextStyle(color: Colors.grey[700], fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  _getConfidenceText(),
                  style: TextStyle(
                    color: confidenceColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          // Confidence level badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: confidenceColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${(widget.report.confidenceScore * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails() {
    final location =
        '${widget.report.latitude.toStringAsFixed(5)}, ${widget.report.longitude.toStringAsFixed(5)}';
    final timeAgo = _formatTimeAgo(widget.report.timestamp);
    final description = widget.report.description ?? 'No description provided';
    final trustScore = widget.report.trustScore ?? 0.0;
    final trustScoreText = '${(trustScore * 100).toInt()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Time
        _buildDetailItem(
          icon: Icons.access_time,
          label: 'Reported',
          value: timeAgo,
          valueColor: Colors.black87,
        ),
        const SizedBox(height: 16),
        // Location
        _buildDetailItem(
          icon: Icons.location_on,
          label: 'Location',
          value: location,
          valueColor: Colors.black87,
        ),
        const SizedBox(height: 16),
        // Description
        _buildDetailItem(
          icon: Icons.description,
          label: 'Description',
          value: description,
          valueColor: Colors.black87,
        ),
        const SizedBox(height: 16),
        // Trust score
        _buildDetailItem(
          icon: Icons.trending_up,
          label: 'Trust score',
          value: trustScoreText,
          valueColor: Colors.black87,
        ),
      ],
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: Colors.grey[700]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDisclaimer() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.info, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This report represents a community member\'s experience. Verify before acting.',
              style: TextStyle(color: Colors.blue[800], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(Color mainColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // View nearby reports button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ReportListScreen(
                      pulseLat: widget.report.latitude,
                      pulseLng: widget.report.longitude,
                      radius: 500, // 500m radius for individual reports
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.map, size: 20),
              label: const Text(
                'View nearby reports',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: mainColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Close button
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                _controller.reverse().then((_) {
                  widget.onClose();
                });
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                'Close',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon() {
    switch (widget.report.level) {
      case SafetyLevel.safe:
        return Icons.check_circle;
      case SafetyLevel.caution:
        return Icons.warning;
      case SafetyLevel.moderate:
        return Icons.info;
      case SafetyLevel.unsafe:
        return Icons.error;
    }
  }

  String _getSeverityLabel() {
    switch (widget.report.level) {
      case SafetyLevel.safe:
        return 'Safe';
      case SafetyLevel.caution:
        return 'Caution';
      case SafetyLevel.moderate:
        return 'Moderate';
      case SafetyLevel.unsafe:
        return 'Unsafe';
    }
  }

  Color _getConfidenceColor() {
    final score = widget.report.confidenceScore;
    if (score >= 0.7) return Colors.green;
    if (score >= 0.4) return Colors.orange;
    return Colors.red;
  }

  String _getConfidenceText() {
    final score = widget.report.confidenceScore;
    if (score >= 0.7) return 'HIGH';
    if (score >= 0.4) return 'MEDIUM';
    return 'LOW';
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now().toUtc();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} hours ago';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${difference.inDays ~/ 7} weeks ago';
  }
}

/// Show report bottom sheet
Future<void> showReportDetails({
  required BuildContext context,
  required SafetyReport report,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ReportBottomSheet(
      report: report,
      onClose: () => Navigator.of(context).pop(),
    ),
  );
}
