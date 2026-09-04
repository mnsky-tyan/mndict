import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/glass_theme.dart';

/// A liquid-glass pane.
///
/// By default the glass is *painted*: translucent fill, a specular gradient
/// ring that catches light on the lit corners, and a faint top sheen. Over
/// the soft aurora backdrop this is visually identical to a backdrop blur
/// and costs almost nothing — so persistent chrome (bars, cards) stays
/// painted and the app holds 60 fps while the background animates.
///
/// Pass [blur] > 0 only where content genuinely slides underneath and the
/// pane is temporary (drawer, modal sheet).
class GlassContainer extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;

  /// Legacy fill opacity override; negative = use the palette value.
  final double opacity;

  /// Use the extra-transparent chrome fill (floating bars).
  final bool chrome;

  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Widget? child;

  /// Legacy border override; null = the palette's specular ring.
  final BoxBorder? border;

  /// Backdrop blur sigma. 0 (default) = painted glass, no saveLayer.
  final double blur;

  /// Use the more opaque reading-surface fill instead of the chrome fill.
  final bool solid;

  /// Reading surface with translucent fill — the aurora glows through.
  final bool reading;

  /// Render the faint top sheen.
  final bool sheen;

  /// Render a bright specular line along the top rim (glossy highlight).
  final bool rim;

  const GlassContainer({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 24,
    this.opacity = -1,
    this.chrome = false,
    this.padding,
    this.margin,
    this.child,
    this.border,
    this.blur = 0,
    this.solid = false,
    this.reading = false,
    this.sheen = true,
    this.rim = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;

    Color baseFill;
    if (reading) {
      baseFill = p.readingFill;
    } else if (solid) {
      baseFill = p.solidFill;
    } else if (chrome) {
      baseFill = p.chromeFill;
    } else {
      baseFill = p.glassFill;
    }
    final fill =
        opacity >= 0 ? baseFill.withValues(alpha: opacity) : baseFill;

    final ring = border ??
        Border.all(
          color: Colors.transparent,
          width: 0,
        );

    final innerRadius = (borderRadius - 1.2).clamp(0.0, borderRadius);

    return Container(
      width: width,
      height: height,
      margin: margin,
      // The outer box paints the specular ring gradient; the 1.2px padding
      // leaves it visible around the pane.
      padding: border != null ? EdgeInsets.zero : const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: border != null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  p.borderStrong,
                  p.borderFaint,
                  p.borderFaint,
                  p.borderStrong.withValues(alpha: p.borderStrong.a * 0.55),
                ],
                stops: const [0.0, 0.35, 0.7, 1.0],
              ),
        color: border != null ? fill : null,
        border: border != null ? ring : null,
        boxShadow: [
          BoxShadow(
            color: p.shadow,
            blurRadius: blur > 0 ? 30 : 22,
            offset: const Offset(0, 10),
            spreadRadius: -6,
          ),
        ],
      ),
      child: border != null
          ? Padding(padding: padding ?? EdgeInsets.zero, child: child)
          : ClipRRect(
              borderRadius: BorderRadius.circular(innerRadius),
              child: _Pane(
                blur: blur,
                fill: fill,
                innerRadius: innerRadius,
                sheen: sheen,
                rim: rim,
                palette: p,
                padding: padding,
                child: child,
              ),
            ),
    );
  }
}

class _Pane extends StatelessWidget {
  final double blur;
  final Color fill;
  final double innerRadius;
  final bool sheen;
  final bool rim;
  final GlassPalette palette;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  const _Pane({
    required this.blur,
    required this.fill,
    required this.innerRadius,
    required this.sheen,
    required this.rim,
    required this.palette,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    Widget pane = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(innerRadius),
        color: fill,
      ),
      child: Stack(
        children: [
          if (sheen)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(innerRadius),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(
                            alpha: palette.isDark ? 0.06 : 0.40),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.55],
                    ),
                  ),
                ),
              ),
            ),
          // Specular top rim — the glossy glass signature.
          if (rim)
            Positioned(
              top: 0,
              left: innerRadius * 0.8,
              right: innerRadius * 0.8,
              height: 1.2,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(
                            alpha: palette.isDark ? 0.45 : 0.9),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ],
      ),
    );

    if (blur > 0) {
      pane = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: pane,
      );
    }

    return pane;
  }
}
