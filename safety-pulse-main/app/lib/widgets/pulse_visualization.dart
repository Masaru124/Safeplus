import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/safety.dart';

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
    final color = SafetyColors.forIntensity(pulse.intensity);
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
}

/// Pulse info badge showing confidence and dominant reason
class PulseInfoBadge extends StatelessWidget {
  final Pulse pulse;

  const PulseInfoBadge({super.key, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final color = SafetyColors.forIntensity(pulse.intensity);

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
    final color = SafetyColors.forIntensity(widget.avgIntensity);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulseScale = 1 + _pulseAnimation.value * 0.2;
        final pulseOpacity = 1 - _pulseAnimation.value;

        return Stack(
          alignment: Alignment.center,
          children: [
            if (widget.isSpike)
              Container(
                width: 60 * pulseScale,
                height: 60 * pulseScale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(pulseOpacity * 0.3),
                ),
              ),
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
          _buildLegendItem('Calm', SafetyColors.safe),
          _buildLegendItem('Moderate', SafetyColors.caution),
          _buildLegendItem('Concern', SafetyColors.moderate),
          _buildLegendItem('Unsafe', SafetyColors.unsafe),
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
