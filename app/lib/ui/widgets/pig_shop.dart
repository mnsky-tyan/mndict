import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/app_settings.dart';
import '../../services/farm_profile.dart';
import '../../services/pig_service.dart';
import '../theme/glass_theme.dart';
import 'glass_container.dart';
import 'glass_page.dart' show GlassIconButton;
import 'pig_decor.dart';
import 'pig_painter.dart';
import 'pressable.dart';
import '../screens/farm_journal.dart' show showFarmJournal;

/// Opens the Pig Market: the gacha that stocks the pen. A pull pays 15
/// coins and rolls a breed by rarity; the reveal wobbles, then bursts.
/// Adoptions land behind the sheet as the service notifies the scene.
Future<void> showPigMarket(
  BuildContext context,
  AppSettings settings,
  PigService pigs,
  FarmProfile profile,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // The route sits above the app's GlassScope, so the sheet brings its
    // own palette along.
    builder: (_) => GlassScope(
      palette: settings.isDarkMode ? GlassPalette.dark : GlassPalette.light,
      fontSize: 14.5,
      child: _PigMarketSheet(settings: settings, pigs: pigs, profile: profile),
    ),
  );
}

enum _PullPhase { idle, wobbling, reveal }

class _PigMarketSheet extends StatefulWidget {
  final AppSettings settings;
  final PigService pigs;
  final FarmProfile profile;

  const _PigMarketSheet({
    required this.settings,
    required this.pigs,
    required this.profile,
  });

  @override
  State<_PigMarketSheet> createState() => _PigMarketSheetState();
}

class _PigMarketSheetState extends State<_PigMarketSheet>
    with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  late final AnimationController _wobble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  _PullPhase _phase = _PullPhase.idle;
  PullResult? _result;
  Timer? _wobbleTimer;
  String? _status;
  bool _statusGood = false;
  int _tab = 0; // 0 piglets · 1 feed · 2 decor

  @override
  void dispose() {
    _idle.dispose();
    _wobble.dispose();
    _pop.dispose();
    _wobbleTimer?.cancel();
    super.dispose();
  }

  List<Widget> _feedTab(GlassPalette p) {
    final corn = widget.profile.corn;
    return [
      GlassContainer(
        blur: 0,
        chrome: true,
        sheen: false,
        borderRadius: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const FaIcon(FontAwesomeIcons.wheatAwn,
                    size: 13, color: Color(0xFFD9A428)),
                const SizedBox(width: 8),
                Text('Corn Basket · $corn ears',
                    style: GlassText.body(p, 13.5, weight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Hungry pigs walk to the trough and eat on their own. A pig "
              "that runs dry stops growing — and a starving sow won't "
              "start a family — so keep the basket topped up.",
              style:
                  GlassText.body(p, 12, height: 1.5, color: p.textSecondary),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          for (final (i, amount) in [1, 5, 10].indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Pressable(
                onTap: () async {
                  if (await widget.settings
                      .spendCoins(amount * PigService.cornPrice)) {
                    await widget.profile.addCorn(amount);
                    HapticFeedback.lightImpact();
                  } else {
                    HapticFeedback.selectionClick();
                  }
                },
                pressedScale: 0.96,
                child: Material(
                  color: widget.settings.coins >=
                          amount * PigService.cornPrice
                      ? p.accent
                      : p.textSecondary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(18),
                  elevation: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    child: Text(
                      '+$amount 🌽 · ${amount * PigService.cornPrice} 🪙',
                      textAlign: TextAlign.center,
                      style: GlassText.body(p, 12.5,
                          weight: FontWeight.w700,
                          height: 1.25,
                          color: p.isDark
                              ? const Color(0xFF0B1020)
                              : Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 10),
    ];
  }

  List<Widget> _decorTab(GlassPalette p) {
    final owned = widget.profile.decor;
    return [
      Text(
        'Dress up the yard. Props land in a free spot — long-press one at '
        'the farm to put it away for 60% back.',
        style: GlassText.body(p, 12, height: 1.5, color: p.textSecondary),
      ),
      const SizedBox(height: 10),
      for (final (i, item) in decorCatalog.indexed) ...[
        if (i > 0) const SizedBox(height: 8),
        Pressable(
          onTap: owned.containsKey(item.id) ? () => _putAway(item) : () => _buyDecor(item),
          pressedScale: 0.97,
          child: GlassContainer(
            blur: 0,
            chrome: !owned.containsKey(item.id),
            solid: owned.containsKey(item.id),
            sheen: false,
            borderRadius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  height: 54,
                  child: CustomPaint(
                    painter: _DecorThumb(item),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          style: GlassText.body(p, 13.5,
                              weight: FontWeight.w700)),
                      Text(
                        owned.containsKey(item.id)
                            ? 'In the yard'
                            : 'A little charm for the pen',
                        style: GlassText.body(p, 11,
                            color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  owned.containsKey(item.id)
                      ? 'Put away'
                      : '${item.price} 🪙',
                  style: GlassText.body(p, 13,
                      weight: FontWeight.w700,
                      color: owned.containsKey(item.id)
                          ? p.textSecondary
                          : const Color(0xFFE8A13C)),
                ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 10),
    ];
  }

  Future<void> _buyDecor(FarmDecor item) async {
    if (!await widget.settings.spendCoins(item.price)) {
      setState(() {
        _statusGood = false;
        _status = 'Not enough coins — save words and pass tests to earn more.';
      });
      return;
    }
    final slot = widget.profile.placeDecor(item.id);
    if (slot == null) {
      await widget.settings.addCoins(item.price); // yard full: refund
      setState(() {
        _statusGood = false;
        _status = 'The yard is full — put something away first.';
      });
      return;
    }
    HapticFeedback.lightImpact();
  }

  Future<void> _putAway(FarmDecor item) async {
    final refund = (item.price * 0.6).round();
    if (widget.profile.removeDecor(item.id)) {
      await widget.settings.addCoins(refund);
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _pull() async {
    if (_phase != _PullPhase.idle) return;
    if (widget.pigs.isFull) {
      setState(() {
        _statusGood = false;
        _status =
            'The pen is full (${PigService.capacity}/${PigService.capacity}) — sell a pig to make room.';
      });
      HapticFeedback.selectionClick();
      return;
    }

    final result = await widget.pigs.pull();
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _statusGood = false;
        _status =
            'Not enough coins — save words and pass tests to earn more.';
      });
      HapticFeedback.selectionClick();
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _result = result;
      _phase = _PullPhase.wobbling;
      _status = null;
    });
    _wobble.repeat(reverse: true);
    // The crate shakes for a beat — tap it to skip the suspense.
    _wobbleTimer = Timer(const Duration(milliseconds: 1250), _reveal);
  }

  void _reveal() {
    _wobbleTimer?.cancel();
    if (!mounted || _phase != _PullPhase.wobbling) return;
    _wobble.stop();
    setState(() => _phase = _PullPhase.reveal);
    _pop.forward(from: 0);
    final stars = _result?.breed.stars ?? 1;
    if (stars >= 4) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  void _backToIdle() {
    setState(() {
      _phase = _PullPhase.idle;
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;

    return AnimatedBuilder(
      animation: Listenable.merge(
          [widget.pigs, widget.settings.coinsChanged, widget.profile]),
      builder: (context, _) {
        final breeds = PigService.breeds;

        return GlassContainer(
          solid: true,
          blur: 14,
          borderRadius: 34,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.84,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle.
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
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pig Market',
                                style: GlassText.display(p, 23,
                                    weight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              'GACHA PEN · ${widget.pigs.pigs.length}/${PigService.capacity} in the pen',
                              style: GlassText.eyebrow(p),
                            ),
                          ],
                        ),
                      ),
                      GlassContainer(
                        blur: 0,
                        chrome: true,
                        sheen: false,
                        borderRadius: 999,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const FaIcon(FontAwesomeIcons.coins,
                                size: 11, color: Color(0xFFE8A13C)),
                            const SizedBox(width: 6),
                            Text('${widget.settings.coins}',
                                style: GlassText.body(p, 12.5,
                                    weight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GlassIconButton(
                        icon: FontAwesomeIcons.xmark,
                        size: 36,
                        iconSize: 13,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Piglets · Feed · Decor
                  Row(
                    children: [
                      for (final (i, label)
                          in ['Piglets', 'Feed', 'Decor'].indexed) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: Pressable(
                            onTap: () => setState(() {
                              _tab = i;
                              _status = null;
                            }),
                            pressedScale: 0.96,
                            child: Material(
                              color: _tab == i
                                  ? p.accent
                                  : p.textPrimary.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(16),
                              elevation: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                alignment: Alignment.center,
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
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_tab == 0) ...[
                    Text(
                      'Every word saved and test passed earns a coin. '
                      'A pull rolls a random breed — rarer pigs are worth more.',
                      style: GlassText.body(p, 12,
                          height: 1.5, color: p.textSecondary),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // The machine: crate, odds, pull button — or the reveal.
                  if (_tab == 0)
                  Center(
                    child: _phase == _PullPhase.reveal
                        ? _RevealCard(
                            result: _result!,
                            pop: _pop,
                            onDone: _backToIdle,
                            onAgain: () {
                              _backToIdle();
                              _pull();
                            },
                          )
                        : GestureDetector(
                            onTap:
                                _phase == _PullPhase.wobbling ? _reveal : _pull,
                            child: AnimatedBuilder(
                              animation: Listenable.merge([_idle, _wobble]),
                              builder: (context, _) => _MachineCanvas(
                                idle: _idle.value * 6,
                                wobble: _phase == _PullPhase.wobbling
                                    ? _wobble.value
                                    : 0,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),

                  // Feed tab: the corn basket.
                  if (_tab == 1) ..._feedTab(p),

                  // Decor tab: the yard shop.
                  if (_tab == 2) ..._decorTab(p),

                  if (_tab == 0 &&
                      (_phase == _PullPhase.idle ||
                          _phase == _PullPhase.wobbling)) ...[
                    Center(
                      child: Text(
                        _phase == _PullPhase.wobbling
                            ? 'Something is coming…'
                            : 'Adopt a pig · ${PigService.pullCost} coins',
                        style: GlassText.body(p, 13,
                            weight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        '★1 58% · ★2 25% · ★3 12% · ★4 4% · ★5 1%',
                        style: GlassText.body(p, 11,
                            color: p.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: Pressable(
                        onTap: _pull,
                        pressedScale: 0.97,
                        child: Material(
                          color: p.accent,
                          borderRadius: BorderRadius.circular(24),
                          elevation: 0,
                          child: Container(
                            height: 46,
                            alignment: Alignment.center,
                            child: Text(
                              widget.settings.coins < PigService.pullCost
                                  ? 'Need ${PigService.pullCost - widget.settings.coins} more coins'
                                  : 'Pull · ${PigService.pullCost} 🪙',
                              style: GlassText.body(
                                p,
                                14,
                                weight: FontWeight.w700,
                                color: p.isDark
                                    ? const Color(0xFF0B1020)
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],

                  if (_status != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        FaIcon(
                          _statusGood
                              ? FontAwesomeIcons.circleCheck
                              : FontAwesomeIcons.circleExclamation,
                          size: 12,
                          color: _statusGood ? p.success : p.warn,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _status!,
                            style: GlassText.body(p, 12,
                                weight: FontWeight.w600,
                                color: _statusGood ? p.success : p.warn),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Journal + codex teaser: the collection you're growing.
                  Row(
                    children: [
                      Expanded(
                        child: Pressable(
                          onTap: () => showFarmJournal(
                              context, widget.pigs, widget.profile),
                          pressedScale: 0.97,
                          child: GlassContainer(
                            blur: 0,
                            chrome: true,
                            sheen: false,
                            borderRadius: 18,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FaIcon(FontAwesomeIcons.book,
                                    size: 11, color: p.success),
                                const SizedBox(width: 8),
                                Text('Farm Journal',
                                    style: GlassText.body(p, 12.5,
                                        weight: FontWeight.w700)),
                                const SizedBox(width: 6),
                                Text(
                                  '${widget.pigs.discoveredCount}/${breeds.length}',
                                  style: GlassText.body(p, 11,
                                      color: p.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Miniature of a yard prop for the Decor shelf.
class _DecorThumb extends CustomPainter {
  final FarmDecor item;

  _DecorThumb(this.item);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height - 4);
    canvas.scale(math.min(size.width / 80, size.height / 80) * 1.35);
    DecorArt.paint(canvas, item, t: 1.2, night: false);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DecorThumb old) => old.item != item;
}

/// The crate you pull from: a wooden box with a snout-shaped keyhole,
/// resting idle or shaking with anticipation.
class _MachineCanvas extends StatelessWidget {
  final double idle; // seconds of slow idle time
  final double wobble; // -1..1 shake phase while a pull resolves

  const _MachineCanvas({required this.idle, required this.wobble});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      height: 150,
      child: CustomPaint(
        painter: _MachinePainter(idle: idle, wobble: wobble),
      ),
    );
  }
}

class _MachinePainter extends CustomPainter {
  final double idle;
  final double wobble;

  _MachinePainter({required this.idle, required this.wobble});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height - 30.0;

    // Ground shadow.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 4), width: 110, height: 18),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );

    canvas.save();
    canvas.translate(cx, cy);
    if (wobble != 0) {
      // Shake: quick rotate around the crate's base.
      canvas.rotate(wobble * 0.09);
      canvas.translate(math.sin(idle * 40) * 2, 0);
    } else {
      // Idle: gentle bob and tilt.
      canvas.rotate(math.sin(idle * 0.9) * 0.03);
      canvas.translate(0, math.sin(idle * 1.3) * 3);
    }

    // Crate body.
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(0, -34), width: 96, height: 74),
      const Radius.circular(10),
    );
    canvas.drawRRect(
        body, Paint()..color = const Color(0xFFC89B66));
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF9C7047),
    );
    // Slats.
    final slat = Paint()
      ..color = const Color(0xFF9C7047).withValues(alpha: 0.35)
      ..strokeWidth = 2.5;
    canvas.drawLine(const Offset(-44, -48), const Offset(44, -48), slat);
    canvas.drawLine(const Offset(-44, -20), const Offset(44, -20), slat);

    // Snout keyhole: the promise of a pig inside.
    final snout = Paint()..color = const Color(0xFFF2B9C6);
    canvas.drawCircle(const Offset(0, -40), 13, snout);
    canvas.drawCircle(const Offset(-5, -37), 2.2, Paint()..color = const Color(0xFF9C5566));
    canvas.drawCircle(const Offset(5, -37), 2.2, Paint()..color = const Color(0xFF9C5566));

    // Rope handle.
    canvas.drawLine(
      const Offset(0, -71),
      const Offset(0, -86),
      Paint()
        ..color = const Color(0xFF9C7047)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(const Offset(0, -89), 5, Paint()..color = const Color(0xFFE8A13C));

    canvas.restore();

    // Sparkle dust while waiting.
    if (wobble != 0) {
      for (var i = 0; i < 6; i++) {
        final a = math.sin(idle * 12 + i * 2.1).abs();
        canvas.drawCircle(
          Offset(cx + math.cos(i * 2.4) * (52 + a * 8), cy - 40 + math.sin(i * 1.7) * (30 + a * 10)),
          2 + a * 1.5,
          Paint()..color = const Color(0xFFFFD86B).withValues(alpha: 0.5 + a * 0.4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MachinePainter old) =>
      old.idle != idle || old.wobble != wobble;
}

/// Rarity accents for the reveal burst.
Color _rarityColor(int stars) => switch (stars) {
      1 => const Color(0xFF9BB0A5),
      2 => const Color(0xFF6FA8DC),
      3 => const Color(0xFFB08DE0),
      4 => const Color(0xFFF7C948),
      _ => const Color(0xFFFF8A3D),
    };

/// The pulled pig, popping in over a rarity-colored ray burst.
class _RevealCard extends StatelessWidget {
  final PullResult result;
  final Animation<double> pop;
  final VoidCallback onDone;
  final VoidCallback onAgain;

  const _RevealCard({
    required this.result,
    required this.pop,
    required this.onDone,
    required this.onAgain,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    final breed = result.breed;
    final accent = _rarityColor(breed.stars);

    return Column(
      children: [
        SizedBox(
          width: 210,
          height: 190,
          child: AnimatedBuilder(
            animation: pop,
            // The scale must be computed here, per tick — capturing it in
            // build() freezes it at easeOutBack(0) = 0 and the pig never
            // grows in.
            builder: (context, _) {
              final scale =
                  Curves.easeOutBack.transform(pop.value.clamp(0.0, 1.0));
              return CustomPaint(
                painter: _RevealPainter(
                  breed: breed,
                  t: pop.value,
                  accent: accent,
                  scale: scale,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(breed.name,
            style: GlassText.display(p, 20, weight: FontWeight.w700)),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 5; i++)
              Text(
                i < breed.stars ? '★' : '☆',
                style: TextStyle(
                  fontSize: 13,
                  color: i < breed.stars
                      ? const Color(0xFFF7C948)
                      : p.textSecondary.withValues(alpha: 0.4),
                ),
              ),
            const SizedBox(width: 8),
            FaIcon(
              result.pig.gender == PigGender.female
                  ? FontAwesomeIcons.venus
                  : FontAwesomeIcons.mars,
              size: 12,
              color: result.pig.gender == PigGender.female
                  ? const Color(0xFFE87BA4)
                  : const Color(0xFF6B96E0),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          result.isNewBreed
              ? 'New breed discovered!'
              : 'A ${breed.name} again — that\'s ${result.dupCount + 1} of them',
          style: GlassText.body(p, 12,
              weight: FontWeight.w600,
              color: result.isNewBreed ? p.success : p.textSecondary),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Pressable(
                onTap: onAgain,
                pressedScale: 0.96,
                child: GlassContainer(
                  blur: 0,
                  chrome: true,
                  sheen: false,
                  borderRadius: 20,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text('Adopt again',
                        style: GlassText.body(p, 13, weight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Pressable(
                onTap: onDone,
                pressedScale: 0.96,
                child: Material(
                  color: p.accent,
                  borderRadius: BorderRadius.circular(20),
                  elevation: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    child: Text('Keep',
                        style: GlassText.body(p, 13,
                            weight: FontWeight.w700,
                            color: p.isDark
                                ? const Color(0xFF0B1020)
                                : Colors.white)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Ray burst behind the revealed pig; grander the rarer the pull.
class _RevealPainter extends CustomPainter {
  final PigBreed breed;
  final double t; // 0..1 pop progress
  final Color accent;
  final double scale;

  _RevealPainter({
    required this.breed,
    required this.t,
    required this.accent,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height * 0.58;

    // Ray burst, expanding with the pop.
    final rayLen = 40 + t * 46;
    final rayPaint = Paint()
      ..color = accent.withValues(alpha: 0.35 * (1 - t * 0.4));
    for (var i = 0; i < 12; i++) {
      final ang = i * math.pi / 6 + t * 0.4;
      canvas.drawPath(
        Path()
          ..moveTo(cx + math.cos(ang) * (rayLen * 0.5), cy + math.sin(ang) * (rayLen * 0.5))
          ..lineTo(cx + math.cos(ang + 0.09) * rayLen * 1.7,
              cy + math.sin(ang + 0.09) * rayLen * 1.7)
          ..lineTo(cx + math.cos(ang - 0.09) * rayLen * 1.7,
              cy + math.sin(ang - 0.09) * rayLen * 1.7)
          ..close(),
        rayPaint,
      );
    }

    // Sparkles for 4★+.
    if (breed.stars >= 4) {
      for (var i = 0; i < 10; i++) {
        final ang = i * 2.51 + t * 3;
        final r = 55 + t * 30 + math.sin(i * 7.3) * 8;
        canvas.drawCircle(
          Offset(cx + math.cos(ang) * r, cy + math.sin(ang) * r * 0.8),
          2.2,
          Paint()
            ..color = const Color(0xFFFFD86B)
                .withValues(alpha: (1 - t * 0.5).clamp(0.0, 1.0)),
        );
      }
    }

    // The pig itself, scaled in.
    canvas.save();
    canvas.translate(cx, cy + 66);
    canvas.scale(scale);
    PigArt.paint(
      canvas,
      breed,
      PigPose(t: 2.0, happy: (1 - t).clamp(0.0, 1.0)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RevealPainter old) =>
      old.t != t || old.breed != breed || old.scale != scale;
}
