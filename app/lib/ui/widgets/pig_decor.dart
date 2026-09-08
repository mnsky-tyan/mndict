import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The yard's decorateables. One file because both the farm scene and the
/// market's Decor tab paint them: a catalog of little canvas props and
/// the one painter that draws them all. Origin is the prop's base on the
/// ground; size is logical px at scale 1.
class FarmDecor {
  final String id;
  final String name;
  final int price;
  final DecorKind kind;

  const FarmDecor(this.id, this.name, this.price, this.kind);
}

enum DecorKind { ball, mushroom, flowers, pumpkin, hayBale, lantern, scarecrow, cart }

/// Buy order = display order: cheap trinkets first, centrepiece last.
const List<FarmDecor> decorCatalog = [
  FarmDecor('ball', 'Bouncy Ball', 8, DecorKind.ball),
  FarmDecor('mushroom', 'Toadstool', 10, DecorKind.mushroom),
  FarmDecor('flowers', 'Flower Patch', 15, DecorKind.flowers),
  FarmDecor('hay', 'Hay Bale', 18, DecorKind.hayBale),
  FarmDecor('pumpkin', 'Pumpkin', 22, DecorKind.pumpkin),
  FarmDecor('lantern', 'Garden Lantern', 30, DecorKind.lantern),
  FarmDecor('scarecrow', 'Scarecrow', 40, DecorKind.scarecrow),
  FarmDecor('cart', 'Wheelbarrow', 55, DecorKind.cart),
];

FarmDecor? decorById(String id) {
  for (final d in decorCatalog) {
    if (d.id == id) return d;
  }
  return null;
}

/// Paints one yard prop into a local space where (0, 0) is the base on
/// the ground and props are roughly 40–90 px tall at scale 1.
class DecorArt {
  static Color _darken(Color c, double amt) => Color.lerp(c, Colors.black, amt)!;

  static void paint(
    Canvas canvas,
    FarmDecor decor, {
    required double t, // seconds, for idle motion
    required bool night,
  }) {
    final shadow = Rect.fromCenter(
        center: const Offset(0, 2), width: 54, height: 12);
    canvas.drawOval(
      shadow,
      Paint()..color = Colors.black.withValues(alpha: 0.14),
    );
    switch (decor.kind) {
      case DecorKind.ball:
        // Red-and-white beach ball with a bounce that never quite dies.
        final hop = math.sin(t * 2.2).abs() * 4;
        final center = Offset(0, -18 - hop);
        canvas.drawCircle(center, 16, Paint()..color = const Color(0xFFE5484D));
        canvas.save();
        canvas.translate(center.dx, center.dy);
        for (var i = 0; i < 3; i++) {
          canvas.rotate(math.pi / 3);
          canvas.drawArc(
            Rect.fromCircle(center: Offset.zero, radius: 16),
            -0.5,
            1.05,
            false,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 7,
          );
        }
        canvas.restore();
        canvas.drawCircle(center.translate(-5, -6), 3.5,
            Paint()..color = Colors.white.withValues(alpha: 0.7));
      case DecorKind.mushroom:
        final stem = RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(0, -12), width: 12, height: 24),
          const Radius.circular(5),
        );
        canvas.drawRRect(stem, Paint()..color = const Color(0xFFF3EAD8));
        final cap = Path()
          ..moveTo(-24, -20)
          ..quadraticBezierTo(0, -52, 24, -20)
          ..quadraticBezierTo(0, -12, -24, -20)
          ..close();
        canvas.drawPath(cap, Paint()..color = const Color(0xFFD8574C));
        for (final (dx, dy, r) in [(-9, -32, 3.4), (7, -36, 2.8), (1, -26, 2.2)]) {
          canvas.drawCircle(Offset(dx.toDouble(), dy.toDouble()),
              r.toDouble(), Paint()..color = Colors.white.withValues(alpha: 0.9));
        }
      case DecorKind.flowers:
        // A tuft of five blooms swaying on their stems.
        const blooms = [(-16.0, 0.9), (-6.0, 1.1), (4.0, 0.8), (14.0, 1.0), (0.0, 1.2)];
        const petalColors = [
          Color(0xFFFF9EC3),
          Color(0xFFF7C948),
          Color(0xFFB08DE0),
        ];
        for (var i = 0; i < blooms.length; i++) {
          final (bx, s) = blooms[i];
          final sway = math.sin(t * 1.6 + i * 1.3) * 2.2;
          final base = Offset(bx, -2);
          final head = Offset(bx + sway, -26 * s);
          canvas.drawLine(
            base,
            head,
            Paint()
              ..color = const Color(0xFF5FA85C)
              ..strokeWidth = 2.6
              ..strokeCap = StrokeCap.round,
          );
          final petal = Paint()..color = petalColors[i % petalColors.length];
          for (var p = 0; p < 5; p++) {
            final a = p * 2 * math.pi / 5 - math.pi / 2;
            canvas.drawCircle(
              head.translate(math.cos(a) * 4.6 * s, math.sin(a) * 4.6 * s),
              3.1 * s,
              petal,
            );
          }
          canvas.drawCircle(head, 2.7 * s, Paint()..color = const Color(0xFFF7C948));
        }
      case DecorKind.hayBale:
        final body = RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(0, -17), width: 46, height: 34),
          const Radius.circular(9),
        );
        canvas.drawRRect(body, Paint()..color = const Color(0xFFE0B95C));
        final strand = Paint()
          ..color = _darken(const Color(0xFFE0B95C), 0.18)
          ..strokeWidth = 2;
        for (var i = 0; i < 3; i++) {
          canvas.drawLine(Offset(-18, -10 - 8.0 * i), Offset(18, -10 - 8.0 * i),
              strand);
        }
        // Twin ties.
        canvas.drawLine(const Offset(-6, -32), const Offset(-6, -2),
            Paint()..color = const Color(0xFFB58836)..strokeWidth = 3);
        canvas.drawLine(const Offset(8, -32), const Offset(8, -2),
            Paint()..color = const Color(0xFFB58836)..strokeWidth = 3);
      case DecorKind.pumpkin:
        final body = Rect.fromCenter(
            center: const Offset(0, -15), width: 40, height: 30);
        canvas.drawOval(
          body,
          Paint()..color = const Color(0xFFE8823C),
        );
        for (final dx in [-12.0, 0.0, 12.0]) {
          canvas.drawOval(
            Rect.fromCenter(
                center: Offset(dx, -15), width: 11, height: 30),
            Paint()
              ..color = _darken(const Color(0xFFE8823C), 0.10)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
        canvas.drawLine(
          const Offset(0, -30),
          const Offset(4, -38),
          Paint()
            ..color = const Color(0xFF5FA85C)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(const Offset(-6, -24), 3,
            Paint()..color = Colors.white.withValues(alpha: 0.35));
      case DecorKind.lantern:
        // Post, glass house, warm glow that wakes at night.
        canvas.drawLine(
          const Offset(0, 0),
          const Offset(0, -44),
          Paint()
            ..color = const Color(0xFF4A4038)
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
        if (night) {
          final glow = Rect.fromCenter(
              center: const Offset(0, -52), width: 120, height: 120);
          canvas.drawCircle(
            glow.center,
            60,
            Paint()
              ..shader = RadialGradient(colors: [
                const Color(0xFFFFD86B).withValues(alpha: 0.30),
                const Color(0xFFFFD86B).withValues(alpha: 0.0),
              ]).createShader(glow),
          );
        }
        final house = RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(0, -52), width: 20, height: 18),
          const Radius.circular(4),
        );
        canvas.drawRRect(
            house,
            Paint()
              ..color = night
                  ? const Color(0xFFFFD86B)
                  : const Color(0xFFDCE8F0));
        canvas.drawRRect(
          house,
          Paint()
            ..color = const Color(0xFF4A4038)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        final roof = Path()
          ..moveTo(-14, -60)
          ..lineTo(0, -70)
          ..lineTo(14, -60)
          ..close();
        canvas.drawPath(roof, Paint()..color = const Color(0xFF4A4038));
      case DecorKind.scarecrow:
        canvas.drawLine(
          const Offset(0, -2),
          const Offset(0, -58),
          Paint()
            ..color = const Color(0xFF9C7047)
            ..strokeWidth = 6,
        );
        canvas.drawLine(
          const Offset(-22, -44),
          const Offset(22, -44),
          Paint()
            ..color = const Color(0xFF9C7047)
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
        // Coat, patch and straw cuffs.
        final coat = Path()
          ..moveTo(-13, -52)
          ..lineTo(13, -52)
          ..lineTo(10, -26)
          ..lineTo(-10, -26)
          ..close();
        canvas.drawPath(coat, Paint()..color = const Color(0xFF5C86C9));
        canvas.drawCircle(const Offset(5, -36), 2.6,
            Paint()..color = const Color(0xFFF7C948));
        final head = Rect.fromCenter(
            center: const Offset(0, -60), width: 22, height: 20);
        canvas.drawOval(head, Paint()..color = const Color(0xFFF3E3C0));
        canvas.drawCircle(const Offset(-4, -62), 1.8, Paint()..color = const Color(0xFF2E2438));
        canvas.drawCircle(const Offset(4, -62), 1.8, Paint()..color = const Color(0xFF2E2438));
        final hat = Path()
          ..moveTo(-14, -68)
          ..lineTo(14, -68)
          ..lineTo(6, -78)
          ..lineTo(-6, -78)
          ..close();
        canvas.drawPath(hat, Paint()..color = const Color(0xFFB58836));
        // Straw hair.
        for (final dx in [-12.0, -8.0, 8.0, 12.0]) {
          canvas.drawLine(Offset(dx, -66), Offset(dx * 1.3, -56),
              Paint()..color = const Color(0xFFE0B95C)..strokeWidth = 2);
        }
      case DecorKind.cart:
        // A wheelbarrow with a bit of bounce in the wheel.
        final tub = Path()
          ..moveTo(-26, -34)
          ..lineTo(22, -34)
          ..lineTo(14, -18)
          ..lineTo(-18, -18)
          ..close();
        canvas.drawPath(tub, Paint()..color = const Color(0xFF7FA85C));
        canvas.drawPath(
          tub,
          Paint()
            ..color = _darken(const Color(0xFF7FA85C), 0.2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        canvas.drawCircle(
            const Offset(10, -8),
            8,
            Paint()..color = const Color(0xFF4A4038));
        canvas.drawCircle(
            const Offset(10, -8),
            3,
            Paint()..color = const Color(0xFFD9D2C4));
        canvas.drawLine(
          const Offset(-18, -18),
          const Offset(-24, -2),
          Paint()
            ..color = const Color(0xFF9C7047)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawLine(
          const Offset(-24, -2),
          const Offset(-6, -2),
          Paint()
            ..color = const Color(0xFF9C7047)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
        // Hay poking out of the tub.
        for (final dx in [-12.0, -2.0, 8.0]) {
          canvas.drawLine(
            Offset(dx, -34),
            Offset(dx + 4 * math.sin(t * 3 + dx), -42),
            Paint()
              ..color = const Color(0xFFE0B95C)
              ..strokeWidth = 2.4
              ..strokeCap = StrokeCap.round,
          );
        }
    }
  }
}
