import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/safety.dart';
import '../utils/safety_utils.dart';

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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(report.category),
        content: Column(
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
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(
                      colors['main']!,
                    ).withOpacity(report.opacity * 0.7),
                    shape: BoxShape.circle,
                    border: Border.all(color: Color(colors['main']!), width: 3),
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
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
