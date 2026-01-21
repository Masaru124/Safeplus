import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/safety.dart';

/// Animated Pulse Widget for Safety Pulse Map
///
/// Creates expanding ring animations around high-risk areas
/// to visualize the "live heartbeat" of neighborhood safety
/// Uses the new Pulse model as the single source of truth
class PulseCircleMarker extends StatefulWidget {
  final Pulse pulse;
  final VoidCallback? onTap;

  const PulseCircleMarker({super.key, required this.pulse, this.onTap});

  @override
  State<PulseCircleMarker> createState() => _PulseCircleMarkerState();
}

class _PulseCircleMarkerState extends State<PulseCircleMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    // Animation duration based on pulse intensity (stronger = faster)
    final duration = widget.pulse.animationDuration;

    _controller = AnimationController(duration: duration, vsync: this)
      ..repeat();

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
  }

  @override
  void didUpdateWidget(PulseCircleMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse.intensity != oldWidget.pulse.intensity) {
      // Update animation duration when intensity changes
      _controller.duration = widget.pulse.animationDuration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final intensity = widget.pulse.intensity;
    final color = Color(widget.pulse.colorHex);
    final opacity = widget.pulse.displayOpacity;
    final radiusMeters = widget.pulse.radius.toDouble();

    // Convert meters to approximate degrees for the map
    // This is an approximation: 1 degree ≈ 111km at equator
    final radiusDegrees = radiusMeters / 111000;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final progress = _animation.value;

        // Breathing effect: slight radius expansion
        final currentRadius = radiusDegrees * (1 + progress * 0.2);

        // Breathing effect: fading opacity
        final currentOpacity = opacity * (1 - progress * 0.5);

        // Outer ring (expanding and fading)
        final outerOpacity = (1 - progress) * currentOpacity * 0.5;

        return Stack(
          children: [
            // Outer breathing ring
            Positioned(
              left: widget.pulse.lng - currentRadius,
              top: widget.pulse.lat - currentRadius,
              child: Container(
                width: currentRadius * 2,
                height: currentRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(outerOpacity),
                ),
              ),
            ),

            // Inner circle (base pulse)
            Positioned(
              left: widget.pulse.lng - radiusDegrees,
              top: widget.pulse.lat - radiusDegrees,
              child: GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  width: radiusDegrees * 2,
                  height: radiusDegrees * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(currentOpacity * 0.7),
                    border: Border.all(
                      color: color,
                      width:
                          2 +
                          (intensity *
                              2), // Thicker border for higher intensity
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2 * intensity,
                      ),
                    ],
                  ),
                  child: Center(child: _buildPulseContent(color)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPulseContent(Color color) {
    // Show intensity score for stronger pulses
    if (widget.pulse.intensity >= 0.3) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${(widget.pulse.intensity * 100).toInt()}',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12 + (widget.pulse.intensity * 8),
              shadows: [
                Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 2),
              ],
            ),
          ),
          if (widget.pulse.confidence == 'HIGH')
            Icon(
              Icons.verified,
              color: Colors.white.withOpacity(0.8),
              size: 10,
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

/// Pulse Cluster Layer for rendering multiple pulses
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

/// Heatmap-style pulse overlay
class PulseHeatmapLayer extends StatelessWidget {
  final List<Pulse> pulses;
  final double opacity;

  const PulseHeatmapLayer({
    super.key,
    required this.pulses,
    this.opacity = 0.6,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: pulses.map((pulse) {
        return _HeatmapTile(pulse: pulse, opacity: opacity);
      }).toList(),
    );
  }
}

/// Individual heatmap tile
class _HeatmapTile extends StatelessWidget {
  final Pulse pulse;
  final double opacity;

  const _HeatmapTile({required this.pulse, required this.opacity});

  @override
  Widget build(BuildContext context) {
    final color = _getHeatmapColor(pulse.intensity);
    final radiusDegrees = pulse.radius / 111000;

    return Positioned(
      left: pulse.lng - radiusDegrees,
      top: pulse.lat - radiusDegrees,
      child: Container(
        width: radiusDegrees * 2,
        height: radiusDegrees * 2,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              color.withOpacity(opacity * pulse.intensity),
              color.withOpacity(opacity * pulse.intensity * 0.5),
              color.withOpacity(0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Color _getHeatmapColor(double intensity) {
    if (intensity < 0.3) return Colors.green;
    if (intensity < 0.5) return Colors.yellow;
    if (intensity < 0.7) return Colors.orange;
    return Colors.red;
  }
}

/// Pulse info badge showing confidence and dominant reason
class PulseInfoBadge extends StatelessWidget {
  final Pulse pulse;

  const PulseInfoBadge({super.key, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final color = Color(pulse.colorHex);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Intensity score
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                pulse.safetyLevel == SafetyLevel.unsafe
                    ? Icons.warning
                    : pulse.safetyLevel == SafetyLevel.caution
                    ? Icons.info
                    : Icons.check_circle,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Risk Level: ${(pulse.intensity * 100).toInt()}%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Confidence level
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people, size: 16, color: Colors.white70),
              const SizedBox(width: 4),
              Text(
                pulse.confidenceDisplay,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),

          // Dominant reason
          if (pulse.dominantReason != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.white70),
                const SizedBox(width: 4),
                Text(
                  'Primary: ${pulse.dominantReason}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],

          // Last updated
          const SizedBox(height: 4),
          Text(
            'Updated: ${_formatTimeAgo(pulse.lastUpdated)}',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
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

/// Animated Pulse Cluster for the map
class PulseClusterMarker extends StatefulWidget {
  final LatLng position;
  final int reportCount;
  final double avgIntensity;
  final bool isSpike;
  final VoidCallback onTap;

  const PulseClusterMarker({
    super.key,
    required this.position,
    required this.reportCount,
    required this.avgIntensity,
    required this.isSpike,
    required this.onTap,
  });

  @override
  State<PulseClusterMarker> createState() => _PulseClusterMarkerState();
}

class _PulseClusterMarkerState extends State<PulseClusterMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.isSpike
          ? const Duration(milliseconds: 500)
          : const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _pulseAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(PulseClusterMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpike != oldWidget.isSpike) {
      _controller.duration = widget.isSpike
          ? const Duration(milliseconds: 500)
          : const Duration(seconds: 2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColorForScore(widget.avgIntensity);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulseScale = 1 + _pulseAnimation.value * 0.2;
        final pulseOpacity = 1 - _pulseAnimation.value;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulse ring (only visible when spike)
            if (widget.isSpike)
              Container(
                width: 60 * pulseScale,
                height: 60 * pulseScale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(pulseOpacity * 0.3),
                ),
              ),
            // Main marker
            Transform.scale(
              scale: _scaleAnimation.value,
              child: GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.reportCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        if (widget.isSpike)
                          const Icon(
                            Icons.warning,
                            color: Colors.white,
                            size: 12,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Color _getColorForScore(double score) {
    if (score < 0.3) return Colors.green;
    if (score < 0.5) return Colors.yellow;
    if (score < 0.7) return Colors.orange;
    return Colors.red;
  }
}

/// Legend for the safety heatmap
class SafetyHeatmapLegend extends StatelessWidget {
  const SafetyHeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) {
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
            'Safety Score',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildLegendItem('Safe', Colors.green),
          _buildLegendItem('Caution', Colors.yellow),
          _buildLegendItem('Moderate', Colors.orange),
          _buildLegendItem('Unsafe', Colors.red),
          const SizedBox(height: 8),
          Row(
            children: const [
              Icon(Icons.warning, size: 12, color: Colors.red),
              SizedBox(width: 4),
              Text(
                'Active Spike',
                style: TextStyle(color: Colors.white, fontSize: 12),
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
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
