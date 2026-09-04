import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/glass_theme.dart';

/// The "thinking" state: two counter-rotating pools of colored light in a
/// soft sphere, Siri-style. This is the one place the design spends its
/// motion budget.
class AuroraOrb extends StatefulWidget {
  final double size;
  final Color? colorA;
  final Color? colorB;
  final double glowBoost;

  const AuroraOrb({
    super.key,
    this.size = 56,
    this.colorA,
    this.colorB,
    this.glowBoost = 1.0,
  });

  @override
  State<AuroraOrb> createState() => _AuroraOrbState();
}

class _AuroraOrbState extends State<AuroraOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    final a = widget.colorA ?? p.accent;
    final b = widget.colorB ?? (p.isDark ? const Color(0xFFB84A9C) : const Color(0xFFE3B4F2));
    final animate = !MediaQuery.disableAnimationsOf(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = animate ? _controller.value * 2 * math.pi : 0.6;

        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: a.withValues(alpha: 0.35 * widget.glowBoost),
                blurRadius: widget.size * 0.55 * widget.glowBoost,
                spreadRadius: widget.size * 0.06 * widget.glowBoost,
              ),
            ],
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: p.bgBottom),
                Transform.rotate(
                  angle: t,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.4, -0.4),
                        radius: 1.1,
                        colors: [a, a.withValues(alpha: 0)],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: -t * 1.45,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.45, 0.45),
                        radius: 1.0,
                        colors: [b, b.withValues(alpha: 0)],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                ),
                // Inner glow so it reads as luminous, not flat.
                Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 0),
                      radius: 0.9,
                      colors: [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.8],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
