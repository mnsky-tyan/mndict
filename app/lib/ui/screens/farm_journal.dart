import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/farm_profile.dart';
import '../../services/pig_service.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/pig_painter.dart';
import '../widgets/pressable.dart';

/// Opens the Farm Journal: the long-game ledger — today's quests, the
/// breed codex, and the achievement wall. Three tabs, one scroll.
Future<void> showFarmJournal(
  BuildContext context,
  PigService pigs,
  FarmProfile profile,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => GlassScope(
      palette: GlassScope.of(context).palette,
      fontSize: 14.5,
      child: _JournalSheet(pigs: pigs, profile: profile),
    ),
  );
}

class _JournalSheet extends StatefulWidget {
  final PigService pigs;
  final FarmProfile profile;

  const _JournalSheet({required this.pigs, required this.profile});

  @override
  State<_JournalSheet> createState() => _JournalSheetState();
}

class _JournalSheetState extends State<_JournalSheet> {
  int _tab = 0; // 0 quests · 1 codex · 2 badges

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;

    return AnimatedBuilder(
      animation: Listenable.merge([widget.pigs, widget.profile]),
      builder: (context, _) {
        return GlassContainer(
          solid: true,
          blur: 14,
          borderRadius: 34,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.80,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4.5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: p.textSecondary.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Text('Farm Journal',
                      style: GlassText.display(p, 23, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.profile.farmName} · Lv.${widget.profile.level} ${widget.profile.title}'
                    '${widget.profile.streak > 0 ? ' · 🔥${widget.profile.streak}' : ''}',
                    style: GlassText.eyebrow(p),
                  ),
                  const SizedBox(height: 12),

                  // Tabs.
                  Row(
                    children: [
                      for (final (i, label) in
                          ['Quests', 'Codex', 'Badges'].indexed)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 4, right: i == 2 ? 0 : 4),
                            child: Pressable(
                              onTap: () => setState(() => _tab = i),
                              pressedScale: 0.97,
                              child: GlassContainer(
                                blur: 0,
                                solid: _tab == i,
                                sheen: false,
                                borderRadius: 14,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Center(
                                  child: Text(
                                    label,
                                    style: GlassText.body(p, 12.5,
                                        weight: FontWeight.w700,
                                        color: _tab == i
                                            ? (p.isDark
                                                ? const Color(0xFF0B1020)
                                                : Colors.white)
                                            : p.textSecondary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  switch (_tab) {
                    0 => _buildQuests(p),
                    1 => _buildCodex(p),
                    _ => _buildBadges(p),
                  },
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // -- quests ---------------------------------------------------------------

  Widget _buildQuests(GlassPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Daily board — a new three tomorrow',
            style: GlassText.body(p, 12, color: p.textSecondary)),
        const SizedBox(height: 10),
        for (final q in widget.profile.quests) ...[
          GlassContainer(
            blur: 0,
            chrome: true,
            sheen: false,
            borderRadius: 18,
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(q.title,
                          style: GlassText.body(p, 13,
                              weight: FontWeight.w700,
                              color: q.done ? p.success : p.textPrimary)),
                    ),
                    if (q.done)
                      FaIcon(FontAwesomeIcons.circleCheck,
                          size: 13, color: p.success)
                    else
                      Text('${q.progress}/${q.goal}',
                          style: GlassText.body(p, 12,
                              weight: FontWeight.w700,
                              color: p.textSecondary)),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 5,
                    child: Stack(
                      children: [
                        ColoredBox(
                            color: p.textSecondary.withValues(alpha: 0.15),
                            child: const SizedBox.expand()),
                        FractionallySizedBox(
                          widthFactor: (q.progress / q.goal).clamp(0.0, 1.0),
                          child: ColoredBox(
                              color:
                                  q.done ? p.success : p.accent,
                              child: const SizedBox.expand()),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('Reward · ${q.coinReward} 🪙 + ${q.xpReward} XP',
                    style: GlassText.body(p, 10.5, color: p.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  // -- codex ----------------------------------------------------------------

  Widget _buildCodex(GlassPalette p) {
    final breeds = PigService.breeds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Breeds discovered ${widget.pigs.discoveredCount}/${breeds.length} — the pool holds more than the pen will ever see',
          style: GlassText.body(p, 12, color: p.textSecondary),
        ),
        const SizedBox(height: 10),
        for (var row = 0; row < (breeds.length / 3).ceil(); row++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var col = 0; col < 3; col++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: col == 0 ? 0 : 5,
                      right: col == 2 ? 0 : 5,
                    ),
                    child: (row * 3 + col < breeds.length)
                        ? _CodexCard(
                            breed: breeds[row * 3 + col],
                            pulled:
                                widget.pigs.pulledByBreed[breeds[row * 3 + col].id] ?? 0,
                          )
                        : const SizedBox(height: 108),
                  ),
                ),
            ],
          ),
          if (row < (breeds.length / 3).ceil() - 1)
            const SizedBox(height: 8),
        ],
      ],
    );
  }

  // -- badges ---------------------------------------------------------------

  Widget _buildBadges(GlassPalette p) {
    final defs = FarmProfile.achievementDefs;
    final earned = widget.profile.badges;
    final s = widget.profile.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Earned ${earned.length}/${defs.length} · '
          '${s['saved'] ?? 0} words saved · ${s['mastered'] ?? 0} mastered · '
          '${s['pulls'] ?? 0} pulled · ${s['sales'] ?? 0} sold',
          style: GlassText.body(p, 12, color: p.textSecondary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in defs)
              _Badge(
                title: a.title,
                desc: a.desc,
                earned: earned.contains(a.id),
              ),
          ],
        ),
      ],
    );
  }
}

/// A codex entry: the breed if discovered, a grey silhouette if not,
/// plus the lifetime pull count.
class _CodexCard extends StatelessWidget {
  final PigBreed breed;
  final int pulled;

  const _CodexCard({required this.breed, required this.pulled});

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    final discovered = pulled > 0;

    return GlassContainer(
      blur: 0,
      chrome: true,
      sheen: false,
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
      child: Opacity(
        opacity: discovered ? 1.0 : 0.45,
        child: Column(
          children: [
            SizedBox(
              height: 54,
              width: double.infinity,
              child: discovered
                  ? CustomPaint(
                      painter: _CodexPigPainter(breed),
                    )
                  : CustomPaint(
                      painter: _SilhouettePainter(),
                    ),
            ),
            const SizedBox(height: 3),
            Text(
              discovered ? breed.name : '???',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GlassText.body(p, 11.5, weight: FontWeight.w700),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 5; i++)
                  Text(
                    i < breed.stars ? '★' : '☆',
                    style: TextStyle(
                      fontSize: 8.5,
                      color: i < breed.stars
                          ? const Color(0xFFF7C948)
                          : p.textSecondary.withValues(alpha: 0.4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              discovered
                  ? pulled == 1
                      ? 'pulled once'
                      : 'pulled ×$pulled'
                  : 'undiscovered',
              style: GlassText.body(p, 9.5, color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodexPigPainter extends CustomPainter {
  final PigBreed breed;

  _CodexPigPainter(this.breed);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2 - 2, size.height - 4);
    canvas.scale(0.55);
    PigArt.paint(canvas, breed, PigPose(t: 1.25));
  }

  @override
  bool shouldRepaint(_CodexPigPainter old) => old.breed != breed;
}

/// The undiscovered mystery: a fat question mark.
class _SilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: const TextSpan(
        text: '?',
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w900,
          color: Color(0x33000000),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        (size.width - tp.width) / 2,
        (size.height - tp.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_SilhouettePainter old) => false;
}

class _Badge extends StatelessWidget {
  final String title;
  final String desc;
  final bool earned;

  const _Badge({
    required this.title,
    required this.desc,
    required this.earned,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    return GlassContainer(
      blur: 0,
      chrome: true,
      sheen: false,
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            FontAwesomeIcons.medal,
            size: 13,
            color: earned
                ? const Color(0xFFF7C948)
                : p.textSecondary.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GlassText.body(p, 11.5,
                    weight: FontWeight.w700,
                    color: earned ? p.textPrimary : p.textSecondary),
              ),
              Text(
                desc,
                style: GlassText.body(p, 9.5,
                    color: p.textSecondary.withValues(
                        alpha: earned ? 1.0 : 0.6)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
