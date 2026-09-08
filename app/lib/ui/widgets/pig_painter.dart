import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/pig_service.dart';
import 'pig_design.dart';

/// Everything the painter needs to pose one pig. The scene owns the
/// behaviour (timers, hops, blinks); the painter only renders a snapshot.
class PigPose {
  final double t; // seconds, drives idle flourishes
  final double walk; // walk-cycle phase in turns; < 0 means standing
  final bool sleeping;
  final bool blink;
  final double happy; // 0..1, petted joy (^⁠^ face, open smile)
  final double squash; // 0..1 vertical squash, e.g. landing thump
  final double lean; // radians of body tilt while strolling
  final double lift; // logical px off the ground (hops, entrance drop)
  final double chub; // 0..1 growth stage: 0 piglet, .4 grown, 1 chunky

  /// Which way the pig turns its face: +1 toward +x, -1 toward -x.
  final double facing;

  /// 0..1 — how grubby the coat is; paints mud splotches.
  final double dirt;

  /// 0..1 — hunger blues: droopy eyes and a greyed-out coat.
  final double sad;

  const PigPose({
    required this.t,
    this.walk = -1,
    this.sleeping = false,
    this.blink = false,
    this.happy = 0,
    this.squash = 0,
    this.lean = 0,
    this.lift = 0,
    this.chub = 0,
    this.facing = 1,
    this.dirt = 0,
    this.sad = 0,
  });
}

/// How raised a pig is, derived from the pose's chub.
enum _Stage { piglet, grown, chunky }

/// A chibi vinyl-toy pig in the reference-board style: near-round body,
/// stubby legs, big glossy eyes, oversized oval snout, blush — drawn with
/// BOLD dark outlines and two-tone cel shading. Each breed's [PigDesign]
/// layers a themed costume (coat pattern, hat, back item, prop) so no two
/// breeds read as recolours. Everything is parametric: no sprites, any
/// resolution, and the growth stages restyle the same design (piglets are
/// rounder with bigger eyes; chunky pigs bulge at the cheeks).
///
/// Paints into a local space where (0, 0) is the feet on the ground and
/// one unit is one logical pixel at scale 1. The caller translates and
/// scales first; use [PigArt.hitRadius] for taps.
class PigArt {
  static const double hitRadius = 52;

  static Color _lighten(Color c, double amt) => Color.lerp(c, Colors.white, amt)!;
  static Color _darken(Color c, double amt) => Color.lerp(c, Colors.black, amt)!;

  static void paint(Canvas canvas, PigBreed breed, PigPose pose) {
    final d = breed.design;
    final t = pose.t;
    final f = pose.facing >= 0 ? 1.0 : -1.0;
    final sleeping = pose.sleeping;
    final happy = pose.happy.clamp(0.0, 1.0);
    final walking = pose.walk >= 0 && !sleeping;
    final bob = walking ? math.sin(pose.walk * 2 * math.pi * 2) * 2.5 : 0.0;

    final stage = pose.chub >= 0.8
        ? _Stage.chunky
        : pose.chub <= 0.15
            ? _Stage.piglet
            : _Stage.grown;

    _paintShadow(canvas, pose);
    if (d.aura != AuraStyle.none) _paintAura(canvas, d, t);

    canvas.save();
    canvas.translate(0, -pose.lift);
    final sq = pose.squash.clamp(0.0, 1.0);
    canvas.scale(1 + 0.26 * sq, 1 - 0.28 * sq);
    if (sleeping) canvas.scale(1.07, 0.82);
    canvas.rotate(pose.lean + (happy > 0.05 ? math.sin(t * 14) * 0.05 * happy : 0));
    canvas.translate(0, bob);

    // Stage anatomy: piglets are small and round with huge eyes; chunky
    // pigs are wide with bulging cheeks and a second chin.
    final (bw, bh, bodyY) = switch (stage) {
      _Stage.piglet => (72.0, 70.0, -46.0),
      _Stage.grown => (88.0, 80.0, -54.0),
      _Stage.chunky => (104.0, 86.0, -54.0),
    };
    // Piglets: enormous glossy eyes and a button snout — the baby cues
    // must survive even at thumbnail sizes.
    final eyeScale = stage == _Stage.piglet ? 1.45 : 1.0;
    final snoutScale = stage == _Stage.piglet ? 0.7 : 1.0;

    _paintBackItem(canvas, d, t);
    _paintTail(canvas, d, t, f, sleeping);

    _paintLegs(canvas, d, pose, f, sleeping, far: true, stage: stage);
    _paintBody(canvas, d, f, stage, bw, bh, bodyY,
        dirt: pose.dirt.clamp(0.0, 1.0), sad: pose.sad.clamp(0.0, 1.0));
    _paintLegs(canvas, d, pose, f, sleeping, far: false, stage: stage);

    _paintEars(canvas, d, t, f, sleeping, happy, stage, bw, bh, bodyY);
    _paintFace(canvas, d, pose, f, happy, eyeScale, snoutScale, stage);
    _paintHat(canvas, d, t, stage, bw, bh, bodyY);
    _paintFore(canvas, d, t, stage);

    if (stage == _Stage.piglet && d.hat == HatKind.none) {
      _paintBabyCurl(canvas, bw, bh, bodyY);
    }
    if (sleeping) _paintZzz(canvas, t);

    canvas.restore();
  }

  // -- ink: the outline-and-fill brush every part shares ----------------------

  static void _shape(Canvas canvas, Path path, Color fill, Color line,
      {double w = 3}) {
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(path, Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round);
  }

  static void _oval(Canvas canvas, Rect rect, Color fill, Color line,
      {double w = 3}) {
    canvas.drawOval(rect, Paint()..color = fill);
    canvas.drawOval(rect, Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = w);
  }

  static void _rrect(Canvas canvas, RRect rect, Color fill, Color line,
      {double w = 3}) {
    canvas.drawRRect(rect, Paint()..color = fill);
    canvas.drawRRect(rect, Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = w);
  }

  /// The body silhouette as a path, so patterns and shading can clip to it.
  static Path _bodyPath(double w, double h, double y) => Path()
    ..addOval(Rect.fromCenter(center: Offset(0, y), width: w, height: h));

  // -- stage one: the ground ---------------------------------------------------

  static void _paintShadow(Canvas canvas, PigPose pose) {
    final shrink = 1 - (pose.lift / 120).clamp(0.0, 1.0) * 0.4;
    final rect = Rect.fromCenter(
        center: const Offset(2, 2), width: 100 * shrink, height: 22 * shrink);
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.black.withValues(alpha: 0.24),
          Colors.black.withValues(alpha: 0.0),
        ]).createShader(rect),
    );
  }

  /// Rarity glow ring at the feet — the reference boards mark rare pigs
  /// with a coloured halo under them. Hard-edged flat rings: soft airbrush
  /// glows clash with the cel style and read as pasted-on.
  static void _paintAura(Canvas canvas, PigDesign d, double t) {
    final (color, color2) = switch (d.aura) {
      AuraStyle.gold => (const Color(0xFFF7C948), const Color(0xFFFFF3C4)),
      AuraStyle.frost => (const Color(0xFF8FDFF0), const Color(0xFFE8FAFF)),
      AuraStyle.fire => (const Color(0xFFFF7A45), const Color(0xFFFFD9A8)),
      AuraStyle.star => (const Color(0xFFB89BE0), const Color(0xFFF3EAFF)),
      AuraStyle.voidRift => (const Color(0xFF8A6FD8), const Color(0xFFD9CCF5)),
      AuraStyle.rainbow => (const Color(0xFFFF8FB1), const Color(0xFF8FDFF0)),
      AuraStyle.none => (const Color(0x00000000), const Color(0x00000000)),
    };
    final pulse = 0.5 + 0.5 * math.sin(t * 2.4);
    if (d.aura == AuraStyle.rainbow) {
      const rings = [
        Color(0xFFFF8FB1), Color(0xFFFFD86B), Color(0xFF8FE0A8),
        Color(0xFF8FDFF0), Color(0xFFC9AEE8),
      ];
      for (final (i, c) in rings.indexed) {
        canvas.drawOval(
          Rect.fromCenter(
              center: const Offset(0, 0),
              width: 86 + i * 9,
              height: 22 + i * 3),
          Paint()
            ..color = c.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.6,
        );
      }
      return;
    }
    // Two flat concentric rings: outer soft-wide, inner bright.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 0), width: 128, height: 38),
      Paint()
        ..color = color.withValues(alpha: 0.30 + 0.10 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 0), width: 112, height: 32),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.4,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 0), width: 98, height: 26),
      Paint()
        ..color = color2
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Hard triangle sparks riding the ring — flat, not blurry.
    for (var i = 0; i < 3; i++) {
      final ang = t * 1.6 + i * 2.09;
      final p = Offset(math.cos(ang) * 60, math.sin(ang) * 17);
      final tangent = ang + math.pi / 2;
      final spark = Path()
        ..moveTo(p.dx, p.dy - 7)
        ..lineTo(p.dx + math.cos(tangent) * 2.6, p.dy + math.sin(tangent) * 2.6)
        ..lineTo(p.dx - math.cos(tangent) * 2.6, p.dy - math.sin(tangent) * 2.6)
        ..close();
      canvas.drawPath(spark, Paint()..color = color2);
    }
  }

  // -- the body ----------------------------------------------------------------

  static void _paintBody(
    Canvas canvas,
    PigDesign d,
    double f,
    _Stage stage,
    double bw,
    double bh,
    double bodyY, {
    double dirt = 0,
    double sad = 0,
  }) {
    final line = d.outline;
    final base =
        sad > 0 ? Color.lerp(d.body, const Color(0xFF8E8E96), 0.30 * sad)! : d.body;
    final body = _bodyPath(bw, bh, bodyY);

    // Chunky pigs bulge at the cheeks — two arcs breaking the ball's sides.
    if (stage == _Stage.chunky) {
      final p = body.shift(const Offset(0, -2));
      p.addOval(Rect.fromCenter(
          center: Offset(-bw * 0.42, bodyY + 6), width: 34, height: 30));
      p.addOval(Rect.fromCenter(
          center: Offset(bw * 0.42, bodyY + 6), width: 34, height: 30));
      _shape(canvas, p, base, line, w: 3.2);
    } else {
      _shape(canvas, body, base, line, w: 3.2);
    }

    // Everything below lives inside the silhouette.
    canvas.save();
    canvas.clipPath(body);

    // Belly patch (droops lower when chunky).
    if (d.belly != null) {
      final bellyH = stage == _Stage.chunky ? 40.0 : 32.0;
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(4 * f, bodyY + bh * 0.30), width: 52, height: bellyH),
        Paint()..color = d.belly!,
      );
    }

    // Coat pattern — piglets show it faintly, as if the colours still come in.
    final patternAlpha = stage == _Stage.piglet ? 0.55 : 1.0;
    _paintPattern(canvas, d, base, bw, bh, bodyY, patternAlpha);

    // Cel shading: one shadow crescent on the lower-right, one light blob
    // upper-left — the whole "vinyl toy" look in two shapes.
    final shade = _darken(base, 0.16);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(bw * 0.22, bodyY + bh * 0.22),
          width: bw * 1.05,
          height: bh * 1.05),
      Paint()..color = shade.withValues(alpha: 0.55),
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(-bw * 0.26, bodyY - bh * 0.38),
          width: bw * 0.44,
          height: bh * 0.26),
      Paint()..color = Colors.white.withValues(alpha: 0.34),
    );
    canvas.drawCircle(
      Offset(-bw * 0.30, bodyY - bh * 0.42),
      3.4,
      Paint()..color = Colors.white.withValues(alpha: 0.65),
    );

    // Mud, when the care meter says so.
    if (dirt > 0.05) {
      const splotches = [
        (-26.0, -30.0, 13.0),
        (18.0, -24.0, 10.0),
        (2.0, -64.0, 9.0),
        (-8.0, -48.0, 7.0),
      ];
      final mud = Paint()..color = const Color(0xFF8A6A42).withValues(alpha: 0.5 * dirt);
      for (final (dx, dy, r) in splotches) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(dx * f, dy), width: r * 2, height: r * 1.4),
          mud,
        );
      }
    }

    canvas.restore();

    // Chunky chin: a second outline arc under the face.
    if (stage == _Stage.chunky) {
      canvas.drawArc(
        Rect.fromCenter(center: Offset(2 * f, bodyY + 26), width: 46, height: 30),
        0.25,
        math.pi - 0.5,
        false,
        Paint()
          ..color = line.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  static void _paintPattern(Canvas canvas, PigDesign d, Color base,
      double bw, double bh, double bodyY, double alpha) {
    final c = d.patternColor ?? _darken(base, 0.12);
    final c2 = d.patternColor2 ?? _lighten(base, 0.2);
    final paint = Paint()..color = c.withValues(alpha: alpha);
    final paint2 = Paint()..color = c2.withValues(alpha: alpha);
    final rng = _seq(7);

    switch (d.pattern) {
      case CoatPattern.none:
        break;
      case CoatPattern.bigPatch:
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(-bw * 0.16, bodyY - bh * 0.22),
              width: bw * 0.62,
              height: bh * 0.52),
          paint,
        );
      case CoatPattern.spots:
        for (var i = 0; i < 7; i++) {
          final dx = (rng() - 0.5) * bw * 0.9;
          final dy = (rng() - 0.5) * bh * 0.8;
          canvas.drawOval(
            Rect.fromCenter(
                center: Offset(dx, bodyY + dy),
                width: 12 + rng() * 12,
                height: 9 + rng() * 9),
            paint,
          );
        }
      case CoatPattern.freckles:
        for (var i = 0; i < 9; i++) {
          canvas.drawCircle(
            Offset((rng() - 0.5) * bw * 0.8, bodyY + (rng() - 0.5) * bh * 0.7),
            1.8 + rng() * 1.2,
            paint,
          );
        }
      case CoatPattern.stripes:
        // Bands that wrap the ball — bee rinds, watermelon skin. The band
        // crossing the eye line is skipped so the face stays clean.
        for (var i = 0; i < 4; i++) {
          final yy = bodyY - bh * 0.55 + i * bh * 0.34;
          if ((yy - (bodyY - 6)).abs() < bh * 0.20) continue;
          final hh = bh * 0.15;
          canvas.drawOval(
            Rect.fromCenter(
                center: Offset(0, yy), width: bw * 1.15, height: hh * 2),
            i.isEven ? paint : paint2,
          );
        }
      case CoatPattern.diamonds:
        for (var ix = -2; ix <= 2; ix++) {
          for (var iy = -2; iy <= 2; iy++) {
            final dx = ix * 17.0, dy = iy * 14.0 + (ix.isEven ? 0.0 : 7.0);
            if (dx * dx / (bw * bw) + dy * dy / (bh * bh) > 0.23) continue;
            final dot = Path()
              ..moveTo(dx, dy - 5)
              ..lineTo(dx + 4.4, dy)
              ..lineTo(dx, dy + 5)
              ..lineTo(dx - 4.4, dy)
              ..close();
            canvas.drawPath(dot, paint);
          }
        }
      case CoatPattern.seeds:
        for (var i = 0; i < 12; i++) {
          final a = rng() * 2 * math.pi;
          final rx = math.cos(a) * bw * 0.42;
          final ry = math.sin(a) * bh * 0.38;
          final seed = Offset(rx, ry);
          canvas.drawOval(
            Rect.fromCenter(center: seed.translate(0, bodyY), width: 3.2, height: 5),
            paint,
          );
        }
      case CoatPattern.scales:
        for (var row = -2; row <= 2; row++) {
          for (var col = -3; col <= 3; col++) {
            final dx = col * 15.0 + (row.isOdd ? 7.5 : 0.0);
            final dy = row * 11.0 + bodyY - 6;
            if (dx * dx / (bw * bw) + (dy - bodyY) * (dy - bodyY) / (bh * bh) > 0.24) {
              continue;
            }
            canvas.drawArc(
              Rect.fromCenter(center: Offset(dx, dy), width: 13, height: 10),
              math.pi,
              math.pi,
              false,
              Paint()
                ..color = c.withValues(alpha: alpha * 0.5)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2,
            );
          }
        }
      case CoatPattern.wool:
        for (var i = 0; i < 12; i++) {
          final a = i / 12 * 2 * math.pi;
          canvas.drawCircle(
            Offset(math.cos(a) * bw * 0.38, bodyY + math.sin(a) * bh * 0.36),
            10 + rng() * 4,
            i.isEven ? paint : paint2,
          );
        }
      case CoatPattern.splats:
        for (var i = 0; i < 5; i++) {
          final dx = (rng() - 0.5) * bw * 0.85;
          final dy = (rng() - 0.5) * bh * 0.7;
          final splotch = Path()
            ..addOval(Rect.fromCenter(
                center: Offset(dx, bodyY + dy), width: 18 + rng() * 10, height: 14 + rng() * 8))
            ..addOval(Rect.fromCenter(
                center: Offset(dx + 12, bodyY + dy - 8), width: 9, height: 7))
            ..addOval(Rect.fromCenter(
                center: Offset(dx - 10, bodyY + dy + 7), width: 8, height: 6));
          canvas.drawPath(splotch, paint);
        }
      case CoatPattern.stars:
        for (var i = 0; i < 8; i++) {
          final dx = (rng() - 0.5) * bw * 0.85;
          final dy = bodyY + (rng() - 0.5) * bh * 0.75;
          final s = 4.2 + rng() * 3.0;
          final star = Path()
            ..moveTo(dx, dy - s)
            ..quadraticBezierTo(dx + s * 0.22, dy - s * 0.22, dx + s, dy)
            ..quadraticBezierTo(dx + s * 0.22, dy + s * 0.22, dx, dy + s)
            ..quadraticBezierTo(dx - s * 0.22, dy + s * 0.22, dx - s, dy)
            ..quadraticBezierTo(dx - s * 0.22, dy - s * 0.22, dx, dy - s);
          canvas.drawPath(star, paint);
          canvas.drawCircle(Offset(dx, dy), s * 0.2,
              Paint()..color = Colors.white.withValues(alpha: alpha * 0.9));
        }
      case CoatPattern.hexes:
        for (var ix = -1; ix <= 1; ix++) {
          for (var iy = -1; iy <= 1; iy++) {
            final dx = ix * 22.0 + (iy.isOdd ? 11.0 : 0.0);
            final dy = iy * 19.0;
            final hex = Path();
            for (var k = 0; k < 6; k++) {
              final a = k * math.pi / 3 + math.pi / 6;
              final p = Offset(dx + math.cos(a) * 10, bodyY + dy + math.sin(a) * 10);
              k == 0 ? hex.moveTo(p.dx, p.dy) : hex.lineTo(p.dx, p.dy);
            }
            hex.close();
            canvas.drawPath(
              hex,
              Paint()
                ..color = c.withValues(alpha: alpha * 0.85)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.8,
            );
            canvas.drawCircle(
              Offset(dx, bodyY + dy),
              1.8,
              Paint()..color = c.withValues(alpha: alpha),
            );
          }
        }
      case CoatPattern.bubbles:
        for (var i = 0; i < 8; i++) {
          final r = 4.0 + rng() * 6;
          canvas.drawCircle(
            Offset((rng() - 0.5) * bw * 0.8, bodyY + (rng() - 0.5) * bh * 0.72),
            r,
            Paint()
              ..color = c.withValues(alpha: alpha * 0.8)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      case CoatPattern.circuitry:
        for (var i = 0; i < 4; i++) {
          final y0 = bodyY - bh * 0.5 + i * bh * 0.32;
          canvas.drawLine(
            Offset(-bw * 0.4, y0),
            Offset(-bw * 0.1, y0),
            Paint()
              ..color = c.withValues(alpha: alpha * 0.95)
              ..strokeWidth = 3.4
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawLine(
            Offset(-bw * 0.1, y0),
            Offset(bw * 0.05, y0 + 6),
            Paint()
              ..color = c.withValues(alpha: alpha * 0.95)
              ..strokeWidth = 3.4
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawCircle(
            Offset(-bw * 0.44, y0),
            3.2,
            Paint()..color = c.withValues(alpha: alpha),
          );
        }
      case CoatPattern.nebula:
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(-bw * 0.1, bodyY - bh * 0.1),
              width: bw * 0.7,
              height: bh * 0.5),
          Paint()..color = c.withValues(alpha: alpha * 0.5),
        );
        for (var i = 0; i < 10; i++) {
          canvas.drawCircle(
            Offset((rng() - 0.5) * bw * 0.9, bodyY + (rng() - 0.5) * bh * 0.8),
            0.9 + rng() * 1.4,
            Paint()..color = Colors.white.withValues(alpha: alpha * 0.9),
          );
        }
      case CoatPattern.bands:
        // A clean two-tone split down the middle.
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset(bw * 0.25, bodyY), width: bw * 0.55, height: bh),
          paint,
        );
      case CoatPattern.creamSwirl:
        final swirl = Path()
          ..moveTo(-bw * 0.35, bodyY - bh * 0.1)
          ..quadraticBezierTo(0, bodyY - bh * 0.55, bw * 0.35, bodyY - bh * 0.05)
          ..quadraticBezierTo(0, bodyY - bh * 0.15, -bw * 0.35, bodyY - bh * 0.1);
        canvas.drawPath(swirl, Paint()..color = c.withValues(alpha: alpha * 0.7));
      case CoatPattern.mintChips:
        for (var i = 0; i < 8; i++) {
          final dx = (rng() - 0.5) * bw * 0.8;
          final dy = bodyY + (rng() - 0.5) * bh * 0.7;
          canvas.drawOval(
            Rect.fromCenter(center: Offset(dx, dy), width: 7, height: 5),
            Paint()..color = c.withValues(alpha: alpha),
          );
        }
      case CoatPattern.runes:
        for (var i = 0; i < 5; i++) {
          final dx = (rng() - 0.5) * bw * 0.75;
          final dy = bodyY + (rng() - 0.5) * bh * 0.65;
          canvas.drawLine(
            Offset(dx, dy - 4),
            Offset(dx, dy + 4),
            Paint()
              ..color = c.withValues(alpha: alpha)
              ..strokeWidth = 2.2
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawLine(
            Offset(dx - 3, dy - 1),
            Offset(dx + 3, dy - 1),
            Paint()
              ..color = c.withValues(alpha: alpha)
              ..strokeWidth = 2.2
              ..strokeCap = StrokeCap.round,
          );
        }
      case CoatPattern.waves:
        for (var i = 0; i < 3; i++) {
          final y0 = bodyY - bh * 0.4 + i * bh * 0.3;
          final wave = Path()
            ..moveTo(-bw * 0.6, y0)
            ..quadraticBezierTo(-bw * 0.3, y0 - 7, 0, y0)
            ..quadraticBezierTo(bw * 0.3, y0 + 7, bw * 0.6, y0);
          canvas.drawPath(
            wave,
            Paint()
              ..color = c.withValues(alpha: alpha * 0.7)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.2
              ..strokeCap = StrokeCap.round,
          );
        }
      case CoatPattern.flames:
        for (var i = 0; i < 4; i++) {
          final dx = -bw * 0.3 + i * bw * 0.2;
          final flame = Path()
            ..moveTo(dx, bodyY + bh * 0.3)
            ..quadraticBezierTo(dx - 7, bodyY, dx + 2, bodyY - bh * 0.28)
            ..quadraticBezierTo(dx + 9, bodyY, dx, bodyY + bh * 0.3);
          canvas.drawPath(flame, Paint()..color = c.withValues(alpha: alpha * 0.7));
        }
    }
  }

  /// Deterministic pseudo-random sequence, so patterns are stable per frame.
  static double Function() _seq(int seed) {
    var s = seed;
    return () {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      return (s % 1000) / 1000;
    };
  }

  static void _paintLegs(
    Canvas canvas,
    PigDesign d,
    PigPose pose,
    double f,
    bool sleeping, {
    required bool far,
    required _Stage stage,
  }) {
    final walking = pose.walk >= 0 && !sleeping;
    final base = far ? _darken(d.body, 0.22) : _darken(d.body, 0.10);
    const phase = [0.0, math.pi];
    final legH = stage == _Stage.piglet ? 9.0 : 12.0;
    final stance = stage == _Stage.chunky ? 1.14 : 1.0;
    final xs = far
        ? [-24.0 * f * stance, -4.0 * f * stance]
        : [-10.0 * f * stance, 22.0 * f * stance];

    for (var i = 0; i < 2; i++) {
      canvas.save();
      canvas.translate(xs[i], -legH + 3);
      var swing = 0.0;
      if (walking) {
        swing = math.sin(pose.walk * 2 * math.pi * 2 + phase[i] + (far ? math.pi : 0)) *
            (far ? 0.18 : 0.26);
      } else if (sleeping) {
        swing = (i == 0) == far ? -0.4 : 0.4;
      }
      canvas.rotate(swing);
      final w = far ? 16.0 : 17.0;
      _rrect(
        canvas,
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-w / 2, -4, w, legH + 4),
          const Radius.circular(7),
        ),
        base,
        d.outline,
        w: 2.6,
      );
      // Hoof line.
      canvas.drawLine(
        Offset(-w / 2 + 3, legH - 3),
        Offset(w / 2 - 3, legH - 3),
        Paint()
          ..color = d.outline.withValues(alpha: 0.45)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }
  }

  // -- ears --------------------------------------------------------------------

  static void _paintEars(
    Canvas canvas,
    PigDesign d,
    double t,
    double f,
    bool sleeping,
    double happy,
    _Stage stage,
    double bw,
    double bh,
    double bodyY,
  ) {
    final top = bodyY - bh / 2 + (stage == _Stage.piglet ? 6.0 : 10.0);
    final inner = d.earInner ?? _lighten(d.blush, 0.15);
    final line = d.outline;
    final wig = sleeping ? 0.0 : math.sin(t * 2.4) * 0.06;
    final earScale = stage == _Stage.piglet ? 1.15 : 1.0;
    final earX = bw * (stage == _Stage.piglet ? 0.27 : 0.30);

    void ear(double side, double baseAngle, double s) {
      canvas.save();
      canvas.translate(side * earX, top);
      canvas.rotate(baseAngle + wig);
      canvas.scale(s * earScale);
      switch (d.ears) {
        case EarStyle.round:
          final petal = Path()
            ..moveTo(-10, 8)
            ..quadraticBezierTo(-7, -12, 4, -15)
            ..quadraticBezierTo(12, -5, 8, 8)
            ..close();
          _shape(canvas, petal, _darken(d.body, 0.05), line, w: 2.6);
          final innerPetal = Path()
            ..moveTo(-5.5, 5)
            ..quadraticBezierTo(-3, -7, 3, -9)
            ..quadraticBezierTo(8, -2, 5.5, 5)
            ..close();
          canvas.drawPath(
              innerPetal, Paint()..color = inner.withValues(alpha: 0.8));
        case EarStyle.floppy:
          final flop = Path()
            ..moveTo(-2, -6)
            ..quadraticBezierTo(-14, 2, -16, 18)
            ..quadraticBezierTo(-8, 20, -2, 12)
            ..close();
          _shape(canvas, flop, _darken(d.body, 0.08), line, w: 2.6);
        case EarStyle.leaf:
          final leaf = Path()
            ..moveTo(0, 8)
            ..quadraticBezierTo(-12, -2, -4, -14)
            ..quadraticBezierTo(6, -16, 8, -4)
            ..quadraticBezierTo(8, 4, 0, 8)
            ..close();
          _shape(canvas, leaf, Color(0xFF6FBF63), Color(0xFF4E9E5F), w: 2.4);
          canvas.drawLine(
            const Offset(0, 6),
            const Offset(-3, -10),
            Paint()
              ..color = const Color(0xFF4E9E5F)
              ..strokeWidth = 1.6
              ..strokeCap = StrokeCap.round,
          );
        case EarStyle.hornSmall:
          final horn = Path()
            ..moveTo(-5, 6)
            ..quadraticBezierTo(-8, -8, 2, -16)
            ..quadraticBezierTo(8, -6, 5, 6)
            ..close();
          _shape(canvas, horn, const Color(0xFFF7C948), line, w: 2.4);
        case EarStyle.hornBig:
          final horn = Path()
            ..moveTo(-7, 8)
            ..quadraticBezierTo(-14, -10, 4, -26)
            ..quadraticBezierTo(12, -8, 7, 8)
            ..close();
          _shape(canvas, horn, const Color(0xFFF2E4C4), line, w: 2.8);
        case EarStyle.antenna:
          canvas.drawLine(
            const Offset(0, 4),
            Offset(4 * side, -16),
            Paint()
              ..color = line
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round,
          );
          _oval(
            canvas,
            Rect.fromCircle(center: Offset(4 * side, -19), radius: 5),
            d.hatColor ?? _kGold,
            line,
            w: 2.4,
          );
        case EarStyle.fox:
          final fox = Path()
            ..moveTo(-9, 10)
            ..quadraticBezierTo(-10, -12, 6, -20)
            ..quadraticBezierTo(13, -8, 8, 10)
            ..close();
          _shape(canvas, fox, _darken(d.body, 0.02), line, w: 2.6);
          final tip = Path()
            ..moveTo(1, -12)
            ..quadraticBezierTo(7, -14, 8, -6)
            ..quadraticBezierTo(4, -4, 1, -12)
            ..close();
          canvas.drawPath(tip, Paint()..color = Colors.white);
        case EarStyle.fin:
          final fin = Path()
            ..moveTo(-8, 8)
            ..quadraticBezierTo(-16, -10, 12, -16)
            ..quadraticBezierTo(12, -2, 6, 8)
            ..close();
          _shape(canvas, fin, d.backColor ?? const Color(0xFF4E9E5F), line, w: 2.6);
      }
      canvas.restore();
    }

    ear(-f, -0.34, 0.88);
    ear(f, 0.36, 1.0);
  }

  static const _kGold = Color(0xFFF7C948);

  // -- face --------------------------------------------------------------------

  static void _paintFace(
    Canvas canvas,
    PigDesign d,
    PigPose pose,
    double f,
    double happy,
    double eyeScale,
    double snoutScale,
    _Stage stage,
  ) {
    final line = d.outline;
    final dark = const Color(0xFF2E2438);

    // Eyes, close-set above the snout; the far eye smaller and higher.
    final eyeY = -60.0;
    final eyes = [
      (x: -3.0 * f, y: eyeY, r: 4.6),
      (x: 17.0 * f, y: eyeY - 1.5, r: 5.4),
    ];
    for (final eye in eyes) {
      final c = Offset(eye.x, eye.y);
      final r = eye.r * eyeScale;
      if (pose.sad > 0.4 && !pose.sleeping) {
        // Hunger blues: downturned, watery.
        final p = Paint()
          ..color = dark
          ..strokeWidth = 2.8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(c.dx - r, c.dy - 1)
          ..quadraticBezierTo(c.dx, c.dy + 4.5, c.dx + r, c.dy - 1);
        canvas.drawPath(path, p);
        canvas.drawCircle(
          c.translate(0, 6),
          1.6,
          Paint()..color = const Color(0xFF9CC7E2).withValues(alpha: 0.9),
        );
      } else if (pose.sleeping || pose.blink) {
        final p = Paint()
          ..color = dark
          ..strokeWidth = 2.8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        final path = Path();
        if (pose.sleeping) {
          path.moveTo(c.dx - r, c.dy + 1);
          path.quadraticBezierTo(c.dx, c.dy + 5.5, c.dx + r, c.dy + 1);
        } else {
          path.moveTo(c.dx - r, c.dy);
          path.lineTo(c.dx + r, c.dy);
        }
        canvas.drawPath(path, p);
      } else if (happy > 0.25 && d.eyes != EyeStyle.visor) {
        // Joy squint: ^ ^
        final p = Paint()
          ..color = dark
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(c.dx - r - 0.6, c.dy + 2.5)
          ..quadraticBezierTo(c.dx, c.dy - r - 2, c.dx + r + 0.6, c.dy + 2.5);
        canvas.drawPath(path, p);
      } else {
        switch (d.eyes) {
          case EyeStyle.glossy:
            _oval(
              canvas,
              Rect.fromCenter(center: c, width: r * 1.55, height: r * 2.1),
              d.eyeColor ?? dark,
              d.eyeColor == null ? Colors.transparent : line,
              w: 2,
            );
            // Two shine dots sell the vinyl-toy gloss.
            canvas.drawCircle(
              c.translate(-r * 0.35, -r * 0.45),
              r * 0.38,
              Paint()..color = Colors.white.withValues(alpha: 0.95),
            );
            canvas.drawCircle(
              c.translate(r * 0.25, r * 0.35),
              r * 0.18,
              Paint()..color = Colors.white.withValues(alpha: 0.8),
            );
          case EyeStyle.bead:
            canvas.drawCircle(c, r * 0.62, Paint()..color = dark);
            canvas.drawCircle(
              c.translate(-1, -1.4),
              r * 0.22,
              Paint()..color = Colors.white,
            );
          case EyeStyle.happy:
            final p = Paint()
              ..color = dark
              ..strokeWidth = 2.8
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round;
            final path = Path()
              ..moveTo(c.dx - r, c.dy + 2)
              ..quadraticBezierTo(c.dx, c.dy - r - 2, c.dx + r, c.dy + 2);
            canvas.drawPath(path, p);
          case EyeStyle.sly:
            _oval(
              canvas,
              Rect.fromCenter(center: c, width: r * 1.7, height: r * 1.5),
              dark,
              Colors.transparent,
            );
            // Heavy upper lid.
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(c.dx - r, c.dy - r * 1.6, r * 2, r * 1.3),
                const Radius.circular(3),
              ),
              Paint()..color = _darken(d.body, 0.06),
            );
            canvas.drawCircle(
              c.translate(-r * 0.3, -r * 0.2),
              r * 0.25,
              Paint()..color = Colors.white,
            );
          case EyeStyle.visor:
            _rrect(
              canvas,
              RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset(7 * f, eyeY), width: 40, height: 14),
                const Radius.circular(7),
              ),
              const Color(0xFF2A3040),
              line,
              w: 2.4,
            );
            canvas.drawCircle(
              Offset(7 * f - 9, eyeY),
              3,
              Paint()..color = const Color(0xFF6FF2E0),
            );
            canvas.drawCircle(
              Offset(7 * f + 10, eyeY),
              3,
              Paint()..color = const Color(0xFF6FF2E0),
            );
        }
      }
    }

    // Blush — bigger on piglets (everything is cuter rounder).
    final blushScale = stage == _Stage.piglet ? 1.2 : 1.0;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(-11 * f, -47),
          width: 15 * blushScale,
          height: 9.5 * blushScale),
      Paint()..color = d.blush.withValues(alpha: 0.55),
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(28 * f, -47),
          width: 17 * blushScale,
          height: 10.5 * blushScale),
      Paint()..color = d.blush.withValues(alpha: 0.68),
    );

    // The snout — the pig's centrepiece.
    final snoutW = (d.snoutStyle == SnoutStyle.big
            ? 40.0
            : d.snoutStyle == SnoutStyle.tiny
                ? 26.0
                : 34.0) *
        snoutScale;
    final snoutH = (d.snoutStyle == SnoutStyle.big ? 27.0 : 23.0) * snoutScale;
    final snoutRect = Rect.fromCenter(
        center: Offset(12 * f, -45), width: snoutW, height: snoutH);
    _oval(canvas, snoutRect, d.snout, line, w: 2.8);
    // Top rim highlight keeps the snout dimensional.
    canvas.drawArc(
      snoutRect.deflate(2.5),
      -math.pi * 0.85,
      math.pi * 0.55,
      false,
      Paint()
        ..color = _lighten(d.snout, 0.3).withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    final nostrilPaint = Paint()..color = _darken(d.snout, 0.45);
    for (final dx in [-6.5, 6.5]) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(12 * f + dx * snoutScale, -45), width: 4.6, height: 7.4),
        nostrilPaint,
      );
    }
    if (d.snoutStyle == SnoutStyle.golden) {
      canvas.drawCircle(
        Offset(12 * f - snoutW * 0.2, -45 - snoutH * 0.2),
        2.2,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }

    // Mouth: an open smile when overjoyed.
    if (happy > 0.25 && !pose.sleeping) {
      _rrect(
        canvas,
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(12 * f, -28), width: 17, height: 12),
          const Radius.elliptical(8.5, 6),
        ),
        const Color(0xFFB0425A),
        line,
        w: 2.2,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(12 * f, -24), width: 9, height: 6),
        Paint()..color = const Color(0xFFEF8FA6),
      );
    }
  }

  // -- tails ---------------------------------------------------------------------

  static void _paintTail(
    Canvas canvas,
    PigDesign d,
    double t,
    double f,
    bool sleeping,
  ) {
    canvas.save();
    canvas.translate(-44 * f, -38);
    canvas.scale(f, 1);
    final line = d.outline;
    switch (d.tail) {
      case TailStyle.curl:
      case TailStyle.curlTight:
        final r = d.tail == TailStyle.curlTight ? 4.5 : 6.0;
        canvas.rotate(sleeping ? 0.9 : 0.5 + math.sin(t * 3) * 0.12);
        // A filled comma so the tail carries its own outline.
        final curl = Path()
          ..moveTo(0, 8)
          ..quadraticBezierTo(12, 7, 12, -3)
          ..quadraticBezierTo(12, -12, 3, -12)
          ..quadraticBezierTo(-3, -12, -3, -6)
          ..quadraticBezierTo(-3, -1, 2, -1)
          ..quadraticBezierTo(6, -1, 6, -5)
          ..quadraticBezierTo(6, -8, 2.5, -8)
          ..close();
        canvas.drawPath(curl, Paint()..color = _darken(d.body, 0.06));
        canvas.drawPath(
          curl,
          Paint()
            ..color = line
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.45
            ..strokeJoin = StrokeJoin.round,
        );
      case TailStyle.straight:
        canvas.rotate(sleeping ? 0.8 : 0.2 + math.sin(t * 2) * 0.08);
        _rrect(
          canvas,
          RRect.fromRectAndRadius(
              Rect.fromLTWH(-3, -16, 7, 24), const Radius.circular(3.5)),
          _darken(d.body, 0.06),
          line,
          w: 2.4,
        );
      case TailStyle.tuft:
        canvas.rotate(sleeping ? 0.8 : 0.3 + math.sin(t * 2.5) * 0.1);
        for (var i = -1; i <= 1; i++) {
          final strand = Path()
            ..moveTo(0, 4)
            ..quadraticBezierTo(i * 8, -4, i * 10 - 2, -14);
          canvas.drawPath(
            strand,
            Paint()
              ..color = d.patternColor ?? _darken(d.body, 0.1)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.6
              ..strokeCap = StrokeCap.round,
          );
        }
      case TailStyle.flame:
        final flick = math.sin(t * 9);
        canvas.rotate(0.2 + flick * 0.1);
        final outer = Path()
          ..moveTo(0, 6)
          ..quadraticBezierTo(14, 2, 12, -8)
          ..quadraticBezierTo(8 + flick * 2, -18, 2, -24)
          ..quadraticBezierTo(3, -14, -2, -10)
          ..quadraticBezierTo(-8, -14, -6, -4)
          ..quadraticBezierTo(-5, 2, 0, 6)
          ..close();
        _shape(canvas, outer, const Color(0xFFFF7A45), line, w: 2.4);
        final inner = Path()
          ..moveTo(1, 2)
          ..quadraticBezierTo(8, -2, 6, -9)
          ..quadraticBezierTo(5, -14, 2, -17)
          ..quadraticBezierTo(2, -9, -1, -6)
          ..quadraticBezierTo(-3, -8, -3, -3)
          ..close();
        canvas.drawPath(inner, Paint()..color = const Color(0xFFFFD24C));
      case TailStyle.bolt:
        canvas.rotate(0.15);
        final bolt = Path()
          ..moveTo(-2, 8)
          ..lineTo(8, -2)
          ..lineTo(3, -2)
          ..lineTo(10, -14)
          ..lineTo(-1, -4)
          ..lineTo(4, -4)
          ..close();
        _shape(canvas, bolt, const Color(0xFFFFD24C), line, w: 2.2);
      case TailStyle.feather:
        canvas.rotate(sleeping ? 0.7 : 0.35 + math.sin(t * 2.2) * 0.1);
        final feather = Path()
          ..moveTo(0, 6)
          ..quadraticBezierTo(-4, -6, -14, -16)
          ..quadraticBezierTo(2, -16, 8, -6)
          ..quadraticBezierTo(9, 0, 0, 6)
          ..close();
        _shape(canvas, feather, d.backColor ?? _kGold, line, w: 2.4);
        canvas.drawLine(
          const Offset(0, 4),
          const Offset(-10, -13),
          Paint()
            ..color = line
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round,
        );
      case TailStyle.fin:
        canvas.rotate(0.25 + math.sin(t * 2) * 0.08);
        final fin = Path()
          ..moveTo(0, 6)
          ..quadraticBezierTo(-16, -2, -12, -18)
          ..quadraticBezierTo(-2, -12, 2, -4)
          ..close();
        _shape(canvas, fin, d.backColor ?? const Color(0xFF4E9E5F), line, w: 2.4);
    }
    canvas.restore();
  }

  // -- back items ------------------------------------------------------------------

  static void _paintBackItem(Canvas canvas, PigDesign d, double t) {
    final line = d.outline;
    final c1 = d.backColor ?? Colors.white;
    final c2 = d.backColor2 ?? _lighten(c1, 0.3);
    switch (d.back) {
      case BackKind.none:
        break;
      case BackKind.angelWings:
      case BackKind.frostWings:
      case BackKind.flameWings:
        final flap = math.sin(t * 5.5) * 0.26 - 0.06;
        for (final side in [-1.0, 1.0]) {
          canvas.save();
          canvas.translate(38 * side, -58);
          canvas.rotate(side * (0.45 + flap));
          if (d.back == BackKind.flameWings) {
            final wing = Path()
              ..moveTo(0, 4)
              ..quadraticBezierTo(-18 * side, -26, -40 * side, -12)
              ..quadraticBezierTo(-28 * side, -4, -30 * side, 10)
              ..quadraticBezierTo(-12 * side, 8, 0, 14)
              ..close();
            _shape(canvas, wing, c1, line, w: 2.6);
            final inner = Path()
              ..moveTo(-4 * side, 4)
              ..quadraticBezierTo(-16 * side, -14, -30 * side, -8)
              ..quadraticBezierTo(-20 * side, -2, -22 * side, 6)
              ..quadraticBezierTo(-12 * side, 6, -4 * side, 10)
              ..close();
            canvas.drawPath(inner, Paint()..color = c2);
          } else {
            final wing = Path()
              ..moveTo(0, 6)
              ..quadraticBezierTo(-16 * side, -24, -36 * side, -16)
              ..quadraticBezierTo(-26 * side, -6, -28 * side, 6)
              ..quadraticBezierTo(-14 * side, 4, 0, 12)
              ..close();
            _shape(canvas, wing, c1, line, w: 2.6);
            // Feather grooves / ice facets.
            canvas.drawLine(
                Offset(-8 * side, 0), Offset(-22 * side, -8),
                Paint()..color = c2.withValues(alpha: 0.8)..strokeWidth = 2);
            canvas.drawLine(
                Offset(-8 * side, 5), Offset(-20 * side, 2),
                Paint()..color = c2.withValues(alpha: 0.8)..strokeWidth = 2);
          }
          canvas.restore();
        }
      case BackKind.beetleWings:
        final flap = math.sin(t * 18) * 0.3;
        for (final side in [-1.0, 1.0]) {
          canvas.save();
          canvas.translate(34 * side, -60);
          canvas.rotate(side * (0.5 + flap));
          final wing = Path()
            ..moveTo(0, 0)
            ..quadraticBezierTo(-14 * side, -22, -34 * side, -14)
            ..quadraticBezierTo(-26 * side, 2, 0, 8)
            ..close();
          canvas.drawPath(
            wing,
            Paint()
              ..color = c1.withValues(alpha: 0.55)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4,
          );
          canvas.restore();
        }
      case BackKind.cape:
      case BackKind.royalCape:
        final sway = math.sin(t * 2.4) * 0.06;
        canvas.save();
        canvas.translate(0, -74);
        canvas.rotate(sway);
        final cape = Path()
          ..moveTo(-30, 0)
          ..quadraticBezierTo(-38, 34, -30 + sway * 30, 52)
          ..quadraticBezierTo(0, 44, 30, 52)
          ..quadraticBezierTo(38, 34, 30, 0)
          ..close();
        _shape(canvas, cape, c1, line, w: 2.8);
        if (d.back == BackKind.royalCape) {
          // Ermine trim along the collar.
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(-31, -2, 62, 10), const Radius.circular(5)),
            Paint()..color = c2,
          );
          for (var i = -2; i <= 2; i++) {
            canvas.drawCircle(Offset(i * 12.0, 3), 1.6, Paint()..color = Colors.black38);
          }
        }
        canvas.restore();
      case BackKind.shellPack:
        final shell = Path()
          ..moveTo(0, -78)
          ..quadraticBezierTo(-34, -74, -36, -46)
          ..quadraticBezierTo(-20, -36, 0, -38)
          ..quadraticBezierTo(20, -36, 36, -46)
          ..quadraticBezierTo(34, -74, 0, -78)
          ..close();
        _shape(canvas, shell, c1, line, w: 2.8);
        for (var i = -1; i <= 1; i++) {
          canvas.drawArc(
            Rect.fromCircle(center: Offset(i * 14, -52), radius: 13),
            math.pi * 0.15,
            math.pi * 0.9,
            false,
            Paint()
              ..color = _darken(c1, 0.12)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2,
          );
        }
      case BackKind.leafPack:
        final pack = Path()
          ..moveTo(-26, -74)
          ..quadraticBezierTo(-40, -50, -24, -34)
          ..quadraticBezierTo(-6, -42, -8, -70)
          ..close();
        _shape(canvas, pack, c1, line, w: 2.6);
        canvas.drawLine(
          const Offset(-24, -70),
          const Offset(-20, -40),
          Paint()..color = _darken(c1, 0.25)..strokeWidth = 2,
        );
      case BackKind.jetpack:
        _rrect(
          canvas,
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: const Offset(0, -52), width: 34, height: 40),
              const Radius.circular(10)),
          _kSteel,
          line,
          w: 2.8,
        );
        for (final side in [-1.0, 1.0]) {
          final flameH = 16 + math.sin(t * 20 + side) * 5;
          final flame = Path()
            ..moveTo(side * 9 - 4, -34)
            ..quadraticBezierTo(side * 9, -34 + flameH, side * 9, -34 + flameH + 6)
            ..quadraticBezierTo(side * 9 + 4, -34 + flameH * 0.5, side * 9 + 4, -34)
            ..close();
          canvas.drawPath(flame, Paint()..color = const Color(0xFFFF9A5C));
        }
      case BackKind.fanTail:
        for (var i = -2; i <= 2; i++) {
          final a = i * 0.38 + math.sin(t * 1.8) * 0.03;
          canvas.save();
          canvas.translate(-6, -52);
          canvas.rotate(a - math.pi / 2);
          final feather = Path()
            ..moveTo(0, 0)
            ..quadraticBezierTo(-12, -30, 0, -52)
            ..quadraticBezierTo(12, -30, 0, 0)
            ..close();
          _shape(
            canvas,
            feather,
            i.isEven ? c1 : _darken(c1, 0.12),
            line,
            w: 2.2,
          );
          // The eye-spot near the tip.
          canvas.drawCircle(Offset(0, -36), 5, Paint()..color = c2);
          canvas.drawCircle(Offset(0, -36), 2.2, Paint()..color = _kNavy);
          canvas.restore();
        }
      case BackKind.bubbleRing:
        for (var i = 0; i < 6; i++) {
          final a = t * 0.8 + i * math.pi / 3;
          canvas.drawCircle(
            Offset(math.cos(a) * 42, -54 + math.sin(a) * 20),
            5 + (i % 3),
            Paint()
              ..color = c1.withValues(alpha: 0.45)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      case BackKind.fins:
        final dorsal = Path()
          ..moveTo(0, -86)
          ..quadraticBezierTo(-10, -104, 6, -108)
          ..quadraticBezierTo(12, -96, 8, -84)
          ..close();
        _shape(canvas, dorsal, c1, line, w: 2.6);
      case BackKind.voidRift:
        final rift = Path()
          ..moveTo(-40, -70)
          ..lineTo(-24, -58)
          ..lineTo(-38, -52)
          ..lineTo(-22, -40)
          ..lineTo(-36, -34)
          ..close();
        canvas.drawPath(
          rift,
          Paint()
            ..color = c1.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
        for (var i = 0; i < 4; i++) {
          final tw = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * 3 + i * 2));
          canvas.drawCircle(
            Offset(-30 - i * 3, -66 + i * 9),
            1.6,
            Paint()..color = const Color(0xFFC9AEE8).withValues(alpha: tw),
          );
        }
    }
  }

  static const _kSteel = Color(0xFFAEB9C9);
  static const _kNavy = Color(0xFF44589C);

  // -- hats ------------------------------------------------------------------

  /// Hats are painted in a frame where (0, 0) is the crown contact point on
  /// top of the head; +y goes down toward the face.
  static void _paintHat(Canvas canvas, PigDesign d, double t, _Stage stage,
      double bw, double bh, double bodyY) {
    if (d.hat == HatKind.none) return;
    final line = d.outline;
    final c1 = d.hatColor ?? _kGold;
    final c2 = d.hatColor2 ?? _lighten(c1, 0.35);
    final crownY = bodyY - bh / 2 + (stage == _Stage.piglet ? 6.0 : 9.0);
    final hatScale = stage == _Stage.piglet ? 1.08 : 1.0;
    final bob = math.sin(t * 2.2) * 1.5;

    canvas.save();
    canvas.translate(0, crownY + bob);
    canvas.scale(hatScale);

    switch (d.hat) {
      case HatKind.none:
        break;
      case HatKind.sprout:
        canvas.drawLine(
          const Offset(0, 2),
          const Offset(0, -10),
          Paint()..color = _kLeafDark..strokeWidth = 3..strokeCap = StrokeCap.round,
        );
        final leaf = Path()
          ..moveTo(0, -8)
          ..quadraticBezierTo(-16, -16, -18, -6)
          ..quadraticBezierTo(-8, -2, 0, -8)
          ..close();
        _shape(canvas, leaf, _kLeafGreen, line, w: 2.2);
      case HatKind.flowerOne:
        for (var i = 0; i < 5; i++) {
          final a = i * 2 * math.pi / 5 - math.pi / 2;
          canvas.drawCircle(
              Offset(math.cos(a) * 5.4, -6 + math.sin(a) * 5.4), 3.6,
              Paint()..color = _kCherryHat);
        }
        canvas.drawCircle(const Offset(0, -6), 3, Paint()..color = _kGold);
      case HatKind.beanie:
        final dome = Path()
          ..moveTo(-17, 2)
          ..quadraticBezierTo(-16, -20, 0, -22)
          ..quadraticBezierTo(16, -20, 17, 2)
          ..close();
        _shape(canvas, dome, c1, line, w: 2.6);
        _rrect(
          canvas,
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(-18, -1, 36, 8), const Radius.circular(4)),
          c2,
          line,
          w: 2.4,
        );
        canvas.drawCircle(const Offset(0, -24), 5.5, Paint()..color = c2);
        canvas.drawCircle(const Offset(0, -24), 5.5,
            Paint()..color = line..style = PaintingStyle.stroke..strokeWidth = 2.2);
      case HatKind.butter:
        _rrect(
          canvas,
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(-13, -12, 26, 12), const Radius.circular(3)),
          c1,
          line,
          w: 2.4,
        );
        canvas.drawCircle(const Offset(-3, -14), 3.4, Paint()..color = Colors.white70);
      case HatKind.berryBasket:
        // Upturned basket: woven cone with berries tumbling out.
        final cone = Path()
          ..moveTo(-14, -2)
          ..quadraticBezierTo(-12, -16, 0, -18)
          ..quadraticBezierTo(12, -16, 14, -2)
          ..close();
        _shape(canvas, cone, const Color(0xFFC89B66), line, w: 2.4);
        for (final (dx, dy, r) in [(-6.0, -18.0, 4.0), (5.0, -20.0, 4.5), (0.0, -15.0, 3.6)]) {
          canvas.drawCircle(Offset(dx, dy), r, Paint()..color = c1);
          canvas.drawCircle(Offset(dx, dy), r,
              Paint()..color = line..style = PaintingStyle.stroke..strokeWidth = 2);
          canvas.drawCircle(Offset(dx - 1, dy - 1.4), 1.2, Paint()..color = Colors.white70);
        }
      case HatKind.whippedCream:
        // A pool at the base first, so the swirl never floats.
        _oval(
          canvas,
          Rect.fromCenter(center: const Offset(0, 2), width: 30, height: 10),
          c1,
          line,
          w: 2.4,
        );
        final swirl = Path()
          ..moveTo(-15, 2)
          ..quadraticBezierTo(-13, -12, -4, -14)
          ..quadraticBezierTo(-10, -22, -1, -26)
          ..quadraticBezierTo(6, -30, 8, -22)
          ..quadraticBezierTo(15, -18, 12, -10)
          ..quadraticBezierTo(17, -4, 15, 2)
          ..close();
        _shape(canvas, swirl, c1, line, w: 2.6);
        canvas.drawCircle(const Offset(6, -30), 4.4, Paint()..color = _kCherryHat);
        canvas.drawCircle(const Offset(6, -30), 4.4,
            Paint()..color = line..style = PaintingStyle.stroke..strokeWidth = 2);
      case HatKind.raindrop:
        final drop = Path()
          ..moveTo(0, -26)
          ..quadraticBezierTo(-12, -12, -10, -4)
          ..quadraticBezierTo(-8, 4, 0, 4)
          ..quadraticBezierTo(8, 4, 10, -4)
          ..quadraticBezierTo(12, -12, 0, -26)
          ..close();
        _shape(canvas, drop, c1, line, w: 2.6);
        canvas.drawCircle(const Offset(-3, -6), 2.4, Paint()..color = Colors.white70);
      case HatKind.scarfOnly:
        // Drawn around the neck instead of the crown.
        canvas.restore();
        canvas.save();
        canvas.translate(0, bodyY + bh * 0.30);
        _rrect(
          canvas,
          RRect.fromRectAndRadius(
              Rect.fromLTWH(-30, -6, 60, 13), const Radius.circular(6)),
          c1,
          line,
          w: 2.6,
        );
        final tailEnd = Path()
          ..moveTo(16, 4)
          ..quadraticBezierTo(24, 10, 22, 22)
          ..lineTo(13, 22)
          ..quadraticBezierTo(12, 10, 12, 5)
          ..close();
        _shape(canvas, tailEnd, c1, line, w: 2.4);
        for (var i = 0; i < 3; i++) {
          canvas.drawLine(
            Offset(13.5 + i * 3.4, 22),
            Offset(13.5 + i * 3.4, 27 + math.sin(t * 3 + i) * 1.5),
            Paint()..color = c2..strokeWidth = 2.4..strokeCap = StrokeCap.round,
          );
        }
        canvas.restore();
        return;
      case HatKind.leafCrown:
        for (var i = -2; i <= 2; i++) {
          final a = i * 0.5 - math.pi / 2;
          canvas.save();
          canvas.translate(math.cos(a) * 13, math.sin(a) * 8);
          canvas.rotate(a + math.pi / 2);
          final leaf = Path()
            ..moveTo(0, 4)
            ..quadraticBezierTo(-6, -8, 0, -18)
            ..quadraticBezierTo(6, -8, 0, 4)
            ..close();
          _shape(canvas, leaf, i.isEven ? c1 : _darken(c1, 0.12), line, w: 2.2);
          canvas.restore();
        }
      case HatKind.huskCollar:
        for (var i = -2; i <= 2; i++) {
          final a = i * 0.55 - math.pi / 2;
          canvas.save();
          canvas.translate(math.cos(a) * 20, 4 + math.sin(a) * 5);
          canvas.rotate(a + math.pi / 2 + 0.4);
          final husk = Path()
            ..moveTo(0, 2)
            ..quadraticBezierTo(-7, -10, -2, -22)
            ..quadraticBezierTo(5, -10, 0, 2)
            ..close();
          _shape(canvas, husk, _kLeafGreen, line, w: 2.2);
          canvas.restore();
        }
      case HatKind.bambooSpike:
        for (final (dx, rot) in [(-8.0, -0.5), (0.0, 0.0), (8.0, 0.5)]) {
          canvas.save();
          canvas.translate(dx, 0);
          canvas.rotate(rot);
          final blade = Path()
            ..moveTo(0, 2)
            ..quadraticBezierTo(-3, -10, 0, -20)
            ..quadraticBezierTo(3, -10, 0, 2)
            ..close();
          _shape(canvas, blade, c1, line, w: 2.2);
          canvas.restore();
        }
      case HatKind.candyWrap:
        for (final side in [-1.0, 1.0]) {
          final wrap = Path()
            ..moveTo(0, -6)
            ..quadraticBezierTo(side * 12, -12, side * 16, -4)
            ..quadraticBezierTo(side * 10, -2, side * 6, 2)
            ..close();
          _shape(canvas, wrap, c1, line, w: 2.2);
        }
        _oval(
          canvas,
          Rect.fromCenter(center: const Offset(0, -6), width: 14, height: 10),
          c1,
          line,
          w: 2.2,
        );
      case HatKind.sailorCap:
        _oval(
          canvas,
          Rect.fromCenter(center: const Offset(0, -4), width: 34, height: 14),
          Colors.white,
          line,
          w: 2.6,
        );
        _oval(
          canvas,
          Rect.fromCenter(center: const Offset(0, -8), width: 34, height: 14),
          c1,
          line,
          w: 2.6,
        );
        // Ribbon tail at the back.
        canvas.drawLine(
          const Offset(0, -12),
          const Offset(14, -20),
          Paint()..color = c1..strokeWidth = 3..strokeCap = StrokeCap.round,
        );
      case HatKind.tricorn:
        final hull = Path()
          ..moveTo(-26, -2)
          ..quadraticBezierTo(-20, -18, 0, -22)
          ..quadraticBezierTo(20, -18, 26, -2)
          ..quadraticBezierTo(12, -8, 0, -6)
          ..quadraticBezierTo(-12, -8, -26, -2)
          ..close();
        _shape(canvas, hull, c1, line, w: 2.8);
        // Skull and crossbones.
        canvas.drawCircle(const Offset(0, -12), 4, Paint()..color = Colors.white);
        canvas.drawCircle(const Offset(-1.4, -12.6), 1.1, Paint()..color = line);
        canvas.drawCircle(const Offset(1.4, -12.6), 1.1, Paint()..color = line);
        canvas.drawLine(
          const Offset(-6, -9),
          const Offset(6, -7),
          Paint()..color = Colors.white..strokeWidth = 2.2..strokeCap = StrokeCap.round,
        );
      case HatKind.bandana:
        final band = Path()
          ..moveTo(-20, -2)
          ..quadraticBezierTo(-14, -16, 0, -16)
          ..quadraticBezierTo(14, -16, 20, -2)
          ..lineTo(-20, -2)
          ..close();
        _shape(canvas, band, c1, line, w: 2.6);
        for (final (dx, dy) in [(-8.0, -8.0), (0.0, -11.0), (8.0, -8.0)]) {
          canvas.drawCircle(Offset(dx, dy), 1.6, Paint()..color = Colors.white70);
        }
        // Knotted tail.
        final knot = Path()
          ..moveTo(18, -4)
          ..quadraticBezierTo(26, -2, 24, 8)
          ..quadraticBezierTo(18, 4, 17, 0)
          ..close();
        _shape(canvas, knot, c1, line, w: 2.2);
      case HatKind.wizardHat:
        final cone = Path()
          ..moveTo(-16, 0)
          ..quadraticBezierTo(-8, -24, 2, -40)
          ..quadraticBezierTo(14, -22, 16, 0)
          ..close();
        _shape(canvas, cone, c1, line, w: 2.8);
        _rrect(
          canvas,
          RRect.fromRectAndRadius(
              Rect.fromLTWH(-20, -4, 40, 9), const Radius.circular(4)),
          _darken(c1, 0.15),
          line,
          w: 2.4,
        );
        // Star on the cone.
        final star = Path()
          ..moveTo(0, -26)
          ..lineTo(2.6, -20.5)
          ..lineTo(8.5, -19.5)
          ..lineTo(4, -15.5)
          ..lineTo(5.4, -9.8)
          ..lineTo(0, -12.8)
          ..lineTo(-5.4, -9.8)
          ..lineTo(-4, -15.5)
          ..lineTo(-8.5, -19.5)
          ..lineTo(-2.6, -20.5)
          ..close();
        canvas.drawPath(star, Paint()..color = _kGold);
      case HatKind.ninjaBand:
        _rrect(
          canvas,
          RRect.fromRectAndRadius(
              Rect.fromLTWH(-24, -14, 48, 10), const Radius.circular(5)),
          c1,
          line,
          w: 2.4,
        );
        // Tail flying behind.
        final tailBand = Path()
          ..moveTo(-24, -13)
          ..quadraticBezierTo(-36, -14, -42, -6 + math.sin(t * 4) * 3)
          ..quadraticBezierTo(-34, -8, -24, -5)
          ..close();
        _shape(canvas, tailBand, c1, line, w: 2.2);
        canvas.drawCircle(const Offset(10, -9), 2.4, Paint()..color = Colors.white70);
      case HatKind.chefToque:
        final puff = Path()
          ..moveTo(-15, -4)
          ..quadraticBezierTo(-20, -26, -6, -24)
          ..quadraticBezierTo(-4, -34, 4, -30)
          ..quadraticBezierTo(16, -32, 15, -20)
          ..quadraticBezierTo(22, -16, 15, -4)
          ..close();
        _shape(canvas, puff, Colors.white, line, w: 2.8);
        _rrect(
          canvas,
          RRect.fromRectAndRadius(
              Rect.fromLTWH(-16, -6, 32, 9), const Radius.circular(4)),
          c1 == Colors.white ? const Color(0xFFE8E2D4) : c1,
          line,
          w: 2.4,
        );
      case HatKind.strawHat:
        _oval(
          canvas,
          Rect.fromCenter(center: const Offset(0, -2), width: 46, height: 12),
          c1,
          line,
          w: 2.6,
        );
        final dome = Path()
          ..moveTo(-14, -3)
          ..quadraticBezierTo(-12, -18, 0, -18)
          ..quadraticBezierTo(12, -18, 14, -3)
          ..close();
        _shape(canvas, dome, c1, line, w: 2.6);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(-15, -6, 30, 5), const Radius.circular(2.5)),
          Paint()..color = _kCherryHat,
        );
        canvas.drawCircle(const Offset(12, -8), 3.6, Paint()..color = _kCherryHat);
        canvas.drawCircle(const Offset(12, -8), 1.4, Paint()..color = _kGold);
      case HatKind.kabukiWig:
        for (final side in [-1.0, 1.0]) {
          final puffWig = Path()
            ..moveTo(side * 8, -4)
            ..quadraticBezierTo(side * 26, -8, side * 22, -20)
            ..quadraticBezierTo(side * 14, -14, side * 8, -4)
            ..close();
          _shape(canvas, puffWig, c1, line, w: 2.4);
        }
        // Red comb on top.
        final comb = Path()
          ..moveTo(-4, -6)
          ..quadraticBezierTo(-2, -20, 0, -22)
          ..quadraticBezierTo(2, -20, 4, -6)
          ..close();
        _shape(canvas, comb, _kCherryHat, line, w: 2.4);
      case HatKind.icicleCrown:
        for (var i = -2; i <= 2; i++) {
          final h = 14.0 + (i == 0 ? 10 : (i.isEven ? 4 : 0));
          final spike = Path()
            ..moveTo(i * 8 - 3.4, 0.0)
            ..lineTo(i * 8.0, -h)
            ..lineTo(i * 8 + 3.4, 0.0)
            ..close();
          _shape(canvas, spike, i == 0 ? c2 : c1, line, w: 2.2);
        }
        canvas.drawCircle(
            Offset(0, -26 + math.sin(t * 2) * 1.5), 2.6,
            Paint()..color = Colors.white);
      case HatKind.beeAntennae:
        for (final side in [-1.0, 1.0]) {
          canvas.drawLine(
            Offset(side * 7, 4),
            Offset(side * 12, -15),
            Paint()..color = line..strokeWidth = 4.4..strokeCap = StrokeCap.round,
          );
          _oval(
            canvas,
            Rect.fromCircle(center: Offset(side * 13, -19), radius: 6.5),
            _kGold,
            line,
            w: 2.2,
          );
        }
      case HatKind.featherCrest:
        for (var i = -1; i <= 1; i++) {
          canvas.save();
          canvas.rotate(i * 0.35);
          final feather = Path()
            ..moveTo(0, 2)
            ..quadraticBezierTo(-5, -14, 0, -26)
            ..quadraticBezierTo(5, -14, 0, 2)
            ..close();
          _shape(canvas, feather, i == 0 ? c1 : _darken(c1, 0.1), line, w: 2.2);
          canvas.drawCircle(Offset(0, -19), 2.4, Paint()..color = _kGold);
          canvas.restore();
        }
      case HatKind.vikingHelm:
        final domeHelm = Path()
          ..moveTo(-16, 0)
          ..quadraticBezierTo(-16, -18, 0, -20)
          ..quadraticBezierTo(16, -18, 16, 0)
          ..close();
        _shape(canvas, domeHelm, c1, line, w: 2.8);
        canvas.drawCircle(const Offset(0, -12), 3.4, Paint()..color = _kSteel);
        canvas.drawCircle(const Offset(0, -12), 1.6, Paint()..color = Colors.white70);
        for (final side in [-1.0, 1.0]) {
          final horn = Path()
            ..moveTo(side * 15, -8)
            ..quadraticBezierTo(side * 28, -12, side * 26, -24)
            ..quadraticBezierTo(side * 20, -16, side * 13, -12)
            ..close();
          _shape(canvas, horn, const Color(0xFFF2E4C4), line, w: 2.4);
        }
      case HatKind.crownGold:
        canvas.save();
        canvas.scale(1.22, 1.25);
        final crown = Path()
          ..moveTo(-14, 3)
          ..lineTo(-16, -12)
          ..lineTo(-8, -5)
          ..lineTo(0, -16)
          ..lineTo(8, -5)
          ..lineTo(16, -12)
          ..lineTo(14, 3)
          ..close();
        _shape(canvas, crown, c1, line, w: 2.6);
        canvas.drawCircle(const Offset(0, -4), 2.6, Paint()..color = _kCherryHat);
        canvas.drawCircle(const Offset(-9, -1), 1.8, Paint()..color = _kTealHat);
        canvas.drawCircle(const Offset(9, -1), 1.8, Paint()..color = _kTealHat);
        canvas.restore();
      case HatKind.haloRing:
        final ringBob = math.sin(t * 2) * 2.5;
        final rect = Rect.fromCenter(
            center: Offset(0, -30 + ringBob), width: 34, height: 11);
        canvas.drawOval(
          rect,
          Paint()
            ..color = _kGold.withValues(alpha: 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8,
        );
        canvas.drawOval(
          rect,
          Paint()
            ..color = c1
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
      case HatKind.flameCrest:
        for (var i = -1; i <= 1; i++) {
          final flick = math.sin(t * 9 + i * 2) * 2;
          final flame = Path()
            ..moveTo(i * 5.5 - 3.6, 5)
            ..quadraticBezierTo(i * 5.5 - 5, -10, i * 5.5 + flick * 0.4, -20 - (i == 0 ? 7 : 0))
            ..quadraticBezierTo(i * 5.5 + 5, -8, i * 5.5 + 3.6, 5)
            ..close();
          _shape(canvas, flame, i == 0 ? c1 : _darken(c1, 0.08), line, w: 2.2);
        }
      case HatKind.foxMask:
        // A half-mask perched on the forehead.
        final mask = Path()
          ..moveTo(-14, -4)
          ..quadraticBezierTo(-10, -18, 0, -16)
          ..quadraticBezierTo(10, -18, 14, -4)
          ..quadraticBezierTo(6, -8, 0, -6)
          ..quadraticBezierTo(-6, -8, -14, -4)
          ..close();
        _shape(canvas, mask, c1, line, w: 2.6);
        canvas.drawLine(
          const Offset(-4, -12),
          const Offset(4, -12),
          Paint()..color = _kGold..strokeWidth = 2,
        );
      case HatKind.antennaLight:
        canvas.drawLine(
          const Offset(0, 0),
          Offset(3 + math.sin(t * 3) * 2, -18),
          Paint()..color = line..strokeWidth = 3..strokeCap = StrokeCap.round,
        );
        final blink = 0.5 + 0.5 * math.sin(t * 6);
        canvas.drawCircle(
          Offset(3 + math.sin(t * 3) * 2, -21),
          6,
          Paint()..color = const Color(0xFF6FF2E0).withValues(alpha: 0.25 * blink),
        );
        canvas.drawCircle(
          Offset(3 + math.sin(t * 3) * 2, -21),
          3,
          Paint()..color = Color.lerp(const Color(0xFF4ED8C6), Colors.white, blink)!,
        );
      case HatKind.moonCirclet:
        final crescent = Path()
          ..moveTo(-2, -22)
          ..quadraticBezierTo(-16, -16, -14, -2)
          ..quadraticBezierTo(-6, -12, 4, -14)
          ..quadraticBezierTo(0, -20, -2, -22)
          ..close();
        _shape(canvas, crescent, c1, line, w: 2.4);
        canvas.drawCircle(
            Offset(10, -20 + math.sin(t * 2) * 2), 2,
            Paint()..color = Colors.white);
      case HatKind.sunCorona:
        // Radiant disc with alternating rays.
        final pulse = 0.5 + 0.5 * math.sin(t * 2.5);
        for (var i = 0; i < 10; i++) {
          final a = i * math.pi / 5 + t * 0.3;
          final len = i.isEven ? 26 + pulse * 4 : 18;
          final ray = Path()
            ..moveTo(math.cos(a - 0.12) * 14, -14 + math.sin(a - 0.12) * 8)
            ..lineTo(math.cos(a) * len, -14 + math.sin(a) * len * 0.7)
            ..lineTo(math.cos(a + 0.12) * 14, -14 + math.sin(a + 0.12) * 8)
            ..close();
          canvas.drawPath(
            ray,
            Paint()..color = const Color(0xFFFFD86B).withValues(alpha: 0.85),
          );
        }
        canvas.drawCircle(
            const Offset(0, -14), 15, Paint()..color = const Color(0xFFFFE9A8));
        canvas.drawCircle(
            const Offset(0, -14), 15,
            Paint()..color = c1..style = PaintingStyle.stroke..strokeWidth = 2.4);
      case HatKind.pearlDive:
        _rrect(
          canvas,
          RRect.fromRectAndRadius(
              Rect.fromLTWH(-20, -16, 40, 12), const Radius.circular(6)),
          c1,
          line,
          w: 2.6,
        );
        // Goggles over the crown.
        for (final side in [-1.0, 1.0]) {
          _oval(
            canvas,
            Rect.fromCenter(center: Offset(side * 10, -14), width: 15, height: 12),
            const Color(0xFFBFE9FF),
            line,
            w: 2.4,
          );
        }
      case HatKind.crystalHalo:
        for (var i = 0; i < 5; i++) {
          final a = t * 0.9 + i * 2 * math.pi / 5;
          final cy = -22 + math.sin(t * 2 + i) * 3;
          final cx = math.cos(a) * 20;
          final cyy = cy + math.sin(a) * 7;
          final gem = Path()
            ..moveTo(cx, cyy - 5)
            ..lineTo(cx + 3.6, cyy)
            ..lineTo(cx, cyy + 5)
            ..lineTo(cx - 3.6, cyy)
            ..close();
          _shape(
            canvas,
            gem,
            Color.lerp(const Color(0xFFA5E3F8), Colors.white, 0.25)!,
            line,
            w: 1.8,
          );
        }
      case HatKind.comet:
        final star = Path()
          ..moveTo(6, -24)
          ..lineTo(9, -17)
          ..lineTo(16, -16)
          ..lineTo(11, -11)
          ..lineTo(12, -4)
          ..lineTo(6, -7)
          ..lineTo(0, -4)
          ..lineTo(1, -11)
          ..lineTo(-4, -16)
          ..lineTo(3, -17)
          ..close();
        _shape(canvas, star, c1, line, w: 2.2);
        for (var i = 1; i <= 3; i++) {
          canvas.drawCircle(
            Offset(6 - i * 7, -20 + i * 4),
            3.2 - i * 0.6,
            Paint()..color = c1.withValues(alpha: 0.7 - i * 0.2),
          );
        }
      case HatKind.treasurePile:
        // A heap of coins crowned by one fat gem.
        for (final (dx, dy) in [
          (-14.0, -4.0), (0.0, -6.0), (14.0, -4.0),
          (-7.0, -10.0), (7.0, -10.0),
        ]) {
          _oval(
            canvas,
            Rect.fromCenter(center: Offset(dx, dy), width: 11, height: 8),
            _kGold,
            line,
            w: 2,
          );
          canvas.drawCircle(Offset(dx, dy), 1.6, Paint()..color = const Color(0xFFFFF3C4));
        }
        final gem = Path()
          ..moveTo(0, -22)
          ..lineTo(7, -14)
          ..lineTo(0, -6)
          ..lineTo(-7, -14)
          ..close();
        _shape(canvas, gem, _kCherryHat, line, w: 2.2);
        canvas.drawCircle(const Offset(-2, -16), 1.6, Paint()..color = Colors.white70);
      case HatKind.prismCrown:
        for (var i = -2; i <= 2; i++) {
          final shard = Path()
            ..moveTo(i * 7 - 3.0, 0.0)
            ..lineTo(i * 7 + (i * 1.0), -(12.0 + (2 - i.abs()) * 8))
            ..lineTo(i * 7 + 3.0, 0.0)
            ..close();
          final tint = [
            const Color(0xFFFF8FB1),
            const Color(0xFF8FDFF0),
            const Color(0xFFB9F0D4),
            const Color(0xFFC9AEE8),
            const Color(0xFFFFD86B),
          ][i + 2];
          _shape(canvas, shard, tint, line, w: 2.2);
        }
      case HatKind.voidHalo:
        final ringBob = math.sin(t * 1.6) * 2.5;
        final rect = Rect.fromCenter(
            center: Offset(0, -28 + ringBob), width: 38, height: 12);
        canvas.drawOval(
          rect,
          Paint()
            ..color = const Color(0xFF8A6FD8).withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9,
        );
        canvas.drawOval(
          rect,
          Paint()
            ..color = c1
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.4,
        );
        // Eclipse bead.
        canvas.drawCircle(
          Offset(rect.right, rect.center.dy),
          3,
          Paint()..color = _kGold,
        );
    }
    canvas.restore();
  }

  static const _kLeafGreen = Color(0xFF6FBF63);
  static const _kLeafDark = Color(0xFF4E9E5F);
  static const _kCherryHat = Color(0xFFE5484D);
  static const _kTealHat = Color(0xFF5FC9C0);

  /// A single curly hair — piglets without hats get one on top.
  static void _paintBabyCurl(Canvas canvas, double bw, double bh, double bodyY) {
    final top = bodyY - bh / 2 + 7;
    final curl = Path()
      ..moveTo(0, top + 2)
      ..quadraticBezierTo(-2, top - 6, 5, top - 9)
      ..quadraticBezierTo(10, top - 7, 7, top - 3);
    canvas.drawPath(
      curl,
      Paint()
        ..color = const Color(0xFF43302E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
  }

  // -- held props ----------------------------------------------------------------

  static void _paintFore(Canvas canvas, PigDesign d, double t, _Stage stage) {
    if (d.fore == ForeKind.none) return;
    final line = d.outline;
    final c1 = d.foreColor ?? _kGold;
    canvas.save();
    canvas.translate(26, -26);
    canvas.rotate(-0.25 + math.sin(t * 2.5) * 0.04);

    switch (d.fore) {
      case ForeKind.none:
        break;
      case ForeKind.sword:
        // A cutlass held diagonally across the chest.
        canvas.drawLine(
          const Offset(-18, 14),
          const Offset(14, -18),
          Paint()
            ..color = c1
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawLine(
          const Offset(-18, 14),
          const Offset(14, -18),
          Paint()
            ..color = line
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
        canvas.drawLine(
          const Offset(-14, 18),
          const Offset(-6, 6),
          Paint()..color = const Color(0xFFC89B66)..strokeWidth = 5..strokeCap = StrokeCap.round,
        );
      case ForeKind.wand:
        canvas.drawLine(
          const Offset(0, 14),
          const Offset(0, -14),
          Paint()..color = const Color(0xFFC89B66)..strokeWidth = 4..strokeCap = StrokeCap.round,
        );
        final star = Path()
          ..moveTo(0, -22)
          ..lineTo(2.4, -17)
          ..lineTo(8, -16)
          ..lineTo(4, -12)
          ..lineTo(5, -6.6)
          ..lineTo(0, -9.4)
          ..lineTo(-5, -6.6)
          ..lineTo(-4, -12)
          ..lineTo(-8, -16)
          ..lineTo(-2.4, -17)
          ..close();
        _shape(canvas, star, c1, line, w: 2.2);
      case ForeKind.spoon:
        canvas.drawLine(
          const Offset(0, 16),
          const Offset(4, -10),
          Paint()..color = const Color(0xFFC89B66)..strokeWidth = 5..strokeCap = StrokeCap.round,
        );
        _oval(
          canvas,
          Rect.fromCenter(center: const Offset(6, -16), width: 15, height: 18),
          const Color(0xFFB98A5E),
          line,
          w: 2.4,
        );
      case ForeKind.fan:
        for (var i = -2; i <= 2; i++) {
          canvas.save();
          canvas.rotate(-0.5 + i * 0.25);
          final spoke = Path()
            ..moveTo(0, 14)
            ..quadraticBezierTo(-4, -8, 0, -22)
            ..quadraticBezierTo(4, -8, 0, 14)
            ..close();
          _shape(canvas, spoke, i.isEven ? c1 : Colors.white, line, w: 2);
          canvas.restore();
        }
      case ForeKind.trowel:
        canvas.drawLine(
          const Offset(-6, 14),
          const Offset(4, -2),
          Paint()..color = const Color(0xFFC89B66)..strokeWidth = 5..strokeCap = StrokeCap.round,
        );
        final blade = Path()
          ..moveTo(2, -2)
          ..quadraticBezierTo(14, -6, 16, -18)
          ..quadraticBezierTo(4, -16, 0, -4)
          ..close();
        _shape(canvas, blade, c1, line, w: 2.4);
      case ForeKind.shuriken:
        final star = Path();
        for (var i = 0; i < 4; i++) {
          final a = i * math.pi / 2;
          final b = a + math.pi / 8;
          star.moveTo(0, 0);
          star.lineTo(math.cos(a) * 14, math.sin(a) * 14);
          star.lineTo(math.cos(b) * 5, math.sin(b) * 5);
        }
        star.close();
        _shape(canvas, star, c1, line, w: 2.2);
        canvas.drawCircle(Offset.zero, 2, Paint()..color = line);
      case ForeKind.goldCoin:
        _oval(
          canvas,
          Rect.fromCircle(center: Offset.zero, radius: 13),
          c1,
          line,
          w: 2.6,
        );
        canvas.drawCircle(
            Offset.zero, 8.6,
            Paint()..color = const Color(0xFFFFF3C4).withValues(alpha: 0.9));
        canvas.drawCircle(Offset.zero, 8.6,
            Paint()..color = _deepGold..style = PaintingStyle.stroke..strokeWidth = 1.8);
      case ForeKind.gem:
        final heart = Path()
          ..moveTo(0, 10)
          ..lineTo(-12, -2)
          ..quadraticBezierTo(-12, -12, -4, -10)
          ..quadraticBezierTo(0, -8, 4, -10)
          ..quadraticBezierTo(12, -12, 12, -2)
          ..lineTo(0, 10)
          ..close();
        _shape(canvas, heart, c1, line, w: 2.6);
        canvas.drawCircle(const Offset(-4, -4), 2.2, Paint()..color = Colors.white70);
      case ForeKind.iceCream:
        final cone = Path()
          ..moveTo(-9, 0)
          ..lineTo(9, 0)
          ..lineTo(0, 20)
          ..close();
        _shape(canvas, cone, const Color(0xFFE0B95C), line, w: 2.4);
        _oval(
          canvas,
          Rect.fromCenter(center: const Offset(0, -6), width: 20, height: 16),
          c1,
          line,
          w: 2.4,
        );
        canvas.drawCircle(const Offset(4, -14), 4.4, Paint()..color = c1);
      case ForeKind.corn:
        final ear = Path()
          ..moveTo(-6, 14)
          ..quadraticBezierTo(-9, -6, 0, -18)
          ..quadraticBezierTo(9, -6, 6, 14)
          ..close();
        _shape(canvas, ear, c1, line, w: 2.4);
        for (var r = 0; r < 4; r++) {
          for (var ccc = 0; ccc < 2; ccc++) {
            canvas.drawCircle(
              Offset(-3 + ccc * 6 + (r.isOdd ? 1.5 : 0), 8 - r * 6.5),
              1.3,
              Paint()..color = _deepGold,
            );
          }
        }
      case ForeKind.pearl:
        final glow = 0.5 + 0.5 * math.sin(t * 3);
        canvas.drawCircle(
          Offset.zero,
          16,
          Paint()..color = c1.withValues(alpha: 0.25 + 0.15 * glow),
        );
        _oval(
          canvas,
          Rect.fromCircle(center: Offset.zero, radius: 10),
          Color.lerp(c1, Colors.white, 0.4)!,
          line,
          w: 2.4,
        );
        canvas.drawCircle(
            const Offset(-3, -3), 2.6, Paint()..color = Colors.white70);
      case ForeKind.drumstick:
        _oval(
          canvas,
          Rect.fromCenter(center: const Offset(0, -6), width: 20, height: 16),
          const Color(0xFFE8A05C),
          line,
          w: 2.4,
        );
        canvas.drawLine(
          const Offset(0, 4),
          const Offset(3, 18),
          Paint()..color = Color(0xFFF3EAD8)..strokeWidth = 5..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(const Offset(5, 19), 3.4, Paint()..color = Colors.white70);
      case ForeKind.umbrella:
        canvas.drawLine(
          const Offset(0, 18),
          const Offset(2, -10),
          Paint()..color = _kLeafDark..strokeWidth = 3.4..strokeCap = StrokeCap.round,
        );
        final canopy = Path()
          ..moveTo(-18, -10)
          ..quadraticBezierTo(-8, -26, 2, -10)
          ..quadraticBezierTo(10, -24, 20, -10)
          ..quadraticBezierTo(0, -14, -18, -10)
          ..close();
        _shape(canvas, canopy, const Color(0xFF6FBF63), line, w: 2.4);
    }
    canvas.restore();
  }

  static const _deepGold = Color(0xFFDDA322);

  // -- sleep ---------------------------------------------------------------------

  static void _paintZzz(Canvas canvas, double t) {
    for (var i = 0; i < 3; i++) {
      final cycle = (t * 0.45 + i * 0.33) % 1.0;
      final alpha = (1 - cycle) * 0.8;
      final p = Paint()
        ..color = const Color(0xFF8E9BC4).withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      final s = 4.0 + i * 2.6;
      final x = 34 + cycle * 14 + i * 6;
      final y = -96 - cycle * 18 - i * 9;
      final z = Path()
        ..moveTo(x - s, y - s * 0.7)
        ..lineTo(x + s, y - s * 0.7)
        ..lineTo(x - s, y + s * 0.7)
        ..lineTo(x + s, y + s * 0.7);
      canvas.drawPath(z, p);
    }
  }
}
