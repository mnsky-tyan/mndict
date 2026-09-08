import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/worlds.dart';

/// Where in the real day the scene's sky sits (farm_view keeps the
/// real-clock mapping; painters only need the bucket).
enum SkyPhase { dawn, day, dusk, night }

/// Paints one world's full backdrop — sky, horizon, ground and props —
/// into a canvas of [size]. The herd, the care stations (trough, shower,
/// nest) and the yard decor draw on top in farm_view. The style follows
/// the pigs: flat saturated fills, chunky rounded shapes, no airbrush.
class WorldBackdrop {
  static void paint(
    Canvas canvas,
    Size size,
    WorldId id, {
    required SkyPhase phase,
    required bool night,
    required int level,
    required double t,
  }) {
    switch (id) {
      case WorldId.meadow:
        _meadow(canvas, size, phase, night, level, t);
      case WorldId.beach:
        _beach(canvas, size, phase, night, level, t);
      case WorldId.ship:
        _ship(canvas, size, phase, night, level, t);
      case WorldId.skyisland:
        _skyIsland(canvas, size, phase, night, level, t);
    }
  }

  static bool _isNight(SkyPhase phase, bool night) =>
      phase == SkyPhase.night || night;

  static double _hash(int n) {
    final s = math.sin(n * 127.1 + 311.7) * 43758.5453;
    return s - s.floor();
  }

  // -- shared sky ---------------------------------------------------------------

  static void _sky(
    Canvas canvas,
    double w,
    double h,
    double horizon,
    SkyPhase phase,
    bool night,
    double t, {
    List<Color>? dayColors,
    bool seagulls = false,
  }) {
    final isNight = _isNight(phase, night);
    final dawnish = phase == SkyPhase.dawn || phase == SkyPhase.dusk;
    final colors = isNight
        ? const [Color(0xFF0D1230), Color(0xFF232048), Color(0xFF4A3A58)]
        : dawnish
            ? const [Color(0xFF7FA8D8), Color(0xFFF2B98A), Color(0xFFFFE3B0)]
            : (dayColors ?? const [Color(0xFF9ED9F2), Color(0xFFC8E8EF), Color(0xFFF6EFD9)]);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, horizon + 2),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(Rect.fromLTWH(0, 0, w, horizon + 2)),
    );

    if (isNight) {
      final moonCenter = Offset(w * 0.80, h * 0.08);
      canvas.drawCircle(moonCenter, 54,
          Paint()..color = const Color(0xFFF4EFD0).withValues(alpha: 0.08));
      canvas.drawCircle(moonCenter, 38,
          Paint()..color = const Color(0xFFF4EFD0).withValues(alpha: 0.15));
      canvas.drawCircle(moonCenter, 19, Paint()..color = const Color(0xFFF2ECC4));
      canvas.drawCircle(moonCenter.translate(8, -5), 16,
          Paint()..color = colors[0]);
      for (var i = 0; i < 40; i++) {
        final sx = _hash(i) * w;
        final sy = _hash(i + 50) * horizon * 0.85;
        final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * (0.8 + _hash(i + 99)) + i));
        canvas.drawCircle(
          Offset(sx, sy),
          0.8 + _hash(i + 7) * 1.2,
          Paint()..color = Colors.white.withValues(alpha: 0.85 * tw),
        );
      }
    } else {
      final sunX = dawnish ? w * 0.30 : w * 0.82;
      final sunY = dawnish ? horizon * 0.55 : h * 0.09;
      final sun = Offset(sunX, sunY);
      canvas.drawCircle(
          sun, 66, Paint()..color = const Color(0xFFFFE9A8).withValues(alpha: 0.16));
      canvas.drawCircle(
          sun, 48, Paint()..color = const Color(0xFFFFE9A8).withValues(alpha: 0.35));
      canvas.drawCircle(
          sun,
          dawnish ? 26 : 20,
          Paint()
            ..color = dawnish ? const Color(0xFFFFC978) : const Color(0xFFFFE18A));
      // God rays.
      for (var i = 0; i < 3; i++) {
        final sway = math.sin(t * 0.22 + i * 2.1) * 0.05;
        canvas.save();
        canvas.translate(sun.dx, sun.dy);
        canvas.rotate((dawnish ? 1.2 : 1.95) + i * 0.42 + sway);
        canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..lineTo(-w * 0.34, h)
            ..lineTo(-w * 0.20, h)
            ..close(),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.16),
                Colors.white.withValues(alpha: 0.0),
              ],
            ).createShader(Rect.fromLTWH(-w * 0.34, 0, w * 0.14, h)),
        );
        canvas.restore();
      }
    }

    // Drifting clouds (shared).
    for (var i = 0; i < 4; i++) {
      final cx = ((_hash(i + 400) + t * (0.006 + 0.003 * _hash(i + 401))) % 1.3 - 0.15) * w;
      final cy = h * (0.05 + 0.05 * i);
      final cloud = Paint()..color = Colors.white.withValues(alpha: 0.85);
      final shade = Paint()..color = const Color(0xFFC9D8EC).withValues(alpha: 0.55);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: 84, height: 24), cloud);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx - 26, cy + 4), width: 46, height: 17), cloud);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx + 27, cy + 3), width: 52, height: 20), cloud);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy + 10), width: 74, height: 9), shade);
    }

    // Seagulls: two-arc birds crossing the sky.
    if (seagulls && !_isNight(phase, night)) {
      for (var i = 0; i < 3; i++) {
        final gx = ((t * 0.025 + _hash(i + 50) * 1.4) % 1.4 - 0.2) * w;
        final gy = h * (0.10 + 0.06 * i) + math.sin(t * 1.6 + i * 2.0) * 6;
        final flap = math.sin(t * 6 + i * 1.7) * 3.2;
        final wing = Paint()
          ..color = Colors.white.withValues(alpha: 0.95)
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(gx - 8, gy - flap), Offset(gx, gy), wing);
        canvas.drawLine(Offset(gx, gy), Offset(gx + 8, gy - flap), wing);
      }
    }
  }

  // -- meadow (the home world; yard features unlock with level) ------------------

  static void _meadow(Canvas canvas, Size size, SkyPhase phase, bool night,
      int level, double t) {
    final w = size.width, h = size.height;
    final horizon = h * 0.33;
    final isNight = _isNight(phase, night);

    _sky(canvas, w, h, horizon, phase, night, t, seagulls: false);

    // Rolling back hills.
    canvas.drawPath(
      Path()
        ..moveTo(0, horizon + 6)
        ..quadraticBezierTo(w * 0.18, horizon - 58, w * 0.40, horizon - 14)
        ..quadraticBezierTo(w * 0.58, horizon + 24, w * 0.78, horizon - 30)
        ..quadraticBezierTo(w * 0.90, horizon - 50, w, horizon - 34)
        ..lineTo(w, horizon + 6)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isNight
              ? const [Color(0xFF3A466B), Color(0xFF33415F)]
              : const [Color(0xFFB9D89B), Color(0xFFA5CD84)],
        ).createShader(Rect.fromLTWH(0, horizon - 52, w, h)),
    );

    // Ground.
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, w, h - horizon),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isNight
              ? const [Color(0xFF31405C), Color(0xFF27344C)]
              : const [Color(0xFF9CCB77), Color(0xFF7FBA5E)],
        ).createShader(Rect.fromLTWH(0, horizon, w, h - horizon)),
    );
    if (!isNight && phase == SkyPhase.day) {
      final poolCenter = Offset(w * 0.72, horizon + (h - horizon) * 0.30);
      canvas.drawCircle(
        poolCenter,
        w * 0.50,
        Paint()
          ..shader = RadialGradient(colors: [
            const Color(0xFFFFF2BC).withValues(alpha: 0.20),
            const Color(0xFFFFF2BC).withValues(alpha: 0.0),
          ]).createShader(Rect.fromCircle(center: poolCenter, radius: w * 0.50)),
      );
    }

    if (level >= 2) _pond(canvas, w, h, horizon, t, isNight);
    _fence(canvas, w, horizon, level >= 5);
    _barn(canvas, _hubX(w), horizon, isNight);
    if (level >= 3) _windmill(canvas, w * 0.52, horizon, t);
    if (level >= 6) _orchard(canvas, w, horizon);
    _trees(canvas, w, horizon, isNight);
    if (level >= 4) _flowerGarden(canvas, w, h, horizon);
    _flora(canvas, w, h, isNight);
  }

  static double _hubX(double w) => w * 0.30;

  static void _pond(Canvas canvas, double w, double h, double horizon,
      double t, bool isNight) {
    final cx = w * 0.66, cy = h * 0.58;
    final water = Rect.fromCenter(center: Offset(cx, cy), width: 210, height: 96);
    canvas.drawOval(
      water,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: isNight
              ? const [Color(0xFF3E5C8A), Color(0xFF2C4568)]
              : const [Color(0xFF8ED4EC), Color(0xFF5FA8D6)],
        ).createShader(water),
    );
    for (var i = 0; i < 3; i++) {
      final phase = (t * 0.5 + i * 0.33) % 1.0;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx - 30 + i * 34, cy + 8 - i * 6),
          width: 30 + phase * 46,
          height: 10 + phase * 14,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: 0.30 * (1 - phase)),
      );
    }
    for (final (i, pad) in [(-42, -14), (18, 20), (58, -6)].indexed) {
      canvas.drawCircle(
        Offset(cx + pad.$1, cy + pad.$2),
        8 + i * 1.5,
        Paint()..color = const Color(0xFF4E9E5F),
      );
    }
  }

  static void _windmill(Canvas canvas, double cx, double horizon, double t) {
    final bodyTop = horizon - 96.0;
    final body = Path()
      ..moveTo(cx - 26, horizon + 4)
      ..lineTo(cx - 15, bodyTop)
      ..lineTo(cx + 15, bodyTop)
      ..lineTo(cx + 26, horizon + 4)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFFE8DCC3));
    canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFFB49F79));
    canvas.drawCircle(Offset(cx, bodyTop), 13, Paint()..color = const Color(0xFFB5574A));
    canvas.save();
    canvas.translate(cx, bodyTop);
    canvas.rotate(t * 0.5);
    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.rotate(i * math.pi / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(-3.4, -46, 6.8, 34), const Radius.circular(3)),
        Paint()..color = const Color(0xFFF6EFE2),
      );
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, 3.4, Paint()..color = const Color(0xFF7A6A4F));
    canvas.restore();
  }

  static void _flowerGarden(Canvas canvas, double w, double h, double horizon) {
    final cx = w * 0.42, cy = h * 0.47;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: 150, height: 44),
      Paint()..color = const Color(0xFF8FBE6C),
    );
    final petals = [
      const Color(0xFFFF9EC3),
      const Color(0xFFF7E8A0),
      const Color(0xFFF3F6FF),
      const Color(0xFFE8A0F7),
    ];
    for (var i = 0; i < 9; i++) {
      final fx = cx - 60 + _hash(i + 41) * 120;
      final fy = cy - 12 + _hash(i + 87) * 24;
      canvas.drawCircle(
          Offset(fx, fy - 3), 3.4, Paint()..color = petals[i % petals.length]);
      canvas.drawCircle(
          Offset(fx, fy - 3), 1.2, Paint()..color = const Color(0xFFFFD86B));
    }
  }

  static void _fence(Canvas canvas, double w, double horizon, bool gold) {
    final wood = gold ? const Color(0xFFC7A45A) : const Color(0xFFB98A5A);
    final woodDark = gold ? const Color(0xFFB08D42) : const Color(0xFF9C7047);
    final post = Paint()..color = wood;
    final rail = Paint()..color = woodDark;
    for (double x = -8; x < w + 20; x += 64) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, horizon - 34, 7, 38), const Radius.circular(3)),
        post,
      );
      canvas.drawCircle(Offset(x + 3.5, horizon - 34), 3.5, post);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, horizon - 27, w, 5), const Radius.circular(2.5)),
      rail,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, horizon - 13, w, 5), const Radius.circular(2.5)),
      rail,
    );
    if (gold) {
      for (double x = -8; x < w + 20; x += 64) {
        canvas.drawCircle(
            Offset(x + 3.5, horizon - 30), 4.2, Paint()..color = const Color(0xFFF7C948));
      }
    }
  }

  static void _barn(Canvas canvas, double cx, double horizon, bool isNight) {
    final body = isNight ? const Color(0xFF7A4A3C) : const Color(0xFFD9694F);
    final roof = isNight ? const Color(0xFF5A3630) : const Color(0xFFB54B37);
    final trim = isNight ? const Color(0xFF9C8C7A) : const Color(0xFFF6EFE2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, horizon - 28), width: 96, height: 58),
        const Radius.circular(5),
      ),
      Paint()..color = body,
    );
    final roofPath = Path()
      ..moveTo(cx - 58, horizon - 52)
      ..lineTo(cx, horizon - 82)
      ..lineTo(cx + 58, horizon - 52)
      ..close();
    canvas.drawPath(roofPath, Paint()..color = roof);
    final door = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, horizon - 18), width: 28, height: 40),
      const Radius.circular(3),
    );
    canvas.drawRRect(door, Paint()..color = trim);
    final doorX = Paint()
      ..color = roof
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - 13, horizon - 36), Offset(cx + 13, horizon), doorX);
    canvas.drawLine(Offset(cx + 13, horizon - 36), Offset(cx - 13, horizon), doorX);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, horizon - 62), width: 17, height: 15),
        const Radius.circular(3),
      ),
      Paint()..color = isNight ? const Color(0xFFFFD97A) : trim,
    );
    if (isNight) {
      canvas.drawCircle(
        Offset(cx, horizon - 62),
        17,
        Paint()..color = const Color(0xFFFFD97A).withValues(alpha: 0.18),
      );
    }
  }

  static void _orchard(Canvas canvas, double w, double horizon) {
    for (var i = 0; i < 3; i++) {
      final cx = w * (0.56 + i * 0.05);
      final cy = horizon + 26 + i * 12.0;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, cy - 12), width: 6, height: 18),
        Paint()..color = const Color(0xFFA9784E),
      );
      canvas.drawCircle(
          Offset(cx, cy - 30), 16, Paint()..color = const Color(0xFF6BA75B));
      canvas.drawCircle(
          Offset(cx - 5, cy - 26), 2.6, Paint()..color = const Color(0xFFE86A5C));
      canvas.drawCircle(
          Offset(cx + 6, cy - 34), 2.6, Paint()..color = const Color(0xFFE86A5C));
    }
  }

  static void _trees(Canvas canvas, double w, double horizon, bool isNight) {
    final leaf = isNight ? const Color(0xFF46614F) : const Color(0xFF7FB86B);
    final leafDark = isNight ? const Color(0xFF3A5244) : const Color(0xFF6BA75B);
    final trunk = isNight ? const Color(0xFF5C4A38) : const Color(0xFFA9784E);
    void tree(double cx, double scale) {
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset(cx, horizon - 26 * scale),
            width: 9 * scale,
            height: 34 * scale),
        Paint()..color = trunk,
      );
      canvas.drawCircle(Offset(cx - 14 * scale, horizon - 52 * scale),
          17 * scale, Paint()..color = leafDark);
      canvas.drawCircle(Offset(cx + 14 * scale, horizon - 54 * scale),
          18 * scale, Paint()..color = leaf);
      canvas.drawCircle(
          Offset(cx, horizon - 70 * scale), 20 * scale, Paint()..color = leaf);
    }

    tree(w * 0.06, 1.1);
    tree(w * 0.13, 0.8);
    tree(w * 0.44, 0.85);
    tree(w * 0.72, 1.0);
    tree(w * 0.93, 1.0);
    tree(w * 0.975, 0.72);
  }

  static void _flora(Canvas canvas, double w, double h, bool isNight) {
    for (var i = 0; i < 48; i++) {
      final fx0 = _hash(i + 600);
      final fy0 = 0.34 + _hash(i + 700) * 0.52;
      final x = fx0 * w, y = fy0 * h;
      if (i % 3 == 0) {
        final stem = Paint()
          ..color = isNight ? const Color(0xFF4E6B4A) : const Color(0xFF6FAE55)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x, y), Offset(x, y - 7), stem);
        final colors = [
          const Color(0xFFFF9EC3),
          const Color(0xFFF7E8A0),
          const Color(0xFFF3F6FF),
        ];
        canvas.drawCircle(Offset(x, y - 9), 3.2, Paint()..color = colors[i % 3]);
      } else {
        final tuft = Paint()
          ..color = isNight ? const Color(0xFF4E6B4A) : const Color(0xFF74B356)
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x, y), Offset(x - 3, y - 6), tuft);
        canvas.drawLine(Offset(x + 1, y), Offset(x + 1, y - 8), tuft);
        canvas.drawLine(Offset(x + 3, y), Offset(x + 6, y - 5), tuft);
      }
    }
  }

  // -- beach ----------------------------------------------------------------------

  static void _beach(Canvas canvas, Size size, SkyPhase phase, bool night,
      int level, double t) {
    final w = size.width, h = size.height;
    final horizon = h * 0.33;
    final isNight = _isNight(phase, night);

    _sky(canvas, w, h, horizon, phase, night, t,
        dayColors: const [Color(0xFF6FD3F0), Color(0xFFA9E8F2), Color(0xFFFFF2D9)],
        seagulls: true);

    // Distant sea band.
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, w, h * 0.14),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isNight
              ? const [Color(0xFF1E3A5C), Color(0xFF2C4E74)]
              : const [Color(0xFF4FB8DC), Color(0xFF7FD4E8)],
        ).createShader(Rect.fromLTWH(0, horizon, w, h * 0.14)),
    );
    // Sparkle lane on the water.
    if (!isNight) {
      for (var i = 0; i < 12; i++) {
        final sx = _hash(i + 30) * w;
        final sy = horizon + 6 + _hash(i + 31) * h * 0.10;
        final tw = 0.5 + 0.5 * math.sin(t * 2 + i * 2.1);
        canvas.drawCircle(
          Offset(sx, sy),
          1.4,
          Paint()..color = Colors.white.withValues(alpha: 0.6 * tw),
        );
      }
    }
    // Rolling surf line: scalloped foam where sea meets sand.
    final surfY = horizon + h * 0.14;
    final foam = Path()..moveTo(0, surfY + 6);
    for (double x = 0; x <= w; x += 46) {
      foam.quadraticBezierTo(x + 23, surfY - 6 + math.sin(t * 1.4 + x) * 3, x + 46, surfY + 4);
    }
    foam.lineTo(w, surfY + 10);
    foam.lineTo(0, surfY + 10);
    foam.close();
    canvas.drawPath(foam, Paint()..color = isNight ? const Color(0xFF3D5A78) : const Color(0xFFEAF9FF));

    // Sand.
    canvas.drawRect(
      Rect.fromLTWH(0, surfY + 6, w, h - surfY),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isNight
              ? const [Color(0xFF8A7C64), Color(0xFF6E6250)]
              : const [Color(0xFFFBE7B7), Color(0xFFF2D692)],
        ).createShader(Rect.fromLTWH(0, surfY, w, h - surfY)),
    );
    // Wet sand sheen right under the surf.
    canvas.drawRect(
      Rect.fromLTWH(0, surfY + 6, w, 22),
      Paint()
        ..color = isNight
            ? Colors.black26
            : const Color(0xFFDEC68C).withValues(alpha: 0.35),
    );
    // Wave lines pushing in.
    for (var i = 0; i < 2; i++) {
      final wy = surfY + 18 + i * 16 + math.sin(t * 0.9 + i * 2) * 3;
      final wave = Path()..moveTo(w * (0.1 + 0.2 * i), wy);
      wave.quadraticBezierTo(w * 0.4, wy - 5, w * (0.72 - 0.1 * i), wy);
      canvas.drawPath(
        wave,
        Paint()
          ..color = Colors.white.withValues(alpha: isNight ? 0.12 : 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // Palms.
    _palm(canvas, w * 0.10, surfY + 10, 1.15, isNight, t);
    _palm(canvas, w * 0.90, surfY + 4, 0.95, isNight, t, lean: -0.2);

    // Beach hut = the hub (barn tap zone).
    _beachHut(canvas, _hubX(w), surfY + 8, isNight);

    // Umbrella + towel + sandcastle props.
    _umbrella(canvas, w * 0.72, h * 0.55, isNight);
    if (level >= 9) _sandcastle(canvas, w * 0.52, h * 0.78);
    _shells(canvas, w, h, isNight);
  }

  static void _palm(Canvas canvas, double bx, double by, double s,
      bool isNight, double t, {double lean = 0.15}) {
    final trunk = Paint()
      ..color = isNight ? const Color(0xFF6E5340) : const Color(0xFFB5804C)
      ..strokeWidth = 9 * s
      ..strokeCap = StrokeCap.round;
    final top = Offset(bx + lean * 60 * s, by - 120 * s);
    final mid = Offset(bx + lean * 22 * s, by - 60 * s);
    canvas.drawLine(Offset(bx, by), mid, trunk);
    canvas.drawLine(mid, top, trunk..strokeWidth = 7 * s);
    // Fronds.
    for (var i = 0; i < 6; i++) {
      final a = -math.pi + i * math.pi / 5 + math.sin(t * 1.2 + i) * 0.04;
      final frond = Paint()..color = isNight ? const Color(0xFF3E6B4A) : const Color(0xFF4FA85C);
      final tip = Offset(
          top.dx + math.cos(a) * 42 * s, top.dy + math.sin(a) * 26 * s + 10);
      canvas.drawPath(
        Path()
          ..moveTo(top.dx, top.dy)
          ..quadraticBezierTo(
              top.dx + math.cos(a) * 22 * s, top.dy + math.sin(a) * 18 * s - 8,
              tip.dx, tip.dy)
          ..quadraticBezierTo(
              top.dx + math.cos(a) * 24 * s, top.dy + math.sin(a) * 20 * s,
              top.dx, top.dy + 4),
        frond,
      );
    }
    // Coconuts.
    canvas.drawCircle(top.translate(-7, 3), 4.5 * s, Paint()..color = const Color(0xFF7A5230));
    canvas.drawCircle(top.translate(7, 5), 4.5 * s, Paint()..color = const Color(0xFF7A5230));
  }

  static void _beachHut(Canvas canvas, double cx, double groundY, bool isNight) {
    // Stilts.
    final stilts = Paint()..color = const Color(0xFF9C7047);
    canvas.drawRect(Rect.fromLTWH(cx - 26, groundY - 30, 6, 30), stilts);
    canvas.drawRect(Rect.fromLTWH(cx + 20, groundY - 30, 6, 30), stilts);
    // Body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, groundY - 52), width: 84, height: 46),
        const Radius.circular(5),
      ),
      Paint()..color = isNight ? const Color(0xFF5C7C8C) : const Color(0xFF7FC4DE),
    );
    // Big striped roof.
    final roof = Path()
      ..moveTo(cx - 56, groundY - 72)
      ..lineTo(cx, groundY - 104)
      ..lineTo(cx + 56, groundY - 72)
      ..close();
    canvas.drawPath(roof, Paint()..color = const Color(0xFFEF6B4E));
    canvas.save();
    canvas.clipPath(roof);
    for (double x = cx - 56; x < cx + 56; x += 18) {
      canvas.drawRect(
        Rect.fromLTWH(x, groundY - 110, 9, 44),
        Paint()..color = const Color(0xFFFDF6E8),
      );
    }
    canvas.restore();
    // Door, warmly lit at night.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, groundY - 48), width: 22, height: 30),
        const Radius.circular(3),
      ),
      Paint()..color = isNight ? const Color(0xFFFFD97A) : const Color(0xFF3E5866),
    );
    if (isNight) {
      canvas.drawCircle(
        Offset(cx, groundY - 48),
        22,
        Paint()..color = const Color(0xFFFFD97A).withValues(alpha: 0.18),
      );
    }
  }

  static void _umbrella(Canvas canvas, double bx, double groundY, bool isNight) {
    canvas.drawLine(
      Offset(bx, groundY),
      Offset(bx, groundY - 64),
      Paint()
        ..color = const Color(0xFF9C7047)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    final canopy = Path()
      ..moveTo(bx - 42, groundY - 62)
      ..quadraticBezierTo(bx - 20, groundY - 96, bx, groundY - 96)
      ..quadraticBezierTo(bx + 20, groundY - 96, bx + 42, groundY - 62)
      ..quadraticBezierTo(bx, groundY - 74, bx - 42, groundY - 62)
      ..close();
    canvas.drawPath(canopy, Paint()..color = const Color(0xFFEF6B4E));
    canvas.save();
    canvas.clipPath(canopy);
    for (var i = -2; i <= 2; i++) {
      canvas.drawRect(
        Rect.fromLTWH(bx + i * 16 - 4, groundY - 100, 8, 40),
        Paint()..color = const Color(0xFFFDF6E8),
      );
    }
    canvas.restore();
    // Beach towel.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(bx + 10, groundY - 2), width: 52, height: 14),
        const Radius.circular(4),
      ),
      Paint()..color = isNight ? const Color(0xFF5C6C8C) : const Color(0xFF5FC9C0),
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(
        Rect.fromLTWH(bx - 12 + i * 14, groundY - 8, 7, 16),
        Paint()..color = const Color(0xFFFDF6E8),
      );
    }
  }

  static void _sandcastle(Canvas canvas, double cx, double groundY) {
    final sand = const Color(0xFFE8C87E);
    final sandDark = const Color(0xFFD4AC5E);
    // Base keep + towers.
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, groundY - 20), width: 56, height: 40),
      Paint()..color = sand,
    );
    for (final side in [-1.0, 1.0]) {
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset(cx + side * 38, groundY - 26), width: 24, height: 52),
        Paint()..color = sand,
      );
      // Crenellations.
      for (var i = -1; i <= 1; i++) {
        canvas.drawRect(
          Rect.fromLTWH(cx + side * 38 + i * 9 - 3, groundY - 58, 6, 8),
          Paint()..color = sand,
        );
      }
    }
    // Door + windows.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, groundY - 12), width: 14, height: 22),
        const Radius.circular(7),
      ),
      Paint()..color = sandDark,
    );
    // Little flag.
    canvas.drawLine(
      Offset(cx, groundY - 40),
      Offset(cx, groundY - 60),
      Paint()
        ..color = const Color(0xFF9C7047)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx, groundY - 60)
        ..lineTo(cx + 16, groundY - 55)
        ..lineTo(cx, groundY - 50)
        ..close(),
      Paint()..color = const Color(0xFFEF5D6A),
    );
  }

  static void _shells(Canvas canvas, double w, double h, bool isNight) {
    for (var i = 0; i < 14; i++) {
      final x = _hash(i + 800) * w;
      final y = (0.52 + _hash(i + 810) * 0.40) * h;
      final kind = i % 3;
      if (kind == 0) {
        // Shell fan.
        final shell = Paint()..color = isNight ? const Color(0xFFB9A98C) : const Color(0xFFF6D9C4);
        for (var k = -2; k <= 2; k++) {
          canvas.drawCircle(Offset(x + k * 2.4, y - k.abs() * 1.2), 2.0, shell);
        }
      } else if (kind == 1) {
        // Starfish.
        final star = Paint()..color = isNight ? const Color(0xFFC77E5A) : const Color(0xFFEF9A5C);
        for (var k = 0; k < 5; k++) {
          final a = k * 2 * math.pi / 5 - math.pi / 2;
          canvas.drawCircle(
              Offset(x + math.cos(a) * 3.4, y + math.sin(a) * 3.4), 2.2, star);
        }
        canvas.drawCircle(Offset(x, y), 1.8, star);
      } else {
        // Pebble.
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: 8, height: 5),
          Paint()..color = isNight ? const Color(0xFF8A7C64) : const Color(0xFFD9C49A),
        );
      }
    }
  }

  // -- pirate ship ------------------------------------------------------------------

  static void _ship(Canvas canvas, Size size, SkyPhase phase, bool night,
      int level, double t) {
    final w = size.width, h = size.height;
    final horizon = h * 0.33;
    final isNight = _isNight(phase, night);

    _sky(canvas, w, h, horizon, phase, night, t,
        dayColors: const [Color(0xFF6FB8E8), Color(0xFFA9D4EE), Color(0xFFEFF6E1)],
        seagulls: true);

    // Open sea to the horizon.
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, w, h - horizon),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isNight
              ? const [Color(0xFF16304E), Color(0xFF1E3E5E), Color(0xFF16304E)]
              : const [Color(0xFF3E9EC8), Color(0xFF5FB8D8), Color(0xFF3E86AC)],
        ).createShader(Rect.fromLTWH(0, horizon, w, h - horizon)),
    );
    // Wave strokes across the sea.
    for (var i = 0; i < 10; i++) {
      final wy = horizon + 8 + i * (h - horizon - 16) / 10;
      final wx = _hash(i + 20) * w;
      final wl = 30 + _hash(i + 21) * 50;
      final wob = math.sin(t * 1.2 + i) * 4;
      canvas.drawPath(
        Path()
          ..moveTo(wx, wy + wob)
          ..quadraticBezierTo(wx + wl / 2, wy - 5 + wob, wx + wl, wy + wob),
        Paint()
          ..color = Colors.white.withValues(alpha: isNight ? 0.08 : 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // Distant island on the horizon.
    final isl = Path()
      ..moveTo(w * 0.80, horizon + 2)
      ..quadraticBezierTo(w * 0.86, horizon - 26, w * 0.92, horizon + 2)
      ..close();
    canvas.drawPath(isl, Paint()..color = isNight ? const Color(0xFF2A4058) : const Color(0xFF6FAE86));
    canvas.drawCircle(
        Offset(w * 0.855, horizon - 22), 6, Paint()..color = const Color(0xFF4E9E5F));

    // Mast + rigging behind the deck.
    final mastX = w * 0.18;
    canvas.drawLine(
      Offset(mastX, horizon + 40),
      Offset(mastX, horizon - 170),
      Paint()
        ..color = isNight ? const Color(0xFF5C432E) : const Color(0xFF8A5F3C)
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );
    // Yardarm + billowing sail.
    canvas.drawLine(
      Offset(mastX - 62, horizon - 128),
      Offset(mastX + 62, horizon - 128),
      Paint()
        ..color = const Color(0xFF5C432E)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    final swell = math.sin(t * 0.8) * 5;
    final sail = Path()
      ..moveTo(mastX - 58, horizon - 124)
      ..quadraticBezierTo(mastX - 20 + swell, horizon - 60, mastX + 12, horizon - 30)
      ..quadraticBezierTo(mastX + 40, horizon - 70, mastX + 58, horizon - 124)
      ..close();
    canvas.drawPath(sail, Paint()..color = isNight ? const Color(0xFFD8D2C4) : const Color(0xFFFDF6E8));
    // Skull emblem on the sail.
    canvas.drawCircle(
        Offset(mastX, horizon - 96), 9, Paint()..color = const Color(0xFF43302E));
    canvas.drawCircle(Offset(mastX - 3, horizon - 98), 1.8, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(mastX + 3, horizon - 98), 1.8, Paint()..color = Colors.white);
    // Pennant flag at the top.
    canvas.drawPath(
      Path()
        ..moveTo(mastX, horizon - 168)
        ..lineTo(mastX + 30 + math.sin(t * 4) * 4, horizon - 160)
        ..lineTo(mastX, horizon - 152)
        ..close(),
      Paint()..color = const Color(0xFFEF5D6A),
    );
    // Rigging lines.
    canvas.drawLine(
      Offset(mastX, horizon - 150),
      Offset(w * 0.02, horizon + 8),
      Paint()..color = const Color(0xFF5C432E)..strokeWidth = 2,
    );
    canvas.drawLine(
      Offset(mastX, horizon - 150),
      Offset(w * 0.55, horizon + 8),
      Paint()..color = const Color(0xFF5C432E)..strokeWidth = 2,
    );

    // Stern rail along the horizon (the far edge of our deck).
    final railY = horizon + 18;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, railY, w, 12), const Radius.circular(6)),
      Paint()..color = isNight ? const Color(0xFF6E4E32) : const Color(0xFF9C6B42),
    );
    for (double x = 8; x < w; x += 74) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, railY - 14, 8, 20), const Radius.circular(4)),
        Paint()..color = isNight ? const Color(0xFF5C432E) : const Color(0xFF8A5F3C),
      );
    }

    // The deck: warm planks below the rail.
    canvas.drawRect(
      Rect.fromLTWH(0, railY + 12, w, h - railY - 12),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isNight
              ? const [Color(0xFF7A5636), Color(0xFF5E4228)]
              : const [Color(0xFFC08A56), Color(0xFF9C6B42)],
        ).createShader(Rect.fromLTWH(0, railY, w, h - railY)),
    );
    // Plank seams.
    for (var i = 0; i < 9; i++) {
      final px = (i + _hash(i + 60) * 0.5) * w / 8;
      canvas.drawLine(
        Offset(px, railY + 12),
        Offset(px + 14, h),
        Paint()
          ..color = const Color(0xFF5E4228).withValues(alpha: 0.45)
          ..strokeWidth = 2,
      );
    }
    for (var i = 1; i < 4; i++) {
      final py = railY + 12 + (h - railY - 12) * i / 4;
      canvas.drawLine(
        Offset(0, py),
        Offset(w, py),
        Paint()
          ..color = const Color(0xFF5E4228).withValues(alpha: 0.30)
          ..strokeWidth = 2,
      );
    }

    // Ship's cabin = the hub (barn tap zone).
    _cabin(canvas, _hubX(w) + w * 0.12, railY + 16, isNight);

    // Props: barrel + rope coil.
    _barrel(canvas, w * 0.78, h * 0.70, isNight);
    canvas.drawCircle(
      Offset(w * 0.60, h * 0.86),
      18,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const Color(0xFFC9A96B),
    );
    canvas.drawCircle(
      Offset(w * 0.60, h * 0.86),
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0xFFB58836),
    );

    // Night: warm lanterns along the rail.
    if (isNight) {
      for (double x = 40; x < w; x += 150) {
        canvas.drawCircle(
            Offset(x, railY - 20), 26, Paint()..color = const Color(0xFFFFD97A).withValues(alpha: 0.14));
        canvas.drawCircle(Offset(x, railY - 20), 5, Paint()..color = const Color(0xFFFFD97A));
      }
    }
  }

  static void _cabin(Canvas canvas, double cx, double groundY, bool isNight) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, groundY - 40), width: 92, height: 56),
        const Radius.circular(6),
      ),
      Paint()..color = isNight ? const Color(0xFF5C432E) : const Color(0xFF8A5F3C),
    );
    final roof = Path()
      ..moveTo(cx - 54, groundY - 62)
      ..lineTo(cx, groundY - 92)
      ..lineTo(cx + 54, groundY - 62)
      ..close();
    canvas.drawPath(roof, Paint()..color = const Color(0xFF6E4E32));
    // Porthole windows.
    for (final side in [-1.0, 1.0]) {
      canvas.drawCircle(
        Offset(cx + side * 22, groundY - 46),
        8,
        Paint()..color = isNight ? const Color(0xFFFFD97A) : const Color(0xFFBFE9FF),
      );
      canvas.drawCircle(
        Offset(cx + side * 22, groundY - 46),
        8,
        Paint()
          ..color = const Color(0xFF43302E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }
    // Ship's wheel by the door.
    final wheelC = Offset(cx, groundY - 22);
    canvas.drawCircle(
      wheelC,
      10,
      Paint()
        ..color = const Color(0xFFC9A96B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 4;
      canvas.drawLine(
        wheelC.translate(math.cos(a) * 10, math.sin(a) * 10),
        wheelC.translate(math.cos(a) * 15, math.sin(a) * 15),
        Paint()
          ..color = const Color(0xFFC9A96B)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  static void _barrel(Canvas canvas, double cx, double groundY, bool isNight) {
    final body = Path()
      ..moveTo(cx - 20, groundY - 44)
      ..quadraticBezierTo(cx - 26, groundY - 22, cx - 20, groundY)
      ..lineTo(cx + 20, groundY)
      ..quadraticBezierTo(cx + 26, groundY - 22, cx + 20, groundY - 44)
      ..close();
    canvas.drawPath(
        body, Paint()..color = isNight ? const Color(0xFF6E4E32) : const Color(0xFF9C6B42));
    canvas.drawLine(
        Offset(cx - 23, groundY - 34),
        Offset(cx + 23, groundY - 34),
        Paint()..color = const Color(0xFFC9A96B)..strokeWidth = 3.4);
    canvas.drawLine(
        Offset(cx - 24, groundY - 12),
        Offset(cx + 24, groundY - 12),
        Paint()..color = const Color(0xFFC9A96B)..strokeWidth = 3.4);
    // Top lid ellipse.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, groundY - 44), width: 40, height: 10),
      Paint()..color = const Color(0xFFB58836),
    );
  }

  // -- sky island ---------------------------------------------------------------------

  static void _skyIsland(Canvas canvas, Size size, SkyPhase phase, bool night,
      int level, double t) {
    final w = size.width, h = size.height;
    final horizon = h * 0.30;
    final isNight = _isNight(phase, night);

    _sky(canvas, w, h, horizon, phase, night, t,
        dayColors: const [Color(0xFF8FBCE8), Color(0xFFC6D9EE), Color(0xFFF2E6F5)],
        seagulls: true);

    // Distant floating islets.
    _islet(canvas, w * 0.14, h * 0.22, 0.7, isNight, t);
    _islet(canvas, w * 0.86, h * 0.16, 0.5, isNight, t);
    _islet(canvas, w * 0.66, h * 0.12, 0.35, isNight, t);

    // Drifting cloud puffs below and around the island.
    for (var i = 0; i < 7; i++) {
      final cx = ((_hash(i + 300) + t * 0.004) % 1.2 - 0.1) * w;
      final cy = h * (0.42 + 0.09 * (i % 5)) + math.sin(t * 0.6 + i * 2) * 5;
      final cloud = Paint()..color = Colors.white.withValues(alpha: 0.9);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: 74, height: 20), cloud);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx - 22, cy + 5), width: 42, height: 14), cloud);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx + 24, cy + 4), width: 46, height: 16), cloud);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + 10), width: 64, height: 8),
        Paint()..color = const Color(0xFFD5E2F2).withValues(alpha: 0.7),
      );
    }

    // The island: grass top from the horizon down to the cliff edge…
    final edgeY = h * 0.72;
    canvas.drawPath(
      Path()
        ..moveTo(0, horizon + 4)
        ..quadraticBezierTo(w * 0.25, horizon - 14, w * 0.5, horizon + 2)
        ..quadraticBezierTo(w * 0.75, horizon + 16, w, horizon - 6)
        ..lineTo(w, edgeY - 40)
        ..quadraticBezierTo(w * 0.85, edgeY + 6, w * 0.7, edgeY - 26)
        ..quadraticBezierTo(w * 0.55, edgeY + 16, w * 0.4, edgeY - 20)
        ..quadraticBezierTo(w * 0.25, edgeY + 10, w * 0.12, edgeY - 30)
        ..quadraticBezierTo(w * 0.05, edgeY - 6, 0, edgeY - 44)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isNight
              ? const [Color(0xFF37543E), Color(0xFF2A4232)]
              : const [Color(0xFF9CCB77), Color(0xFF6FAE55)],
        ).createShader(Rect.fromLTWH(0, horizon - 20, w, edgeY - horizon + 40)),
    );
    // …then the rocky underside hanging in the sky.
    canvas.drawPath(
      Path()
        ..moveTo(0, edgeY - 44)
        ..quadraticBezierTo(w * 0.05, edgeY - 6, w * 0.12, edgeY - 30)
        ..quadraticBezierTo(w * 0.25, edgeY + 10, w * 0.4, edgeY - 20)
        ..quadraticBezierTo(w * 0.55, edgeY + 16, w * 0.7, edgeY - 26)
        ..quadraticBezierTo(w * 0.85, edgeY + 6, w, edgeY - 40)
        ..lineTo(w, edgeY + 26)
        ..quadraticBezierTo(w * 0.78, edgeY + 90, w * 0.55, edgeY + 60)
        ..quadraticBezierTo(w * 0.35, edgeY + 110, w * 0.15, edgeY + 54)
        ..quadraticBezierTo(w * 0.04, edgeY + 40, 0, edgeY + 30)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isNight
              ? const [Color(0xFF4E3E55), Color(0xFF3A2E44)]
              : const [Color(0xFFB08A5E), Color(0xFF8A6644)],
        ).createShader(Rect.fromLTWH(0, edgeY - 30, w, 150)),
    );
    // Rocky facet lines.
    for (var i = 0; i < 5; i++) {
      final fx = w * (0.12 + i * 0.17);
      canvas.drawLine(
        Offset(fx, edgeY + (i.isEven ? -10 : 4)),
        Offset(fx + 16, edgeY + 40 + i * 8),
        Paint()
          ..color = const Color(0xFF6E5238).withValues(alpha: 0.35)
          ..strokeWidth = 2,
      );
    }
    // Hanging vines from the cliff.
    for (var i = 0; i < 4; i++) {
      final vx = w * (0.2 + i * 0.2);
      final sway = math.sin(t * 1.1 + i * 1.9) * 4;
      canvas.drawPath(
        Path()
          ..moveTo(vx, edgeY + 8)
          ..quadraticBezierTo(vx + sway, edgeY + 30, vx, edgeY + 48),
        Paint()
          ..color = isNight ? const Color(0xFF3E6B4A) : const Color(0xFF5FA85C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(Offset(vx, edgeY + 50), 3.2,
          Paint()..color = const Color(0xFF4E9E5F));
    }

    // Waterfall off the right edge of the island.
    final fallTop = Offset(w * 0.82, edgeY - 18);
    final flow = (t * 0.35) % 1.0;
    for (var i = 0; i < 4; i++) {
      final fy = fallTop.dy + ((i + flow) % 4) * 34;
      final fade = 1 - (((i + flow) % 4) / 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(fallTop.dx - 8, fy, 16, 22),
          const Radius.circular(8),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.30 + 0.25 * fade),
      );
    }

    // The hub: a big treehouse where the barn stands.
    _treehouse(canvas, _hubX(w), horizon + 8, isNight);

    // Props: balloons tethered at lv10, flowers elsewhere.
    if (level >= 10) {
      for (var i = 0; i < 3; i++) {
        final bx = w * (0.6 + i * 0.13);
        final by = horizon - 40 - math.sin(t * 0.9 + i * 2.1) * 8 - i * 14;
        final colors = [
          const Color(0xFFEF5D6A),
          const Color(0xFFF7C948),
          const Color(0xFF5FC9C0),
        ];
        canvas.drawOval(
          Rect.fromCenter(center: Offset(bx, by), width: 26, height: 32),
          Paint()..color = colors[i % 3],
        );
        canvas.drawPath(
          Path()
            ..moveTo(bx - 4, by + 16)
            ..lineTo(bx, by + 24)
            ..lineTo(bx + 4, by + 16)
            ..close(),
          Paint()..color = colors[i % 3],
        );
        canvas.drawLine(
          Offset(bx, by + 24),
          Offset(bx - 4, horizon + 40),
          Paint()
            ..color = const Color(0xFF8E9AAB)
            ..strokeWidth = 1.4,
        );
      }
    }
    // Flora pass confined to the island top.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, horizon + 4, w, edgeY - horizon - 10));
    _flora(canvas, w, h, isNight);
    canvas.restore();
  }

  static void _islet(Canvas canvas, double cx, double cy, double s,
      bool isNight, double t) {
    final bob = math.sin(t * 0.7 + cx) * 3 * s;
    canvas.save();
    canvas.translate(cx, cy + bob);
    canvas.scale(s);
    // Grass cap.
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 90, height: 22),
      Paint()..color = isNight ? const Color(0xFF37543E) : const Color(0xFF8FBE6C),
    );
    // Rock cone.
    canvas.drawPath(
      Path()
        ..moveTo(-45, 2)
        ..quadraticBezierTo(-20, 30, -6, 64)
        ..quadraticBezierTo(6, 34, 45, 2)
        ..close(),
      Paint()..color = isNight ? const Color(0xFF4E3E55) : const Color(0xFFA98A5E),
    );
    // One little tree.
    canvas.drawLine(
      const Offset(0, -2),
      const Offset(0, -20),
      Paint()
        ..color = const Color(0xFF8A5F3C)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
        const Offset(0, -30), 14, Paint()..color = isNight ? const Color(0xFF46614F) : const Color(0xFF7FB86B));
    canvas.restore();
  }

  static void _treehouse(Canvas canvas, double cx, double groundY, bool isNight) {
    // Trunk.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, groundY - 60), width: 40, height: 120),
        const Radius.circular(12),
      ),
      Paint()..color = isNight ? const Color(0xFF5C4A38) : const Color(0xFF9C7047),
    );
    // Big canopy.
    final leaf = isNight ? const Color(0xFF46614F) : const Color(0xFF7FB86B);
    final leafDark = isNight ? const Color(0xFF3A5244) : const Color(0xFF6BA75B);
    canvas.drawCircle(Offset(cx - 34, groundY - 108), 30, Paint()..color = leafDark);
    canvas.drawCircle(Offset(cx + 34, groundY - 112), 32, Paint()..color = leaf);
    canvas.drawCircle(Offset(cx, groundY - 134), 38, Paint()..color = leaf);
    canvas.drawCircle(Offset(cx, groundY - 142), 20,
        Paint()..color = isNight ? leaf : const Color(0xFF9CCB77));
    // Door at the base, warmly lit at night.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, groundY - 26), width: 20, height: 34),
        const Radius.circular(10),
      ),
      Paint()..color = isNight ? const Color(0xFFFFD97A) : const Color(0xFF6E5238),
    );
    // Round window in the canopy.
    canvas.drawCircle(
      Offset(cx, groundY - 108),
      8,
      Paint()..color = isNight ? const Color(0xFFFFD97A) : const Color(0xFFBFE9FF),
    );
    if (isNight) {
      canvas.drawCircle(
        Offset(cx, groundY - 108),
        18,
        Paint()..color = const Color(0xFFFFD97A).withValues(alpha: 0.16),
      );
    }
  }
}
