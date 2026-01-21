import 'dart:async';
import 'package:flutter/material.dart';

/// Spike Glow Overlay Widget
///
/// Shows an animated glow effect when a safety spike is detected
class SpikeGlowOverlay extends StatefulWidget {
  final bool isActive;
  final String message;
  final VoidCallback? onDismiss;
  final Color glowColor;
  final double glowIntensity;

  const SpikeGlowOverlay({
    super.key,
    required this.isActive,
    this.message = '⚠️ Safety spike detected nearby',
    this.onDismiss,
    this.glowColor = Colors.red,
    this.glowIntensity = 0.8,
  });

  @override
  State<SpikeGlowOverlay> createState() => _SpikeGlowOverlayState();
}

class _SpikeGlowOverlayState extends State<SpikeGlowOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(SpikeGlowOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      // Start fade out when deactivated
      _controller.stop();
      _controller.forward();
    } else if (widget.isActive && !oldWidget.isActive) {
      // Restart animation when activated
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive && _fadeAnimation.value == 0.0) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            // Glow effect
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        widget.glowColor.withOpacity(
                          widget.glowIntensity * 0.3 * _pulseAnimation.value,
                        ),
                        widget.glowColor.withOpacity(0.0),
                      ],
                      stops: const [0.3, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // Alert banner
            Positioned(
              top: kToolbarHeight + 16,
              left: 16,
              right: 16,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                    CurvedAnimation(parent: _controller, curve: Curves.easeOut),
                  ),
                  child: _buildAlertBanner(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAlertBanner() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: widget.glowColor.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12.0),
          boxShadow: [
            BoxShadow(
              color: widget.glowColor.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          children: [
            // Animated warning icon
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: 0.8 + (_pulseAnimation.value - 0.5) * 0.4,
                  child: child,
                );
              },
              child: const Icon(
                Icons.warning_amber,
                color: Colors.white,
                size: 28.0,
              ),
            ),
            const SizedBox(width: 12.0),
            // Message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SAFETY SPIKE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.0,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    widget.message,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13.0,
                    ),
                  ),
                ],
              ),
            ),
            // Dismiss button
            if (widget.onDismiss != null)
              IconButton(
                onPressed: widget.onDismiss,
                icon: const Icon(Icons.close, color: Colors.white, size: 20.0),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pulse Animation Widget for Map Markers
///
/// Creates a pulsing ring effect around high-risk areas
class SpikePulseRing extends StatefulWidget {
  final Color color;
  final double size;
  final bool isActive;

  const SpikePulseRing({
    super.key,
    this.color = Colors.red,
    this.size = 100.0,
    this.isActive = true,
  });

  @override
  State<SpikePulseRing> createState() => _SpikePulseRingState();
}

class _SpikePulseRingState extends State<SpikePulseRing>
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
    if (!widget.isActive) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final scale = 0.5 + progress * 1.5;
        final opacity = 1.0 - progress;

        return Center(
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity * 0.6,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: widget.color, width: 3.0),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Animated pulse counter for spike indicators
class SpikeCounterBadge extends StatelessWidget {
  final int count;
  final double size;

  const SpikeCounterBadge({super.key, required this.count, this.size = 40.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18.0,
          ),
        ),
      ),
    );
  }
}
