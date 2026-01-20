import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/safety.dart';
import '../utils/safety_utils.dart';
import '../providers/safety_provider.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';

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

  @override
  void didUpdateWidget(SafetyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Move map when center changes
    if (widget.center != null && oldWidget.center != widget.center) {
      _mapController.move(widget.center!, 13.0);
    }
  }

  void _showReportDetails(SafetyReport report) {
    // Get auth provider for ownership check
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
              // Trust Score
              Row(
                children: [
                  const Icon(Icons.verified_user, size: 16, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    'Trust Score: ${((report.trustScore ?? 0.5) * 100).toInt()}%',
                    style: const TextStyle(color: Colors.blue),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Vote Counts
              Row(
                children: [
                  const Icon(Icons.how_to_vote, size: 16, color: Colors.purple),
                  const SizedBox(width: 4),
                  Text(
                    'Votes: ${report.trueVotes} true, ${report.falseVotes} false',
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
                  // True Vote Button
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
                    label: const Text('True'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: report.userVote == true
                          ? Colors.green
                          : Colors.grey[200],
                      foregroundColor: report.userVote == true
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                  // False Vote Button
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
                    label: const Text('False'),
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
              // Remove vote button if user has voted
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
              // Delete report button (only for owner)
              if (isOwner) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    // Confirm deletion
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
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.center ?? const LatLng(40.7484, -73.9857),
        initialZoom: 13.0,
        onTap: (_, point) => widget.onMapTap(point.latitude, point.longitude),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c'],
          retinaMode: RetinaMode.isHighDensity(context),
        ),
        MarkerLayer(
          markers: widget.reports.map((report) {
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
                    // Show vote indicator if user has voted
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
                            border: Border.all(color: Colors.white, width: 1),
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
    );
  }
}
