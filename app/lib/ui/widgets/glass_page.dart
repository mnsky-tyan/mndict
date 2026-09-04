import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/glass_theme.dart';
import 'aurora_background.dart';
import 'glass_container.dart';
import 'pressable.dart';

/// A circular glass icon button (menu, back, close, actions).
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? iconColor;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 42,
    this.iconSize = 15,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.90,
      child: GlassContainer(
        width: size,
        height: size,
        borderRadius: size / 2,
        chrome: true,
        padding: EdgeInsets.zero,
        child: Center(
          child: FaIcon(
            icon,
            size: iconSize,
            color: iconColor ?? p.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Filled accent capsule for the main action of a screen.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height;
  final Widget? leading;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 52,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.96,
      child: Material(
        color: p.accent,
        borderRadius: BorderRadius.circular(height / 2),
        elevation: 0,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 9)],
              Text(
                label,
                style: GlassText.body(
                  p,
                  14.5,
                  weight: FontWeight.w600,
                  color: p.isDark ? const Color(0xFF0B1020) : Colors.white,
                  tracking: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quiet glass capsule for secondary actions.
class GlassButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height;
  final Widget? leading;

  const GlassButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 52,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.96,
      child: GlassContainer(
        borderRadius: height / 2,
        blur: 0,
        padding: EdgeInsets.zero,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Text(
                label,
                style: GlassText.body(p, 15, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Self-contained page for routes pushed above the main scope: brings its
/// own aurora + palette so pushed screens match the app.
class GlassPage extends StatelessWidget {
  final String title;
  final Widget child;
  final GlassPalette? palette;

  const GlassPage({super.key, required this.title, required this.child, this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette ?? GlassPalette.light;
    return GlassScope(
      palette: p,
      fontSize: 16,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: p.isDark ? Brightness.dark : Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: AuroraBackground(
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Row(
                      children: [
                        GlassIconButton(
                          icon: FontAwesomeIcons.chevronLeft,
                          onTap: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            title,
                            style: GlassText.display(p, 20, weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
