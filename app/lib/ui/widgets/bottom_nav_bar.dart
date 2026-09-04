import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/glass_theme.dart';
import 'glass_container.dart';

/// Floating glass navigation. The lens position is driven directly by
/// [position] (a fractional page index, 0..n-1), so it scrubs under the
/// finger during a page drag instead of only animating after a tap.
class GlassBottomNavBar extends StatelessWidget {
  final Animation<double> position;
  final Function(int) onTap;

  const GlassBottomNavBar({
    super.key,
    required this.position,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    const items = [
      (FontAwesomeIcons.magnifyingGlass, 'Search'),
      (FontAwesomeIcons.bookOpen, 'Vocabulary'),
      (FontAwesomeIcons.graduationCap, 'Test'),
      (FontAwesomeIcons.house, 'Home'),
    ];

    return RepaintBoundary(
      child: GlassContainer(
        borderRadius: 30,
        chrome: true,
        // Extra see-through so the aurora reads through the bar; the
        // specular ring + sheen keep the pane legible.
        opacity: p.isDark ? 0.22 : 0.30,
        rim: true,
        padding: const EdgeInsets.all(6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            return ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AnimatedBuilder(
                animation: position,
                builder: (context, _) {
                  final v = position.value.clamp(0.0, items.length - 1.0);
                  final active = v.round().clamp(0, items.length - 1);
                  return Stack(
                    children: [
                      // The lens that slides between tabs — scrubbed, not
                      // replayed, so it is always exactly where the finger is.
                      Positioned(
                        left: v * w / items.length,
                        width: w / items.length,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Container(
                            height: 52,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  p.accent.withValues(
                                      alpha: p.isDark ? 0.30 : 0.17),
                                  p.accent.withValues(
                                      alpha: p.isDark ? 0.12 : 0.08),
                                ],
                              ),
                              border: Border.all(
                                color: p.accent.withValues(alpha: 0.30),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: p.accent.withValues(alpha: 0.20),
                                  blurRadius: 14,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (final (i, (icon, label)) in items.indexed)
                            _NavItem(
                              palette: p,
                              icon: icon,
                              label: label,
                              index: i,
                              currentIndex: active,
                              onTap: onTap,
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final GlassPalette palette;
  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final Function(int) onTap;

  const _NavItem({
    required this.palette,
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final isActive = widget.index == widget.currentIndex;
    final fg = isActive ? p.accent : p.textSecondary;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          setState(() => _pressed = true);
        },
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () => widget.onTap(widget.index),
        child: AnimatedScale(
          scale: _pressed ? 0.88 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: SizedBox(
            height: 60,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  scale: isActive ? 1.12 : 1.0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(scale: anim, child: child),
                    ),
                    child: FaIcon(
                      widget.icon,
                      key: ValueKey(isActive),
                      color: fg,
                      size: isActive ? 18 : 16,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 240),
                  style: GlassText.body(
                    p,
                    10,
                    weight: isActive ? FontWeight.w600 : FontWeight.w500,
                    tracking: 0.2,
                    color: fg,
                  ),
                  child: Text(widget.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
