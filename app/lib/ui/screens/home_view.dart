import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/vocabulary_service.dart';
import '../theme/glass_theme.dart';
import '../widgets/aurora_orb.dart';
import '../widgets/glass_container.dart';
import '../widgets/pressable.dart';

/// The Home tab: a bento of the app's state — brand header, model hero,
/// stats, quick actions and the latest saved words — with a staggered
/// entrance so the page assembles itself when first shown.
class HomeView extends StatelessWidget {
  final int wordCount;
  final int coins;
  final String modelName;
  final String modelFilename;
  final double modelSizeMB;
  final bool modelReady;
  final bool modelBusy;
  final List<VocabularyItem> recentWords;
  final ValueChanged<int> onNav;

  const HomeView({
    super.key,
    required this.wordCount,
    required this.coins,
    required this.modelName,
    required this.modelFilename,
    required this.modelSizeMB,
    required this.modelReady,
    required this.modelBusy,
    required this.recentWords,
    required this.onNav,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    final statusColor = modelReady
        ? p.success
        : modelBusy
            ? p.warn
            : p.textSecondary;
    final statusLabel = modelReady
        ? 'Ready'
        : modelBusy
            ? 'Preparing…'
            : 'Not loaded';

    return ListView(
      padding: const EdgeInsets.only(top: 4),
      children: [
        // Brand header: the orb wordmark.
        _Entrance(
          delay: 0.0,
          child: Row(
            children: [
              const AuroraOrb(size: 26),
              const SizedBox(width: 9),
              Text('mndict',
                  style: GlassText.display(p, 19, tracking: -0.4)),
              const Spacer(),
              GlassContainer(
                blur: 0,
                chrome: true,
                sheen: false,
                borderRadius: 999,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaIcon(FontAwesomeIcons.coins,
                        size: 10, color: const Color(0xFFE8A13C)),
                    const SizedBox(width: 6),
                    Text('$coins',
                        style: GlassText.body(p, 12,
                            weight: FontWeight.w600,
                            color: p.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Entrance(
          delay: 0.08,
          child: Text('Your library',
              style: GlassText.display(p, 27)),
        ),
        const SizedBox(height: 3),
        _Entrance(
          delay: 0.12,
          child: Text(
            'Every definition is generated right here,\non this device.',
            style: GlassText.body(p, 12.5,
                height: 1.5, color: p.textSecondary),
          ),
        ),
        const SizedBox(height: 18),

        // Model hero.
        _Entrance(
          delay: 0.18,
          child: GlassContainer(
            blur: 0,
            borderRadius: 22,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        p.accent.withValues(alpha: 0.20),
                        p.accent.withValues(alpha: 0.07),
                      ],
                    ),
                    border: Border.all(
                      color: p.accent.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: FaIcon(FontAwesomeIcons.microchip,
                        size: 15, color: p.accent),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(modelName,
                          style: GlassText.body(p, 14.5,
                              weight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        '$modelFilename · ~${modelSizeMB.toInt()} MB',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GlassText.body(p, 10.5,
                            color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GlassContainer(
                  blur: 0,
                  chrome: true,
                  sheen: false,
                  borderRadius: 999,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6.5,
                        height: 6.5,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: modelReady
                              ? [
                                  BoxShadow(
                                    color: statusColor.withValues(alpha: 0.5),
                                    blurRadius: 5,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(statusLabel,
                          style: GlassText.body(p, 11,
                              weight: FontWeight.w600,
                              color: p.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Stats bento.
        _Entrance(
          delay: 0.26,
          child: Row(
            children: [
              Expanded(
                child: _BentoStat(
                  icon: FontAwesomeIcons.bookOpen,
                  iconColor: p.accent,
                  value: '$wordCount',
                  label: wordCount == 1 ? 'Word saved' : 'Words saved',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BentoStat(
                  icon: FontAwesomeIcons.coins,
                  iconColor: const Color(0xFFE8A13C),
                  value: '$coins',
                  label: 'Coins earned',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Quick actions.
        _Entrance(
          delay: 0.34,
          child: Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: FontAwesomeIcons.magnifyingGlass,
                  label: 'Look up',
                  filled: true,
                  onTap: () => onNav(0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickAction(
                  icon: FontAwesomeIcons.graduationCap,
                  label: 'Practice',
                  onTap: () => onNav(2),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // Recently saved.
        if (recentWords.isNotEmpty) ...[
          _Entrance(
            delay: 0.42,
            child: Text('RECENTLY SAVED', style: GlassText.eyebrow(p)),
          ),
          const SizedBox(height: 10),
            for (final (i, item) in recentWords.take(3).indexed)
              _Entrance(
                delay: 0.46 + i * 0.06,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Pressable(
                    onTap: () => onNav(1),
                    pressedScale: 0.98,
                    child: GlassContainer(
                      blur: 0,
                      borderRadius: 18,
                      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.word,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GlassText.reading(p, 14.5,
                                      weight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.definition,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GlassText.body(p, 11.5,
                                      color: p.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FaIcon(
                              FontAwesomeIcons.chevronRight,
                              size: 10,
                              color:
                                  p.textSecondary.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ],
        const SizedBox(height: 22),
        _Entrance(
          delay: 0.6,
          child: Center(
            child: Text(
              'mndict v0.1.0 · on-device AI',
              style: GlassText.body(p, 10.5,
                  tracking: 0.3,
                  color: p.textSecondary.withValues(alpha: 0.75)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Fade + rise entrance, delayed by [delay] (fraction of the total 640ms)
/// so home sections assemble in sequence.
class _Entrance extends StatelessWidget {
  final double delay;
  final Widget child;

  const _Entrance({required this.delay, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 640),
      curve: Interval(delay, 1.0, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _BentoStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _BentoStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    return GlassContainer(
      blur: 0,
      borderRadius: 20,
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  iconColor.withValues(alpha: 0.22),
                  iconColor.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(
                color: iconColor.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Center(child: FaIcon(icon, size: 13, color: iconColor)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: GlassText.display(p, 20)),
              const SizedBox(height: 1),
              Text(label,
                  style: GlassText.body(p, 10.5, color: p.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FaIcon(
          icon,
          size: 12,
          color: filled
              ? (p.isDark ? const Color(0xFF0B1020) : Colors.white)
              : p.accent,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GlassText.body(
            p,
            13.5,
            weight: FontWeight.w600,
            color: filled
                ? (p.isDark ? const Color(0xFF0B1020) : Colors.white)
                : p.textPrimary,
          ),
        ),
      ],
    );

    Widget action;
    if (filled) {
      action = Material(
        color: p.accent,
        borderRadius: BorderRadius.circular(18),
        elevation: 0,
        child: Container(height: 46, alignment: Alignment.center, child: content),
      );
    } else {
      action = GlassContainer(
        blur: 0,
        chrome: true,
        borderRadius: 18,
        padding: EdgeInsets.zero,
        child: Container(height: 46, alignment: Alignment.center, child: content),
      );
    }

    return Pressable(
      onTap: onTap,
      pressedScale: 0.95,
      child: action,
    );
  }
}
