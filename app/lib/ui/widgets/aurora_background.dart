import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/glass_theme.dart';

/// The living backdrop: a base gradient with three slow, drifting pools of
/// light. Everything glassy in the app refracts these.
///
/// Perf notes: the base gradient and each blob sit in RepaintBoundaries, and
/// blob motion is done with Transform.translate so the compositor moves the
/// cached gradient layers instead of repainting them every frame.
class AuroraBackground extends StatefulWidget {
  final Widget? child;

  const AuroraBackground({super.key, this.child});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 42),
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
    final animate = !MediaQuery.disableAnimationsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final shortest = math.min(w, h);

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = animate ? _controller.value * 2 * math.pi : 0.0;

            return Stack(
              fit: StackFit.expand,
              children: [
                // Static base gradient, painted once.
                RepaintBoundary(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [p.bgTop, p.bgBottom],
                      ),
                    ),
                  ),
                ),
                for (final spec in p.blobs)
                  _buildBlob(spec, shortest, w, h, t),
                // A quiet top light so glass rims have something to catch.
                RepaintBoundary(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white
                                .withValues(alpha: p.isDark ? 0.04 : 0.30),
                            Colors.white.withValues(alpha: 0),
                          ],
                          stops: const [0.0, 0.4],
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.child != null) widget.child!,
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBlob(BlobSpec spec, double shortest, double w, double h,
      double t) {
    final phase = (math.sin(t + spec.phase) + 1) / 2;
    final size = shortest * spec.size;

    // Target alignment maps to a translation of the blob box inside the
    // stack, so the gradient itself never repaints.
    final a = Alignment(
      spec.base.x + (spec.drift.x - spec.base.x) * phase,
      spec.base.y + (spec.drift.y - spec.base.y) * phase,
    );
    final dx = (a.x + 1) / 2 * (w - size);
    final dy = (a.y + 1) / 2 * (h - size);

    return Transform.translate(
      offset: Offset(dx, dy),
      child: RepaintBoundary(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                spec.color.withValues(alpha: spec.opacity),
                spec.color.withValues(alpha: 0),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
