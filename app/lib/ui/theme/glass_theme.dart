import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A single drifting light source behind the glass.
class BlobSpec {
  final Alignment base;
  final Alignment drift; // how far it wanders over one cycle
  final double size; // fraction of the shorter screen side
  final Color color;
  final double opacity;
  final double phase; // radians offset so blobs don't move in lockstep

  const BlobSpec({
    required this.base,
    required this.drift,
    required this.size,
    required this.color,
    required this.opacity,
    this.phase = 0,
  });
}

/// All color decisions for the liquid-glass design system.
class GlassPalette {
  final Color bgTop;
  final Color bgBottom;
  final List<BlobSpec> blobs;

  /// Translucent fill for chrome (bars, pills).
  final Color glassFill;

  /// Extra-transparent fill for floating bars — the background shows
  /// through deliberately.
  final Color chromeFill;

  /// More opaque fill for reading surfaces (cards, sheets).
  final Color solidFill;

  /// Semi-translucent fill for reading surfaces — the aurora glows through,
  /// so text floats on the same atmosphere as the orb.
  final Color readingFill;

  /// Specular edge of a glass pane: lit corner -> faint corner.
  final Color borderStrong;
  final Color borderFaint;

  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color hairline;
  final Color shadow;

  /// Opaque surface for dialogs / the drawer body.
  final Color surface;

  final Color success;
  final Color danger;
  final Color warn;

  final bool isDark;

  const GlassPalette({
    required this.bgTop,
    required this.bgBottom,
    required this.blobs,
    required this.glassFill,
    required this.chromeFill,
    required this.solidFill,
    required this.readingFill,
    required this.borderStrong,
    required this.borderFaint,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.hairline,
    required this.shadow,
    required this.surface,
    required this.success,
    required this.danger,
    required this.warn,
    required this.isDark,
  });

  static const GlassPalette light = GlassPalette(
    isDark: false,
    bgTop: Color(0xFFEDF1FB),
    bgBottom: Color(0xFFF7F1FA),
    blobs: [
      BlobSpec(
        base: Alignment(-0.65, -0.55),
        drift: Alignment(0.25, -0.15),
        size: 1.05,
        color: Color(0xFF9DB8FF),
        opacity: 0.55,
      ),
      BlobSpec(
        base: Alignment(0.75, 0.15),
        drift: Alignment(0.15, -0.45),
        size: 0.85,
        color: Color(0xFFE3B4F2),
        opacity: 0.50,
        phase: 2.1,
      ),
      BlobSpec(
        base: Alignment(-0.25, 0.9),
        drift: Alignment(0.4, 0.2),
        size: 0.95,
        color: Color(0xFF96E6D3),
        opacity: 0.45,
        phase: 4.2,
      ),
    ],
    glassFill: Color(0x94FFFFFF),
    chromeFill: Color(0x73FFFFFF),
    solidFill: Color(0xE6FFFFFF),
    readingFill: Color(0xCCFFFFFF),
    borderStrong: Color(0xF2FFFFFF),
    borderFaint: Color(0x52FFFFFF),
    textPrimary: Color(0xFF17203D),
    textSecondary: Color(0xFF5A6584),
    accent: Color(0xFF3D6BFF),
    hairline: Color(0x1417203D),
    shadow: Color(0x2417203D),
    surface: Color(0xFFF4F6FD),
    success: Color(0xFF2FA36B),
    danger: Color(0xFFE5484D),
    warn: Color(0xFFDD8A1E),
  );

  static const GlassPalette dark = GlassPalette(
    isDark: true,
    bgTop: Color(0xFF070B17),
    bgBottom: Color(0xFF0E1330),
    blobs: [
      BlobSpec(
        base: Alignment(-0.6, -0.5),
        drift: Alignment(0.3, -0.1),
        size: 1.1,
        color: Color(0xFF2A4DD0),
        opacity: 0.42,
      ),
      BlobSpec(
        base: Alignment(0.8, 0.2),
        drift: Alignment(0.2, -0.35),
        size: 0.9,
        color: Color(0xFF0FA3B1),
        opacity: 0.30,
        phase: 2.1,
      ),
      BlobSpec(
        base: Alignment(-0.2, 0.95),
        drift: Alignment(0.35, 0.25),
        size: 1.0,
        color: Color(0xFFB84A9C),
        opacity: 0.28,
        phase: 4.2,
      ),
    ],
    glassFill: Color(0x14FFFFFF),
    chromeFill: Color(0x5C101731),
    solidFill: Color(0xB3101731),
    readingFill: Color(0xD10F1428),
    borderStrong: Color(0x61FFFFFF),
    borderFaint: Color(0x1AFFFFFF),
    textPrimary: Color(0xFFF3F5FF),
    textSecondary: Color(0xFFA7B0CC),
    accent: Color(0xFF7DA4FF),
    hairline: Color(0x1AFFFFFF),
    shadow: Color(0x80000000),
    surface: Color(0xFF141B33),
    success: Color(0xFF4ADE9C),
    danger: Color(0xFFFF7B81),
    warn: Color(0xFFFFC46B),
  );
}

/// Typography: Inter stands in for SF Pro. Large sizes get tighter
/// tracking, the way iOS display type does.
class GlassText {
  static TextStyle display(
    GlassPalette p,
    double size, {
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? tracking,
    double height = 1.18,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: tracking ?? -size * 0.028,
      color: color ?? p.textPrimary,
    );
  }

  static TextStyle body(
    GlassPalette p,
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.4,
    double? tracking,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: tracking,
      color: color ?? p.textPrimary,
    );
  }

  static TextStyle eyebrow(GlassPalette p, {Color? color}) {
    return GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.6,
      color: color ?? p.textSecondary,
    );
  }

  /// Reading face: Literata, a bookish serif for dictionary content.
  /// Deliberately distinct from the Inter UI chrome.
  static TextStyle reading(
    GlassPalette p,
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.6,
    FontStyle fontStyle = FontStyle.normal,
    double? tracking,
  }) {
    return GoogleFonts.literata(
      fontSize: size,
      height: height,
      fontWeight: weight,
      fontStyle: fontStyle,
      letterSpacing: tracking,
      color: color ?? p.textPrimary,
    );
  }
}

/// Provides the active palette + reader font size to the whole subtree.
class GlassScope extends InheritedWidget {
  final GlassPalette palette;
  final double fontSize;

  const GlassScope({
    super.key,
    required this.palette,
    required this.fontSize,
    required super.child,
  });

  static GlassScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GlassScope>();
    assert(scope != null, 'GlassScope not found in ancestry');
    return scope!;
  }

  @override
  bool updateShouldNotify(GlassScope oldWidget) =>
      oldWidget.palette != palette || oldWidget.fontSize != fontSize;
}
