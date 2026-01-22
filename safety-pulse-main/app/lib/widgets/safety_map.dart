import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/safety.dart';
import '../utils/safety_utils.dart';
import '../providers/safety_provider.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'pulse_visualization.dart';
import 'pulse_bottom_sheet.dart';

/// Zoom threshold for showing individual reports
const double kZoomShowIndividual = 14.0;

/// Safety Map Widget
///
/// Main map component for displaying safety pulses.
/// Uses CircleLayer for proper flutter_map coordinate integration.
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

class _SafetyMapState extends State<SafetyMap> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  bool _showDisclaimer = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(SafetyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.center != null && oldWidget.center != widget.center) {
      _mapController.move(widget.center!, 13.0);
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
            onLongPress: (_, point) => _handleLongPress(point),
            onPositionChanged: (position, hasGesture) {
              if (hasGesture) {
                safetyProvider.setZoomLevel(position.zoom ?? 13.0);
              }
            },
          ),
          children: [
            // Dark muted base map
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c'],
              retinaMode: RetinaMode.isHighDensity(context),
            ),

            // ============ PULSE LAYER (Primary) ============
            // Render pulses using CircleLayer for proper flutter_map integration
            CircleLayer(
              circles: visiblePulses.map((pulse) {
                final color = SafetyColors.forIntensity(pulse.intensity);
                final opacity = pulse.displayOpacity;

                return CircleMarker(
                  point: LatLng(pulse.lat, pulse.lng),
                  radius: pulse.radius.toDouble(),
                  useRadiusInMeter: true,
                  color: color.withOpacity(opacity * 0.6),
                  borderColor: color.withOpacity(opacity * 0.8),
                  borderStrokeWidth: 2,
                );
              }).toList(),
            ),

            // ============ TAPPABLE PULSE MARKERS ============
            // Invisible tap targets on top of pulses for better tap detection
            MarkerLayer(
              markers: visiblePulses.map((pulse) {
                return Marker(
                  point: LatLng(pulse.lat, pulse.lng),
                  width: pulse.radius * 2,
                  height: pulse.radius * 2,
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: () => _showPulseDetails(pulse),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            // ============ ANIMATED PULSE OVERLAY ============
            // Add subtle breathing animation on top
            AnimatedPulseLayer(
              pulses: visiblePulses,
              onPulseTap: _showPulseDetails,
            ),

            // ============ INDIVIDUAL REPORTS (Only at deep zoom) ============
            if (showIndividualReports && visibleReports.isNotEmpty)
              MarkerLayer(
                markers: visibleReports.map((report) {
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
                          border: Border.all(
                            color: Color(colors['main']!),
                            width: 2,
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

        // ============ LEGEND ============
        Positioned(bottom: 16, left: 16, child: _buildLegend()),

        // ============ ZOOM INFO ============
        Positioned(
          bottom: 16,
          right: 16,
          child: _buildZoomInfo(currentZoom, showIndividualReports),
        ),
      ],
    );
  }

  void _handleLongPress(LatLng point) {
    // Show quick report options on long press
    _showQuickReportSheet(point.latitude, point.longitude);
  }

  void _showQuickReportSheet(double lat, double lng) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _QuickReportSheet(
        lat: lat,
        lng: lng,
        onSubmit: (category, severity) {
          Navigator.of(context).pop();
          // Navigate to full report form
          _showReportDialog(lat, lng, preselectedCategory: category);
        },
      ),
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
                  'Safety Pulses show aggregated community sentiment.',
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
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          _buildLegendItem('Calm', SafetyColors.safe),
          _buildLegendItem('Moderate', SafetyColors.caution),
          _buildLegendItem('Concern', SafetyColors.moderate),
          _buildLegendItem('Unsafe', SafetyColors.unsafe),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomInfo(double zoom, bool showIndividual) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        showIndividual
            ? 'Zoom: ${zoom.toStringAsFixed(1)} • Individual'
            : 'Zoom: ${zoom.toStringAsFixed(1)}',
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
    );
  }

  void _showPulseDetails(Pulse pulse) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PulseBottomSheet(
        pulse: pulse,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _showReportDetails(SafetyReport report) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReportBottomSheet(
        report: report,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _showReportDialog(
    double lat,
    double lng, {
    String? preselectedCategory,
  }) {
    showDialog(
      context: context,
      builder: (context) => ReportDialog(
        lat: lat,
        lng: lng,
        preselectedCategory: preselectedCategory,
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
        color = Colors.yellow[700]!;
        icon = Icons.warning;
        break;
      case SafetyLevel.moderate:
        color = Colors.orange;
        icon = Icons.info;
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
      case SafetyLevel.moderate:
        return 'Moderate';
      case SafetyLevel.unsafe:
        return 'Unsafe';
    }
  }

  String _getConfidenceText(double score) {
    if (score >= 0.7) return 'HIGH';
    if (score >= 0.4) return 'MEDIUM';
    return 'LOW';
  }
}

/// Quick Report Sheet - shown on long press
class _QuickReportSheet extends StatelessWidget {
  final double lat;
  final double lng;
  final Function(String category, int severity) onSubmit;

  const _QuickReportSheet({
    required this.lat,
    required this.lng,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.add_location_alt, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Quick Report',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'Tap to report at this location',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildQuickButton(
                      'Followed',
                      Icons.visibility,
                      Colors.red[700]!,
                      'followed',
                      5,
                    ),
                    _buildQuickButton(
                      'Harassment',
                      Icons.block,
                      Colors.deepOrange,
                      'harassment',
                      5,
                    ),
                    _buildQuickButton(
                      'Suspicious',
                      Icons.warning,
                      Colors.orange,
                      'suspicious-activity',
                      4,
                    ),
                    _buildQuickButton(
                      'Unsafe feel',
                      Icons.info,
                      Colors.yellow[700]!,
                      'felt-unsafe',
                      3,
                    ),
                    _buildQuickButton(
                      'Poor lighting',
                      Icons.lightbulb,
                      Colors.grey,
                      'poor-lighting',
                      2,
                    ),
                    _buildQuickButton(
                      'Feels safe',
                      Icons.check_circle,
                      Colors.green,
                      'safe-area',
                      1,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Long press anywhere on the map to report',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildQuickButton(
    String label,
    IconData icon,
    Color color,
    String category,
    int severity,
  ) {
    return InkWell(
      onTap: () => onSubmit(category, severity),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Report Dialog - step-based form
class ReportDialog extends StatefulWidget {
  final double lat;
  final double lng;
  final String? preselectedCategory;

  const ReportDialog({
    super.key,
    required this.lat,
    required this.lng,
    this.preselectedCategory,
  });

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  int _currentStep = 0;
  int _severity = 3;
  String _selectedCategory = 'felt-unsafe';
  final TextEditingController _descriptionController = TextEditingController();

  final Map<String, int> _categorySeverity = {
    'felt-unsafe': 3,
    'followed': 5,
    'poor-lighting': 2,
    'suspicious-activity': 4,
    'harassment': 5,
    'safe-area': 1,
  };

  @override
  void initState() {
    super.initState();
    if (widget.preselectedCategory != null) {
      _selectedCategory = widget.preselectedCategory!;
      _severity = _categorySeverity[_selectedCategory] ?? 3;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step indicator
              _buildStepIndicator(),
              const SizedBox(height: 24),

              // Step content
              if (_currentStep == 0) _buildStep1_Severity(),
              if (_currentStep == 1) _buildStep2_Category(),
              if (_currentStep == 2) _buildStep3_Description(),

              const SizedBox(height: 24),

              // Navigation buttons
              _buildNavigationButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final isActive = index <= _currentStep;
        return Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isActive ? Colors.blue : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.grey[600],
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            if (index < 2)
              Container(
                width: 40,
                height: 2,
                color: index < _currentStep ? Colors.blue : Colors.grey[300],
              ),
          ],
        );
      }),
    );
  }

  Widget _buildStep1_Severity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How did this place feel?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Slide to indicate the intensity of your feeling',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            _getSeverityLabel(_severity),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _getSeverityColor(_severity),
            ),
          ),
        ),
        Slider(
          value: _severity.toDouble(),
          min: 1,
          max: 5,
          divisions: 4,
          activeColor: _getSeverityColor(_severity),
          onChanged: (value) {
            setState(() {
              _severity = value.toInt();
            });
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('Safe', style: TextStyle(fontSize: 12, color: Colors.green)),
            Text('Unsafe', style: TextStyle(fontSize: 12, color: Colors.red)),
          ],
        ),
      ],
    );
  }

  Widget _buildStep2_Category() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What was the concern?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Select the most relevant option',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
        const SizedBox(height: 16),
        ...reportCategories.map((cat) {
          final isSelected = _selectedCategory == cat['id'];
          final level = cat['level'] as SafetyLevel;
          final color = Color(safetyColors[level]!['main']!);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedCategory = cat['id'] as String;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withOpacity(0.15)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? color : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      cat['icon'] as String,
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        cat['label'] as String,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected ? color : Colors.black,
                        ),
                      ),
                    ),
                    if (isSelected) Icon(Icons.check_circle, color: color),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStep3_Description() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Additional details',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Optional: Help others understand (200 chars max)',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _descriptionController,
          maxLines: 3,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: 'Brief description...',
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your report is anonymous. Be respectful and focused on feelings, not accusations.',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    return Row(
      children: [
        if (_currentStep > 0)
          Expanded(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _currentStep--;
                });
              },
              child: const Text('Back'),
            ),
          ),
        if (_currentStep > 0) const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _currentStep < 2
                ? () {
                    setState(() {
                      _currentStep++;
                    });
                  }
                : _submitReport,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _currentStep < 2 ? 'Continue' : 'Submit Report',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  void _submitReport() {
    final authProvider = context.read<AuthProvider>();
    final token = authProvider.token;

    if (token == null) return;

    final report = SafetyReport(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      latitude: widget.lat,
      longitude: widget.lng,
      level: _severityToLevel(_severity),
      category: _getCategoryLabel(_selectedCategory),
      description: _descriptionController.text.isEmpty
          ? null
          : _descriptionController.text,
      timestamp: DateTime.now(),
      opacity: 1.0,
    );

    context.read<SafetyProvider>().addReport(report, token: token);

    Navigator.of(context).pop();

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text('Report submitted! Thank you for contributing.'),
          ],
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  SafetyLevel _severityToLevel(int severity) {
    if (severity >= 4) return SafetyLevel.unsafe;
    if (severity >= 2) return SafetyLevel.caution;
    return SafetyLevel.safe;
  }

  String _getCategoryLabel(String categoryId) {
    return reportCategories.firstWhere(
          (cat) => cat['id'] == categoryId,
          orElse: () => {'label': 'Felt unsafe here'},
        )['label']
        as String;
  }

  Color _getSeverityColor(int severity) {
    switch (severity) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.yellow[700]!;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.deepOrange;
      case 5:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getSeverityLabel(int severity) {
    switch (severity) {
      case 1:
        return 'Safe';
      case 2:
        return 'Mild Concern';
      case 3:
        return 'Concerning';
      case 4:
        return 'Unsafe';
      case 5:
        return 'Dangerous';
      default:
        return '';
    }
  }
}

/// Animated Pulse Layer - adds breathing effect
class AnimatedPulseLayer extends StatefulWidget {
  final List<Pulse> pulses;
  final Function(Pulse) onPulseTap;

  const AnimatedPulseLayer({
    super.key,
    required this.pulses,
    required this.onPulseTap,
  });

  @override
  State<AnimatedPulseLayer> createState() => _AnimatedPulseLayerState();
}

class _AnimatedPulseLayerState extends State<AnimatedPulseLayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;

        return Stack(
          children: widget.pulses.map((pulse) {
            // Breathing effect
            final breatheScale = 1.0 + (progress * 0.15);
            final breatheOpacity = 0.3 + (0.4 * (1 - (progress * 0.5)));
            final color = SafetyColors.forIntensity(pulse.intensity);

            return Positioned(
              left: pulse.lng - (pulse.radius * breatheScale / 111000),
              top: pulse.lat - (pulse.radius * breatheScale / 111000),
              child: GestureDetector(
                onTap: () => widget.onPulseTap(pulse),
                child: Opacity(
                  opacity: breatheOpacity * pulse.displayOpacity,
                  child: Container(
                    width: (pulse.radius * breatheScale / 111000) * 2,
                    height: (pulse.radius * breatheScale / 111000) * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
