import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/safety.dart';
import '../utils/safety_utils.dart';
import '../providers/safety_provider.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'pulse_visualization.dart';

/// Zoom threshold for showing individual reports
const double kZoomShowIndividual = 14.0;

class SafetyMap extends StatefulWidget {
  final List<SafetyReport> reports;
  final Function(double, double) onMapTap;
  final LatLng? center;

  const SafetyMap({
    super.key,
    required this.reports,
    required this.onMapTap,
    this.center,
  });

  @override
  State<SafetyMap> createState() => _SafetyMapState();
}

class _SafetyMapState extends State<SafetyMap> {
  final MapController _mapController = MapController();
  bool _showDisclaimer = true;

  @override
  void didUpdateWidget(SafetyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.center != null && oldWidget.center != widget.center) {
      _mapController.move(widget.center!, 13.0);
    }
  }

  void _showReportDetails(SafetyReport report) {
    final authProvider = context.read<AuthProvider>();
    final isOwner = report.isOwnedBy(authProvider.userId);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(report.category),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Location
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${report.latitude.toStringAsFixed(5)}, ${report.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Safety Level
              Row(
                children: [
                  _getSeverityIcon(report.level),
                  const SizedBox(width: 4),
                  Text(_getSeverityText(report.level)),
                ],
              ),
              const SizedBox(height: 8),
              // Time
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    getTimeAgo(report.timestamp),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Reporter
              if (report.reporterUsername != null) ...[
                Row(
                  children: [
                    const Icon(Icons.person, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      'Reported by: ${report.reporterUsername}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              // Trust Score (shown as confidence, not raw numbers)
              Row(
                children: [
                  const Icon(Icons.verified_user, size: 16, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    'Community confidence: ${_getConfidenceText(report.confidenceScore)}',
                    style: const TextStyle(color: Colors.blue),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Vote info (anonymized)
              Row(
                children: [
                  const Icon(Icons.how_to_vote, size: 16, color: Colors.purple),
                  const SizedBox(width: 4),
                  Text(
                    _getVoteStatus(report.trueVotes, report.falseVotes),
                    style: const TextStyle(color: Colors.purple),
                  ),
                ],
              ),
              // Description
              if (report.description != null &&
                  report.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 4),
                const Text(
                  'Description:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(report.description!),
              ],
              // Voting Section
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Is this report accurate?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      final safetyProvider = context.read<SafetyProvider>();
                      final authProvider = context.read<AuthProvider>();
                      final token = authProvider.token;
                      if (token != null) {
                        safetyProvider.voteOnReport(
                          signalId: report.id,
                          isTrue: true,
                          token: token,
                        );
                        Navigator.of(context).pop();
                        if (mounted) {
                          final updatedReport = safetyProvider.reports
                              .firstWhere(
                                (r) => r.id == report.id,
                                orElse: () => report,
                              );
                          _showReportDetails(updatedReport);
                        }
                      }
                    },
                    icon: const Icon(Icons.thumb_up, size: 18),
                    label: const Text('Accurate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: report.userVote == true
                          ? Colors.green
                          : Colors.grey[200],
                      foregroundColor: report.userVote == true
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final safetyProvider = context.read<SafetyProvider>();
                      final authProvider = context.read<AuthProvider>();
                      final token = authProvider.token;
                      if (token != null) {
                        safetyProvider.voteOnReport(
                          signalId: report.id,
                          isTrue: false,
                          token: token,
                        );
                        Navigator.of(context).pop();
                        if (mounted) {
                          final updatedReport = safetyProvider.reports
                              .firstWhere(
                                (r) => r.id == report.id,
                                orElse: () => report,
                              );
                          _showReportDetails(updatedReport);
                        }
                      }
                    },
                    icon: const Icon(Icons.thumb_down, size: 18),
                    label: const Text('Inaccurate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: report.userVote == false
                          ? Colors.red
                          : Colors.grey[200],
                      foregroundColor: report.userVote == false
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                ],
              ),
              if (report.hasUserVoted) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    final safetyProvider = context.read<SafetyProvider>();
                    final authProvider = context.read<AuthProvider>();
                    final token = authProvider.token;
                    if (token != null) {
                      safetyProvider.removeVote(
                        signalId: report.id,
                        token: token,
                      );
                      Navigator.of(context).pop();
                      if (mounted) {
                        final updatedReport = safetyProvider.reports.firstWhere(
                          (r) => r.id == report.id,
                          orElse: () => report,
                        );
                        _showReportDetails(updatedReport);
                      }
                    }
                  },
                  child: const Text(
                    'Remove my vote',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
              if (isOwner) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Report'),
                        content: const Text(
                          'Are you sure you want to delete this report? This action cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && mounted) {
                      final safetyProvider = context.read<SafetyProvider>();
                      final authProvider = context.read<AuthProvider>();
                      final token = authProvider.token;

                      if (token != null) {
                        final success = await safetyProvider.deleteReport(
                          signalId: report.id,
                          token: token,
                        );

                        Navigator.of(context).pop();

                        if (success && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Report deleted successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      }
                    }
                  },
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text(
                    'Delete my report',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _getConfidenceText(double score) {
    if (score >= 0.7) return 'HIGH';
    if (score >= 0.4) return 'MEDIUM';
    return 'LOW';
  }

  String _getVoteStatus(int trueVotes, int falseVotes) {
    final total = trueVotes + falseVotes;
    if (total == 0) return 'Not yet verified by community';
    if (total < 3) return 'Being verified ($total votes)';
    if (total < 10) return 'Growing verification ($total votes)';
    return 'Established trust ($total verified)';
  }

  Widget _getSeverityIcon(SafetyLevel level) {
    Color color;
    IconData icon;
    switch (level) {
      case SafetyLevel.safe:
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case SafetyLevel.caution:
        color = Colors.orange;
        icon = Icons.warning;
        break;
      case SafetyLevel.unsafe:
        color = Colors.red;
        icon = Icons.error;
        break;
    }
    return Icon(icon, color: color, size: 20);
  }

  String _getSeverityText(SafetyLevel level) {
    switch (level) {
      case SafetyLevel.safe:
        return 'Safe';
      case SafetyLevel.caution:
        return 'Caution';
      case SafetyLevel.unsafe:
        return 'Unsafe';
    }
  }

  @override
  Widget build(BuildContext context) {
    final safetyProvider = context.watch<SafetyProvider>();
    final currentZoom = safetyProvider.currentZoom;
    final showIndividualReports = currentZoom >= kZoomShowIndividual;
    final visiblePulses = safetyProvider.visiblePulses;
    final visibleReports = safetyProvider.visibleReports;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.center ?? const LatLng(40.7484, -73.9857),
            initialZoom: 13.0,
            onTap: (_, point) =>
                widget.onMapTap(point.latitude, point.longitude),
            onPositionChanged: (position, hasGesture) {
              if (hasGesture) {
                safetyProvider.setZoomLevel(position.zoom ?? 13.0);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c'],
              retinaMode: RetinaMode.isHighDensity(context),
            ),

            // ============ PULSE LAYER (Primary) ============
            // Always show pulses - this is the single source of truth for map rendering
            PulseClusterLayer(
              pulses: visiblePulses,
              onPulseTap: (pulse) => _showPulseDetails(pulse),
            ),

            // ============ INDIVIDUAL REPORTS (Only at deep zoom) ============
            // Only show individual report markers at zoom level 14+
            if (showIndividualReports)
              MarkerLayer(
                markers: visibleReports.map((report) {
                  final colors = safetyColors[report.level]!;
                  return Marker(
                    point: LatLng(report.latitude, report.longitude),
                    child: GestureDetector(
                      onTap: () => _showReportDetails(report),
                      child: Stack(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color(
                                colors['main']!,
                              ).withOpacity(report.opacity * 0.7),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Color(colors['main']!),
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                report.category[0],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          if (report.hasUserVoted)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: report.userVote == true
                                      ? Colors.green
                                      : Colors.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  report.userVote == true
                                      ? Icons.thumb_up
                                      : Icons.thumb_down,
                                  size: 8,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),

        // ============ DISCLAIMER BANNER ============
        if (_showDisclaimer)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _buildDisclaimerBanner(),
          ),

        // ============ ZOOM INFO ============
        Positioned(
          bottom: 16,
          left: 16,
          child: _buildZoomInfo(currentZoom, showIndividualReports),
        ),

        // ============ LEGEND ============
        Positioned(bottom: 16, right: 16, child: _buildLegend()),
      ],
    );
  }

  Widget _buildDisclaimerBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.info, color: Colors.blue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Community-reported feelings, not crime data',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Safety Pulses show aggregated community sentiment, '
                  'not verified incidents.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            onPressed: () {
              setState(() {
                _showDisclaimer = false;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildZoomInfo(double zoom, bool showIndividual) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                showIndividual ? Icons.visibility : Icons.visibility_off,
                color: Colors.white70,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                'Zoom: ${zoom.toStringAsFixed(1)}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            showIndividual
                ? 'Showing individual reports'
                : 'Showing aggregated pulses',
            style: TextStyle(
              color: Colors.white70.withOpacity(0.7),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Safety Level',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendItem('Safe', Colors.green),
          _buildLegendItem('Caution', Colors.yellow),
          _buildLegendItem('Unsafe', Colors.red),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.people, size: 12, color: Colors.blue),
              SizedBox(width: 4),
              Text(
                'High confidence',
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ],
    );
  }

  void _showPulseDetails(Pulse pulse) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              pulse.safetyLevel == SafetyLevel.unsafe
                  ? Icons.warning
                  : pulse.safetyLevel == SafetyLevel.caution
                  ? Icons.info
                  : Icons.check_circle,
              color: Color(pulse.colorHex),
            ),
            const SizedBox(width: 8),
            Text(pulse.dominantReason ?? 'Safety Pulse'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Risk Level
            Row(
              children: [
                const Icon(Icons.speed, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Risk Level: ${(pulse.intensity * 100).toInt()}%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Confidence
            Row(
              children: [
                const Icon(Icons.people, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  pulse.confidenceDisplay,
                  style: const TextStyle(color: Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Location
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  '${pulse.lat.toStringAsFixed(5)}, ${pulse.lng.toStringAsFixed(5)}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Last Updated
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Updated: ${_formatTimeAgo(pulse.lastUpdated)}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const Text(
              'This pulse represents aggregated community reports. '
              'Individual reports are not shown to protect reporter privacy.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now().toUtc();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}

/// Pulse Cluster Layer for rendering pulses on the map
class PulseClusterLayer extends StatelessWidget {
  final List<Pulse> pulses;
  final Function(Pulse) onPulseTap;

  const PulseClusterLayer({
    super.key,
    required this.pulses,
    required this.onPulseTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: pulses.map((pulse) {
        return PulseCircleMarker(pulse: pulse, onTap: () => onPulseTap(pulse));
      }).toList(),
    );
  }
}
