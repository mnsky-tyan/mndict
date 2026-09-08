import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/app_settings.dart';
import '../../services/farm_profile.dart';
import '../../services/pig_service.dart';
import '../../services/worlds.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/glass_page.dart' show GlassIconButton;
import '../widgets/pig_decor.dart';
import '../widgets/pig_painter.dart';
import '../widgets/pressable.dart';
import '../widgets/pig_shop.dart' show showPigMarket;
import '../widgets/world_themes.dart';
import 'farm_journal.dart' show showFarmJournal;

/// Test-build escape hatch: long-press the coin pill to grant +1,000.
/// True so on-device playtesting has coins; flip to false before any
/// APK leaves this desk.
const bool kTestBuildsGrantCoins = true;

/// The Home tab: a pastoral world (in the 摩爾莊園 tradition) that grows
/// with the farm's level. Pigs arrive by gacha pull at the Market, raise
/// from Piglet to Chunky in real time, and are worth more the longer
/// they're kept. Coins come from saving words and passing tests.
class FarmView extends StatefulWidget {
  final AppSettings settings;
  final PigService pigs;
  final FarmProfile profile;
  final int wordCount;

  /// When provided, a door button leads the pill row — the way back out
  /// of farm mode into the dictionary. Null keeps the view embeddable
  /// without an exit (previews, tests).
  final VoidCallback? onExit;

  const FarmView({
    super.key,
    required this.settings,
    required this.pigs,
    required this.profile,
    required this.wordCount,
    this.onExit,
  });

  @override
  State<FarmView> createState() => _FarmViewState();
}

class _FarmViewState extends State<FarmView> {
  void _openMarket() {
    HapticFeedback.lightImpact();
    showPigMarket(context, widget.settings, widget.pigs, widget.profile);
  }

  void _openJournal() {
    HapticFeedback.lightImpact();
    showFarmJournal(context, widget.pigs, widget.profile);
  }

  void _openWorldPicker() {
    HapticFeedback.lightImpact();
    showWorldPicker(context, widget.profile);
  }

  Future<void> _renameFarm() async {
    final controller = TextEditingController(text: widget.profile.farmName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassScope.of(context).palette.solidFill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Name your farm',
            style: GlassText.display(GlassScope.of(context).palette, 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(
            hintText: 'My Farm',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      widget.profile.renameFarm(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;

    return Stack(
      children: [
        // The living world — its own widget so the per-frame ticker never
        // rebuilds the overlay chrome above it.
        Positioned.fill(
            child: _FarmWorld(
                pigs: widget.pigs,
                profile: widget.profile,
                settings: widget.settings)),

        // Coin / pen / library pills. In farm mode this view is the whole
        // screen, so the top overlays must clear the status bar inset.
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 20,
          child: AnimatedBuilder(
            animation: Listenable.merge(
                [widget.pigs, widget.settings.coinsChanged, widget.profile]),
            builder: (context, _) => Row(
              children: [
                if (widget.onExit != null) ...[
                  GlassIconButton(
                    icon: FontAwesomeIcons.doorOpen,
                    size: 30,
                    iconSize: 11,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onExit!();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                _FarmPill(
                  icon: FontAwesomeIcons.coins,
                  iconColor: const Color(0xFFE8A13C),
                  label: '${widget.settings.coins}',
                  onLongPress: kTestBuildsGrantCoins
                      ? () => widget.profile.debugGrantCoins(1000)
                      : null,
                ),
                const SizedBox(width: 8),
                _FarmPill(
                  icon: FontAwesomeIcons.wheatAwn,
                  iconColor: const Color(0xFFD9A428),
                  label: '${widget.profile.corn}',
                  onLongPress: kTestBuildsGrantCoins
                      ? () async {
                          await widget.profile.addCorn(10);
                          HapticFeedback.lightImpact();
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                _FarmPill(
                  icon: FontAwesomeIcons.paw,
                  iconColor: p.accent,
                  label:
                      '${widget.pigs.pigs.length}/${PigService.capacity}',
                ),
                const SizedBox(width: 8),
                _FarmPill(
                  icon: FontAwesomeIcons.bookOpen,
                  iconColor: p.success,
                  label: '${widget.wordCount}',
                ),
                const SizedBox(width: 8),
                GlassIconButton(
                  icon: FontAwesomeIcons.earthAsia,
                  size: 30,
                  iconSize: 12,
                  onTap: _openWorldPicker,
                ),
              ],
            ),
          ),
        ),

        // The farm's name plate: user-named, levelled, streaked. Its own
        // row — the pill row above grew an exit button and a big coin
        // count, too wide to share the top line.
        Positioned(
          top: MediaQuery.of(context).padding.top + 48,
          left: 0,
          right: 0,
          child: Center(
            child: Pressable(
              onTap: _renameFarm,
              pressedScale: 0.96,
              child: GlassContainer(
                blur: 0,
                chrome: true,
                sheen: false,
                borderRadius: 999,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: AnimatedBuilder(
                  animation: widget.profile,
                  builder: (context, _) {
                    final xpInto = widget.profile.xpIntoLevel
                        .clamp(0, widget.profile.xpLevelCost);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                widget.profile.farmName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GlassText.display(p, 13.5),
                              ),
                            ),
                            const SizedBox(width: 6),
                            FaIcon(FontAwesomeIcons.pen,
                                size: 8, color: p.textSecondary),
                            if (widget.profile.streak > 0) ...[
                              const SizedBox(width: 8),
                              Text('🔥${widget.profile.streak}',
                                  style: GlassText.body(p, 11,
                                      weight: FontWeight.w700)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Lv.${widget.profile.level}',
                                style: GlassText.body(p, 9.5,
                                    weight: FontWeight.w700,
                                    color: p.accent)),
                            const SizedBox(width: 6),
                            _XpBar(
                              progress: xpInto / widget.profile.xpLevelCost,
                              color: p.accent,
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),

        // Zoom + Market + Journal controls.
        Positioned(
          right: 20,
          bottom: MediaQuery.of(context).padding.bottom + 104,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Pressable(
                    onTap: () => _FarmWorld.zoomNotifier.value =
                        _ZoomRequest(-1),
                    pressedScale: 0.92,
                    child: GlassContainer(
                      blur: 0,
                      chrome: true,
                      sheen: false,
                      borderRadius: 999,
                      padding: const EdgeInsets.all(9),
                      child: FaIcon(FontAwesomeIcons.minus,
                          size: 12, color: p.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pressable(
                    onTap: () => _FarmWorld.zoomNotifier.value =
                        _ZoomRequest(1),
                    pressedScale: 0.92,
                    child: GlassContainer(
                      blur: 0,
                      chrome: true,
                      sheen: false,
                      borderRadius: 999,
                      padding: const EdgeInsets.all(9),
                      child: FaIcon(FontAwesomeIcons.plus,
                          size: 12, color: p.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Pressable(
                    onTap: _openJournal,
                    pressedScale: 0.94,
                    child: GlassContainer(
                      blur: 0,
                      chrome: true,
                      sheen: false,
                      borderRadius: 999,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 10),
                      child: FaIcon(FontAwesomeIcons.clipboardList,
                          size: 13, color: p.success),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pressable(
                    onTap: _openMarket,
                    pressedScale: 0.94,
                    child: GlassContainer(
                      blur: 0,
                      chrome: true,
                      sheen: false,
                      borderRadius: 999,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FaIcon(FontAwesomeIcons.store,
                              size: 12, color: p.accent),
                          const SizedBox(width: 8),
                          Text(
                            'Pig Market',
                            style: GlassText.body(p, 13.5,
                                weight: FontWeight.w700, tracking: 0.2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // First-run / sold-out: an empty pen with an invitation.
        AnimatedBuilder(
          animation: widget.pigs,
          builder: (context, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: widget.pigs.pigs.isEmpty
                ? _EmptyPen(palette: p, onOpenMarket: _openMarket)
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// A thin XP sliver for the name plate.
class _XpBar extends StatelessWidget {
  final double progress;
  final Color color;

  const _XpBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: 54,
        height: 4,
        child: Stack(
          children: [
            ColoredBox(
                color: color.withValues(alpha: 0.18),
                child: const SizedBox.expand()),
            FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: ColoredBox(color: color, child: const SizedBox.expand()),
            ),
          ],
        ),
      ),
    );
  }
}

class _FarmPill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onLongPress;

  const _FarmPill({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    return GestureDetector(
      onLongPress: onLongPress,
      child: GlassContainer(
        blur: 0,
        chrome: true,
        sheen: false,
        borderRadius: 999,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, size: 10, color: iconColor),
            const SizedBox(width: 6),
            Text(label,
                style: GlassText.body(p, 12,
                    weight: FontWeight.w700, color: p.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _EmptyPen extends StatelessWidget {
  final GlassPalette palette;
  final VoidCallback onOpenMarket;

  const _EmptyPen({required this.palette, required this.onOpenMarket});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Center(
      child: GlassContainer(
        blur: 0,
        borderRadius: 28,
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(110, 96),
                painter: _PreviewPainter(
                  PigService.breeds.first,
                  t: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text('Your farm is waiting', style: GlassText.display(p, 19)),
              const SizedBox(height: 7),
              Text(
                'Save words and pass tests to earn coins,\n'
                'then pull a pig at the Market — raise it,\n'
                'watch it grow, sell it for profit.',
                textAlign: TextAlign.center,
                style: GlassText.body(p, 12.5,
                    height: 1.55, color: p.textSecondary),
              ),
              const SizedBox(height: 16),
              Pressable(
                onTap: onOpenMarket,
                pressedScale: 0.96,
                child: Material(
                  color: p.accent,
                  borderRadius: BorderRadius.circular(24),
                  elevation: 0,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    alignment: Alignment.center,
                    child: Text(
                      'Visit the Market',
                      style: GlassText.body(
                        p,
                        14,
                        weight: FontWeight.w700,
                        color: p.isDark ? const Color(0xFF0B1020) : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A shop-card sized static pig preview.
class _PreviewPainter extends CustomPainter {
  final PigBreed breed;
  final double t;

  _PreviewPainter(this.breed, {required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2 - 4, size.height - 8);
    canvas.scale(size.width / 120);
    PigArt.paint(
      canvas,
      breed,
      PigPose(
        t: t,
        blink: (t * 0.4) % 3 < 0.10,
      ),
    );
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.t != t || old.breed != breed;
}

// ---------------------------------------------------------------------------
// The world: one big canvas, one ticker, a camera you can pan and pinch.
// ---------------------------------------------------------------------------

/// The grass band the herd roams, as fractions of world height.
const double _grassMin = 0.40;
const double _grassMax = 0.90;

/// Barn door position, as a fraction of world size — the herd's meeting
/// point for the stampede.
const Offset _barn = Offset(0.30, 0.33);

/// The care facilities, in the grass band: hungry pigs queue at the
/// trough, grubby pigs at the shower, expecting sows rest at the nest.
const Offset _trough = Offset(0.62, 0.56);
const Offset _shower = Offset(0.80, 0.62);
const Offset _nest = Offset(0.44, 0.72);

/// Fixed anchor points for yard decorations — buy a prop, it lands in
/// the first free slot.
const List<Offset> _decorAnchors = [
  Offset(0.16, 0.60),
  Offset(0.30, 0.80),
  Offset(0.68, 0.78),
  Offset(0.90, 0.66),
  Offset(0.55, 0.44),
  Offset(0.22, 0.46),
  Offset(0.88, 0.84),
  Offset(0.06, 0.78),
];

enum _PigState { idle, walk, nap, excited }

/// Where a pig is headed on its own behalf — the auto-interact layer.
enum _PigGoal { none, trough, shower, nest }

enum _FxKind { heart, dust, sparkle, bubble, crumb }

// SkyPhase lives in widgets/world_themes.dart with the backdrop painters.

SkyPhase _phaseFor(DateTime now) {
  final h = now.hour + now.minute / 60.0;
  if (h >= 5 && h < 8) return SkyPhase.dawn;
  if (h >= 8 && h < 17) return SkyPhase.day;
  if (h >= 17 && h < 20) return SkyPhase.dusk;
  return SkyPhase.night;
}

class _ZoomRequest {
  final int direction; // +1 in, -1 out
  const _ZoomRequest(this.direction);
}

class _PigEntity {
  final Pig pig;
  final PigBreed breed;

  // Position and target as fractions of the WORLD size.
  double x, y, tx, ty;
  _PigState state = _PigState.idle;
  double stateTime = 0;
  double stateDur = 1;
  double happy = 0;
  double happyAge = 10;
  double spawn = 0; // 0..1 entrance drop
  double squash = 0;
  double walkPhase = 0;
  double facing = 1; // which way the pig turns its face
  double speed;
  final double blinkSeed;
  final double idleSeed;

  /// Set when the pig decided to visit a facility; the arrival handler
  /// resolves it (eat, scrub, rest).
  _PigGoal goal = _PigGoal.none;

  _PigEntity(this.pig, Size size, math.Random rng)
      : breed = PigService.breedById(pig.breedId),
        x = 0.1 + rng.nextDouble() * 0.8,
        y = 0,
        tx = 0.5,
        ty = 0.7,
        speed =
            PigService.breedById(pig.breedId).speed * (0.85 + rng.nextDouble() * 0.3),
        blinkSeed = rng.nextDouble() * 3,
        idleSeed = rng.nextDouble() * 10 {
    y = _grassMin + rng.nextDouble() * (_grassMax - _grassMin);
  }
}

class _Heart {
  final Offset pos; // fraction of world size
  final _FxKind kind;
  final double seed;
  final double life;
  double age = 0;

  _Heart(this.pos, {this.kind = _FxKind.heart})
      : life = switch (kind) {
          _FxKind.heart => 1.4,
          _FxKind.dust => 1.0,
          _FxKind.sparkle => 0.9,
          _FxKind.bubble => 1.2,
          _FxKind.crumb => 0.8,
        },
        seed = math.Random().nextDouble() * 10;
}

class _FarmWorld extends StatefulWidget {
  final PigService pigs;
  final FarmProfile profile;
  final AppSettings settings;

  /// +/− zoom buttons on the farm chrome talk to the world through this.
  static final ValueNotifier<_ZoomRequest?> zoomNotifier =
      ValueNotifier(null);

  const _FarmWorld({
    required this.pigs,
    required this.profile,
    required this.settings,
  });

  @override
  State<_FarmWorld> createState() => _FarmWorldState();
}

class _FarmWorldState extends State<_FarmWorld>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final TransformationController _tf = TransformationController();
  final math.Random _rng = math.Random();
  final List<_PigEntity> _ents = [];
  final List<_Heart> _fx = [];
  double _t = 0;
  Duration _last = Duration.zero;
  Size _world = Size.zero;
  Size _viewport = Size.zero;
  bool _animate = true;
  bool _centered = false;

  static const double _minScale = 0.6;
  static const double _maxScale = 2.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    // The Market may pull pigs while this subtree isn't rebuilding (the
    // sheet lives above it), so the scene listens for itself.
    widget.pigs.addListener(_syncPigs);
    _FarmWorld.zoomNotifier.addListener(_onZoomRequest);
    _syncPigs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !MediaQuery.disableAnimationsOf(context);
    if (animate != _animate) {
      _animate = animate;
      if (animate) {
        if (!_ticker.isActive) _ticker.start();
      } else {
        _ticker.stop();
        if (mounted) setState(() {});
      }
    }
  }

  @override
  void didUpdateWidget(_FarmWorld old) {
    super.didUpdateWidget(old);
    _syncPigs();
  }

  @override
  void dispose() {
    widget.pigs.removeListener(_syncPigs);
    _FarmWorld.zoomNotifier.removeListener(_onZoomRequest);
    _ticker.dispose();
    _tf.dispose();
    super.dispose();
  }

  void _syncPigs() {
    final pigs = widget.pigs.pigs;
    // Pigs that left (sold) poof where they stood.
    _ents.removeWhere((e) {
      final gone = !pigs.any((p) => p.id == e.pig.id);
      if (gone) {
        for (var i = 0; i < 10; i++) {
          _fx.add(_Heart(Offset(e.x, e.y), kind: _FxKind.sparkle));
        }
        for (var i = 0; i < 5; i++) {
          _fx.add(_Heart(Offset(e.x, e.y), kind: _FxKind.dust));
        }
      }
      return gone;
    });
    for (final pig in pigs) {
      if (!_ents.any((e) => e.pig.id == pig.id)) {
        _ents.add(_PigEntity(pig, _world, _rng));
      }
    }
  }

  void _onZoomRequest() {
    final req = _FarmWorld.zoomNotifier.value;
    if (req == null || _viewport.isEmpty || _world.isEmpty) return;
    _FarmWorld.zoomNotifier.value = null;
    _zoomAbout(_viewport.center(Offset.zero),
        req.direction > 0 ? 1.35 : 1 / 1.35);
  }

  /// Scale by [factor] about a viewport point, clamped to the limits.
  void _zoomAbout(Offset point, double factor) {
    final current = _tf.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(_minScale, _maxScale);
    final f = target / current;
    final t = _tf.value.getTranslation();
    // p' = t + f*(p - t)  =>  t' = p - f*(p - t)
    final nx = point.dx - f * (point.dx - t.x);
    final ny = point.dy - f * (point.dy - t.y);
    _tf.value = Matrix4.identity()
      ..translateByDouble(nx, ny, 0, 1)
      ..scaleByDouble(target, target, 1, 1);
  }

  void _onTick(Duration elapsed) {
    final dt =
        ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    _last = elapsed;
    if (dt <= 0) return;
    _t += dt;
    _update(dt);
    if (mounted) setState(() {});
  }

  void _update(double dt) {
    // Piglets born while we were away (or mid-session) land here.
    if (widget.pigs.pregnant.isNotEmpty) widget.pigs.checkBirths();
    final now = DateTime.now();
    final corn = widget.profile.corn;

    for (final e in _ents) {
      if (e.spawn < 1) {
        e.spawn = math.min(1, e.spawn + dt / 0.85);
        if (e.spawn >= 1) {
          e.squash = 1;
          _spawnDust(e);
        }
      }
      e.squash = math.max(0, e.squash - dt * 3.2);
      e.happy = math.max(0, e.happy - dt / 1.7);
      e.happyAge += dt;

      e.stateTime += dt;
      if (e.stateTime >= e.stateDur) {
        e.stateTime = 0;
        switch (e.state) {
          case _PigState.idle:
            // Needs before whims: a pig with a chore heads out on its own.
            final goal = _pickGoal(e, now, corn);
            if (goal != _PigGoal.none) {
              _setGoal(e, goal);
            } else if (_rng.nextDouble() < e.breed.napChance) {
              e.state = _PigState.nap;
              e.stateDur = 3.5 + _rng.nextDouble() * 4;
            } else {
              e.state = _PigState.walk;
              e.stateDur = 1.6 + _rng.nextDouble() * 2.6;
              e.tx = 0.06 + _rng.nextDouble() * 0.88;
              e.ty = _grassMin + _rng.nextDouble() * (_grassMax - _grassMin);
              e.facing = e.tx >= e.x ? 1 : -1;
            }
          case _PigState.walk:
          case _PigState.nap:
          case _PigState.excited:
            e.state = _PigState.idle;
            e.stateDur = 0.9 + _rng.nextDouble() * 2.4;
        }
      }

      if (e.state == _PigState.walk) {
        const step = 0.052; // world widths per second
        final dx = e.tx - e.x, dy = e.ty - e.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        final stride = step * e.speed * dt;
        if (dist < stride * 1.5) {
          _arrive(e);
        } else {
          e.x += dx / dist * stride;
          e.y += dy / dist * stride;
          e.walkPhase += dt * 2.3 * e.speed;
        }
      }
      e.x = e.x.clamp(0.04, 0.96);
      e.y = e.y.clamp(_grassMin, _grassMax);
    }

    _fx.removeWhere((h) {
      h.age += dt;
      return h.age > h.life;
    });
  }

  /// What does this pig want right now? Expecting sows nest up, hungry
  /// pigs trot to the trough (while there's corn in the basket), grubby
  /// pigs find the shower.
  _PigGoal _pickGoal(_PigEntity e, DateTime now, int corn) {
    if (e.goal != _PigGoal.none) return e.goal; // already committed
    final due = e.pig.dueAt;
    if (due != null && due.difference(now) < const Duration(hours: 1)) {
      return _PigGoal.nest;
    }
    if (e.pig.hunger(now) < 55 && corn > 0) return _PigGoal.trough;
    if (e.pig.dirt(now) > 65) return _PigGoal.shower;
    return _PigGoal.none;
  }

  void _setGoal(_PigEntity e, _PigGoal goal) {
    e.goal = goal;
    final anchor = switch (goal) {
      _PigGoal.trough => _trough,
      _PigGoal.shower => _shower,
      _PigGoal.nest => _nest,
      _PigGoal.none => throw StateError('no goal'),
    };
    e.state = _PigState.walk;
    e.stateTime = 0;
    e.stateDur = 30;
    // A little jitter so a queue of pigs doesn't stack into one pig.
    e.tx = (anchor.dx + (_rng.nextDouble() - 0.5) * 0.06).clamp(0.04, 0.96);
    e.ty = (anchor.dy + (_rng.nextDouble() - 0.5) * 0.05)
        .clamp(_grassMin, _grassMax);
    e.facing = e.tx >= e.x ? 1 : -1;
  }

  /// A walking pig reached its target: resolve any chore, then idle.
  Future<void> _arrive(_PigEntity e) async {
    final goal = e.goal;
    e.goal = _PigGoal.none;
    e.state = _PigState.idle;
    e.stateTime = 0;
    e.stateDur = 1 + _rng.nextDouble() * 2.5;
    final at = Offset(e.x, e.y);
    switch (goal) {
      case _PigGoal.trough:
        if (await widget.profile.spendCorn(1)) {
          await widget.pigs.feed(e.pig);
          e.happy = 1;
          e.happyAge = 0;
          for (var i = 0; i < 5; i++) {
            _fx.add(_Heart(at, kind: _FxKind.crumb));
          }
          for (var i = 0; i < 2; i++) {
            _fx.add(_Heart(at, kind: _FxKind.heart));
          }
        }
      case _PigGoal.shower:
        await widget.pigs.bathe(e.pig);
        e.happy = 1;
        e.happyAge = 0;
        for (var i = 0; i < 8; i++) {
          _fx.add(_Heart(at, kind: _FxKind.bubble));
        }
      case _PigGoal.nest:
        // Expecting sows linger here; checkBirths does the rest.
        e.stateDur = 3 + _rng.nextDouble() * 4;
      case _PigGoal.none:
        break;
    }
  }

  void _spawnDust(_PigEntity e) {
    for (var i = 0; i < 6; i++) {
      _fx.add(_Heart(Offset(e.x, e.y), kind: _FxKind.dust));
    }
    for (var i = 0; i < 3; i++) {
      _fx.add(_Heart(Offset(e.x, e.y), kind: _FxKind.sparkle));
    }
  }

  void _pet(_PigEntity e) {
    e.happy = 1;
    e.happyAge = 0;
    e.state = _PigState.excited;
    e.stateTime = 0;
    e.stateDur = 1.3;
    HapticFeedback.lightImpact();
    widget.pigs.pet(e.pig);
    for (var i = 0; i < 6; i++) {
      _fx.add(_Heart(Offset(e.x, e.y)));
    }
    for (var i = 0; i < 8; i++) {
      _fx.add(_Heart(Offset(e.x, e.y), kind: _FxKind.sparkle));
    }
  }

  /// Tap the barn: the whole herd trots home.
  void _callHerd() {
    HapticFeedback.mediumImpact();
    for (final e in _ents) {
      e.state = _PigState.walk;
      e.stateTime = 0;
      e.stateDur = 30;
      e.tx = _barn.dx + 0.02 + _rng.nextDouble() * 0.10;
      e.ty = _grassMin + 0.02 + _rng.nextDouble() * 0.06;
      e.facing = e.tx >= e.x ? 1 : -1;
    }
  }

  void _handleTap(Offset local) {
    if (_world.isEmpty) return;
    // Barn first: it sits at the horizon, above every pig.
    final barnPx = Offset(_barn.dx * _world.width, _barn.dy * _world.height);
    if ((local - barnPx).distance < 80) {
      _callHerd();
      return;
    }
    // Front pigs win: nearest to the finger among the hit, by depth.
    _PigEntity? best;
    double bestDist = 1e9;
    final sorted = _ents.toList()..sort((a, b) => b.y.compareTo(a.y));
    for (final e in sorted) {
      final s = _scaleFor(e);
      final px = e.x * _world.width, py = e.y * _world.height;
      final dx = local.dx - px, dy = local.dy - (py - 46 * s);
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < PigArt.hitRadius * s + 16 && d < bestDist) {
        best = e;
        bestDist = d;
      }
    }
    if (best != null) {
      _pet(best);
      return;
    }
    // Care facilities.
    final troughPx = Offset(_trough.dx * _world.width, _trough.dy * _world.height);
    if ((local - troughPx).distance < 70) {
      HapticFeedback.lightImpact();
      showCornBasket(context, widget.settings, widget.profile);
      return;
    }
    final showerPx = Offset(_shower.dx * _world.width, _shower.dy * _world.height);
    if ((local - showerPx).distance < 70) {
      _sendToShower();
      return;
    }
    final decor = _decorAt(local);
    if (decor != null) {
      HapticFeedback.lightImpact();
      _fx.add(_Heart(decor.$2, kind: _FxKind.sparkle));
      _fx.add(_Heart(decor.$2, kind: _FxKind.sparkle));
    }
  }

  /// The decor prop under a world point, as (item id, world fraction).
  (String, Offset)? _decorAt(Offset local) {
    for (final entry in widget.profile.decor.entries) {
      if (entry.value < 0 || entry.value >= _decorAnchors.length) continue;
      final a = _decorAnchors[entry.value];
      final px = Offset(a.dx * _world.width, a.dy * _world.height);
      if ((local - px).distance < 55) return (entry.key, a);
    }
    return null;
  }

  /// Tap the shower: the grubbiest pig heads over to scrub up.
  void _sendToShower() {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    _PigEntity? grubbies;
    double worst = 25;
    for (final e in _ents) {
      final d = e.pig.dirt(now);
      if (d > worst) {
        worst = d;
        grubbies = e;
      }
    }
    if (grubbies == null) {
      // Everyone sparkles already — say so with a little fizz.
      final at = Offset(_shower.dx, _shower.dy);
      for (var i = 0; i < 4; i++) {
        _fx.add(_Heart(at, kind: _FxKind.bubble));
      }
      return;
    }
    _setGoal(grubbies, _PigGoal.shower);
  }

  void _handleLongPress(Offset local) {
    if (_world.isEmpty) return;
    _PigEntity? best;
    double bestDist = 1e9;
    final sorted = _ents.toList()..sort((a, b) => b.y.compareTo(a.y));
    for (final e in sorted) {
      final s = _scaleFor(e);
      final px = e.x * _world.width, py = e.y * _world.height;
      final d = (local - Offset(px, py - 40 * s)).distance;
      if (d < PigArt.hitRadius * s + 24 && d < bestDist) {
        best = e;
        bestDist = d;
      }
    }
    if (best != null) {
      HapticFeedback.mediumImpact();
      showPigProfile(context, widget.pigs, widget.profile, best.pig);
      return;
    }
    final decor = _world.isEmpty ? null : _decorAt(local);
    if (decor != null) _putAwayDecor(decor.$1);
  }

  /// Long-press a yard prop to box it back up: 60% of the price back.
  Future<void> _putAwayDecor(String id) async {
    final decor = decorById(id);
    if (decor == null) return;
    final p = GlassScope.of(context).palette;
    final refund = (decor.price * 0.6).round();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassScope.of(context).palette.solidFill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Put away ${decor.name}?',
            style: GlassText.display(GlassScope.of(context).palette, 17)),
        content: Text(
          'It goes back in the shed and you get $refund 🪙 of the '
          '${decor.price} 🪙 back.',
          style: GlassText.body(p, 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Put away',
                style: GlassText.body(p, 14,
                    weight: FontWeight.w700, color: p.warn)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (widget.profile.removeDecor(id)) {
      await widget.settings.addCoins(refund);
      HapticFeedback.lightImpact();
    }
  }

  double _scaleFor(_PigEntity e) {
    final stage = PigService.stageOf(e.pig);
    final stageScale = switch (stage) {
      PigStage.piglet => 0.72,
      PigStage.grown => 1.0,
      PigStage.chunky => 1.22,
    };
    final depth =
        ((e.y - _grassMin) / (_grassMax - _grassMin)).clamp(0.0, 1.0);
    return stageScale * (0.72 + 0.38 * depth);
  }

  @override
  Widget build(BuildContext context) {
    final dark = GlassScope.of(context).palette.isDark;
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        _world = Size(
          _viewport.width * 2.5,
          _viewport.height * 1.8,
        );
        // Start centred on the world, once.
        if (!_centered && _viewport.width > 0) {
          _centered = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _tf.value = Matrix4.identity()
              ..translateByDouble(
                (_viewport.width - _world.width) / 2,
                (_viewport.height - _world.height) / 2,
                0,
                1,
              );
          });
        }
        return InteractiveViewer(
          transformationController: _tf,
          // constrained: false — the child keeps its true world size
          // (2.5×1.8 viewports); the default would squeeze the world back
          // down to the viewport and kill the whole point.
          constrained: false,
          minScale: _minScale,
          maxScale: _maxScale,
          // Zero margin: the world is bigger than the viewport, so the
          // camera can never show space beyond its edges.
          boundaryMargin: EdgeInsets.zero,
          child: SizedBox(
            width: _world.width,
            height: _world.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _handleTap(d.localPosition),
              onLongPressStart: (d) => _handleLongPress(d.localPosition),
              onDoubleTapDown: (d) {
                // The gesture reports world coordinates; zoom math wants
                // the viewport point under the finger.
                final vp =
                    MatrixUtils.transformPoint(_tf.value, d.localPosition);
                _zoomAbout(vp, 1.6);
              },
              onDoubleTap: () {},
              child: CustomPaint(
                size: _world,
                painter: _WorldPainter(
                  ents: _ents,
                  fx: _fx,
                  t: _t,
                  dark: dark,
                  animate: _animate,
                  phase: _phaseFor(DateTime.now()),
                  level: widget.profile.level,
                  world: widget.profile.world,
                  decor: {
                    for (final e in widget.profile.decor.entries)
                      if (e.value >= 0 && e.value < _decorAnchors.length)
                        e.value: e.key,
                  },
                  careNow: DateTime.now(),
                  cornFill: (widget.profile.corn / PigService.cornTroughCapacity)
                      .clamp(0.0, 1.0),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// The painter: sky, hills, level props, herd, particles — one canvas pass.
// ---------------------------------------------------------------------------

double _hash(int i) =>
    ((math.sin(i * 127.1) * 43758.5453) % 1.0).abs();

class _WorldPainter extends CustomPainter {
  final List<_PigEntity> ents;
  final List<_Heart> fx;
  final double t;
  final bool dark;
  final bool animate;
  final SkyPhase phase;
  final int level;
  final WorldId world; // which backdrop theme to paint
  final Map<int, String> decor; // yard slot -> decor item id
  final DateTime careNow; // frozen per frame for hunger/dirt reads
  final double cornFill; // 0..1 — how full the basket is

  _WorldPainter({
    required this.ents,
    required this.fx,
    required this.t,
    required this.dark,
    required this.animate,
    required this.phase,
    required this.level,
    required this.world,
    required this.decor,
    required this.careNow,
    required this.cornFill,
  });

  bool get isNightSky => phase == SkyPhase.night || dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final horizon = h * 0.33;

    // One backdrop pass: sky, horizon and theme props for whichever
    // world the herd lives in (widgets/world_themes.dart).
    WorldBackdrop.paint(canvas, size, world,
        phase: phase, night: dark, level: level, t: t);


    // Sunlit dust motes drifting over the field (day only).
    if (!isNightSky) {
      for (var i = 0; i < 16; i++) {
        final drift = t * (0.008 + 0.006 * _hash(i + 900));
        final mx = ((_hash(i + 800) + drift) % 1.0) * w;
        final my = horizon +
            _hash(i + 850) * (h - horizon) * 0.75 +
            math.sin(t * (0.6 + _hash(i)) + i) * 6;
        final a =
            0.10 + 0.14 * (0.5 + 0.5 * math.sin(t * 1.7 + i * 2.3));
        canvas.drawCircle(
          Offset(mx, my),
          1.0 + _hash(i + 880) * 1.4,
          Paint()..color = Colors.white.withValues(alpha: a),
        );
      }
    }

    // The herd, the care facilities and the yard props share one ground
    // plane, so they draw together, back to front.
    final draws = <(double, int, int)>[ // (y, kind, index); kinds below
      (0.56, 1, 0), // trough
      (0.62, 2, 0), // shower
      (0.72, 3, 0), // nest
      for (final entry in decor.entries) (_decorAnchors[entry.key].dy, 4, entry.key),
      for (var i = 0; i < ents.length; i++) (ents[i].y, 0, i),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, kind, index) in draws) {
      switch (kind) {
        case 0:
          _paintPig(canvas, size, ents[index]);
        case 1:
          _paintTrough(canvas, Offset(_trough.dx * w, _trough.dy * h),
              fill: cornFill);
        case 2:
          _paintShower(canvas, Offset(_shower.dx * w, _shower.dy * h));
        case 3:
          _paintNest(canvas, Offset(_nest.dx * w, _nest.dy * h));
        case 4:
          final anchor = _decorAnchors[index];
          canvas.save();
          canvas.translate(anchor.dx * w, anchor.dy * h);
          DecorArt.paint(
              canvas, decorById(decor[index]!)!, t: t, night: isNightSky);
          canvas.restore();
      }
    }

    _paintParticles(canvas, size);
  }

  /// One pig: joy halo, pregnancy heart bubble, the body with its care
  /// state (mud, hunger blues) painted in, and its name when happy.
  void _paintPig(Canvas canvas, Size size, _PigEntity e) {
    final w = size.width, h = size.height;
    final s = _scaleOf(e);
    final lift = _liftOf(e);
      // A soft halo of joy behind a freshly petted pig.
      if (e.happy > 0.05) {
        final joy = e.happy.clamp(0.0, 1.0);
        final joyRect = Rect.fromCenter(
          center: Offset(e.x * w, e.y * h - 52 * s - lift),
          width: 210 * s,
          height: 210 * s,
        );
        canvas.drawCircle(
          joyRect.center,
          joyRect.width / 2,
          Paint()
            ..shader = RadialGradient(colors: [
              Colors.white.withValues(alpha: 0.20 * joy),
              Colors.white.withValues(alpha: 0.0),
            ]).createShader(joyRect),
        );
      }
      canvas.save();
      canvas.translate(e.x * w, e.y * h);
      canvas.scale(s);
      PigArt.paint(
        canvas,
        e.breed,
        PigPose(
          t: t + e.idleSeed,
          walk: e.state == _PigState.walk && animate ? e.walkPhase : -1,
          sleeping: e.state == _PigState.nap,
          blink: animate &&
              ((t * 0.35 + e.blinkSeed) % 3.0) < 0.09 &&
              e.state != _PigState.nap,
          happy: e.happy,
          squash: e.squash,
          lean: e.state == _PigState.walk
              ? math.sin(e.walkPhase * 12.56) * 0.03
              : 0,
          lift: lift,
          facing: e.facing,
          chub: switch (PigService.stageOf(e.pig)) {
            PigStage.piglet => 0.0,
            PigStage.grown => 0.4,
            PigStage.chunky => 1.0,
          },
          dirt: e.pig.dirt(careNow) / 100,
          sad: e.pig.hunger(careNow) < 15
              ? (15 - e.pig.hunger(careNow)) / 15
              : 0,
        ),
      );
      canvas.restore();

      if (e.happy > 0.15) {
        _paintNameBubble(canvas, e, size, s, lift);
      }

      // An expecting sow wears a bobbing heart over her head.
      if (e.pig.isPregnant) {
        final bob = math.sin(t * 2.6) * 4;
        final cxy = Offset(e.x * w, e.y * h - 128 * s - lift + bob);
        final paint = Paint()
          ..color = const Color(0xFFFF6D8D).withValues(alpha: 0.95);
        canvas.save();
        canvas.translate(cxy.dx, cxy.dy);
        canvas.scale(0.8);
        canvas.drawCircle(const Offset(-3.4, -2), 3.6, paint);
        canvas.drawCircle(const Offset(3.4, -2), 3.6, paint);
        final tip = Path()
          ..moveTo(-6.6, -0.5)
          ..lineTo(0, 7.5)
          ..lineTo(6.6, -0.5)
          ..close();
        canvas.drawPath(tip, paint);
        canvas.restore();
      }

    // Dawn/dusk: a warm wash over everything.
    if (phase == SkyPhase.dawn || phase == SkyPhase.dusk) {
      final warm = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFF9D5C).withValues(alpha: 0.22),
            const Color(0xFFFFC46B).withValues(alpha: 0.10),
            const Color(0xFFFF9D5C).withValues(alpha: 0.05),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h));
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), warm);
    }
  }

  double _scaleOf(_PigEntity e) {
    final stage = PigService.stageOf(e.pig);
    final stageScale = switch (stage) {
      PigStage.piglet => 0.72,
      PigStage.grown => 1.0,
      PigStage.chunky => 1.22,
    };
    final depth =
        ((e.y - _grassMin) / (_grassMax - _grassMin)).clamp(0.0, 1.0);
    return stageScale * (0.72 + 0.38 * depth);
  }

  double _liftOf(_PigEntity e) {
    var lift = 0.0;
    if (e.spawn < 1) lift += math.pow(1 - e.spawn, 2) * 260;
    if (e.state == _PigState.excited) {
      lift += math.sin(e.happyAge * 11).abs() *
          16 *
          math.max(0, 1 - e.happyAge / 1.3);
    }
    return lift;
  }

  // -- care stations (shared by every world) ---------------------------------

  /// The feed trough. The corn pile swells with the basket's fill level,
  /// so a quick glance tells you whether the herd is fed for the day.
  void _paintTrough(Canvas canvas, Offset at, {required double fill}) {
    final wood = Paint()..color = const Color(0xFF9C7047);
    final woodDark = Paint()..color = const Color(0xFF7B5636);
    canvas.save();
    canvas.translate(at.dx, at.dy);

    canvas.drawRect(Rect.fromLTWH(-34, -14, 7, 16), woodDark);
    canvas.drawRect(Rect.fromLTWH(27, -14, 7, 16), woodDark);
    final box = Path()
      ..moveTo(-40, -30)
      ..lineTo(40, -30)
      ..lineTo(34, -14)
      ..lineTo(-34, -14)
      ..close();
    canvas.drawPath(box, wood);
    canvas.drawPath(
      box,
      Paint()
        ..color = const Color(0xFF7B5636)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawLine(const Offset(-37, -22), Offset(37, -22), woodDark..strokeWidth = 2);

    if (fill > 0.02) {
      final heap = Rect.fromCenter(
          center: const Offset(0, -30), width: 66 * (0.5 + 0.5 * fill), height: 16);
      canvas.drawOval(heap, Paint()..color = const Color(0xFFF7C948));
      for (var i = 0; i < 4; i++) {
        final kx = -18.0 + i * 12.0;
        canvas.drawCircle(
            Offset(kx, -30 - (i.isEven ? 3 : 1)),
            4,
            Paint()..color = const Color(0xFFFFE28A));
      }
    }
    canvas.restore();
  }

  /// The yard shower: a post, an arm, a head, and a lazy drip.
  void _paintShower(Canvas canvas, Offset at) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.drawLine(
      const Offset(0, 0),
      const Offset(0, -84),
      Paint()
        ..color = const Color(0xFF8A97A8)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      const Offset(0, -84),
      const Offset(-22, -84),
      Paint()
        ..color = const Color(0xFF8A97A8)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(-22, -80), width: 22, height: 7),
      Paint()..color = const Color(0xFFB9C6D6),
    );
    canvas.drawCircle(const Offset(4, -58), 6,
        Paint()..color = const Color(0xFFE5484D));
    canvas.drawCircle(const Offset(4, -58), 2.4,
        Paint()..color = const Color(0xFFD9D2C4));
    final drip = (t * 0.7) % 1.0;
    if (drip < 0.35) {
      canvas.drawCircle(
        Offset(-22, -74 + drip * 90),
        2.4,
        Paint()..color = const Color(0xFF9ED9F2).withValues(alpha: 0.85),
      );
    }
    canvas.drawRect(Rect.fromCenter(center: const Offset(-14, -2), width: 52, height: 6),
        Paint()..color = const Color(0xFFC89B66));
    canvas.restore();
  }

  /// The nesting straw: a soft ring where an expecting sow waits out the
  /// last hour before her litter arrives.
  void _paintNest(Canvas canvas, Offset at) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    final outer = Rect.fromCenter(center: const Offset(0, -8), width: 92, height: 30);
    canvas.drawOval(outer, Paint()..color = const Color(0xFFE0B95C));
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, -8), width: 66, height: 18),
      Paint()..color = const Color(0xFFF2D9A0),
    );
    final straw = Paint()
      ..color = const Color(0xFFB58836)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + 0.3;
      final dx = math.cos(a) * 44;
      final dy = math.sin(a) * 13 - 8;
      canvas.drawLine(Offset(dx, dy), Offset(dx * 1.14, dy - 5), straw);
    }
    canvas.restore();
  }

  // -- effects ---------------------------------------------------------------

  void _paintNameBubble(
      Canvas canvas, _PigEntity e, Size size, double s, double lift) {
    final tp = TextPainter(
      text: TextSpan(
        text: e.pig.name,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
          color: Color(0xFF17203D),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final alpha = e.happy.clamp(0.0, 1.0);
    final cx = e.x * size.width;
    final cy = e.y * size.height - (108 * s + lift + 26);
    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: tp.width + 20,
      height: 24,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(
      rrect,
      Paint()..color = Colors.white.withValues(alpha: 0.92 * alpha),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF17203D).withValues(alpha: 0.10 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Pointer notch.
    final notch = Path()
      ..moveTo(cx - 4, rect.bottom)
      ..lineTo(cx, rect.bottom + 5)
      ..lineTo(cx + 4, rect.bottom)
      ..close();
    canvas.drawPath(
        notch, Paint()..color = Colors.white.withValues(alpha: 0.92 * alpha));

    tp.paint(canvas, rect.topLeft + Offset(10, (24 - tp.height) / 2));
  }

  void _paintParticles(Canvas canvas, Size size) {
    for (final h in fx) {
      final a = h.age / h.life;
      switch (h.kind) {
        case _FxKind.dust:
          final spread = 14 + a * 26;
          for (var i = 0; i < 6; i++) {
            final ang = i * math.pi / 3 + h.seed;
            canvas.drawCircle(
              Offset(
                h.pos.dx * size.width + math.cos(ang) * spread,
                h.pos.dy * size.height - 4 - a * 8 + math.sin(ang) * spread * 0.3,
              ),
              4.5 * (1 - a) + 1,
              Paint()
                ..color = (isNightSky
                        ? const Color(0xFFB9AE9A)
                        : const Color(0xFFE4D6B8))
                    .withValues(alpha: 0.55 * (1 - a)),
            );
          }
        case _FxKind.sparkle:
          // A golden four-point star flying up and out, twinkling as it
          // fades — the pet-reward sparkle.
          final ang = h.seed * 6 + (h.seed > 5 ? 1.2 : -1.2);
          final cx = h.pos.dx * size.width + math.cos(ang) * (10 + a * 30);
          final cy =
              h.pos.dy * size.height - 55 - a * 46 + math.sin(ang) * 8;
          final tw = (0.55 + 0.45 * math.sin(h.age * 24 + h.seed * 9))
              .clamp(0.15, 1.0);
          final sc = (1.15 - a) * 4.2 * tw;
          if (sc <= 0.2) break;
          final paint = Paint()
            ..color = const Color(0xFFFFD86B)
                .withValues(alpha: 0.95 * (1 - a) * tw);
          canvas.save();
          canvas.translate(cx, cy);
          canvas.rotate(h.seed + h.age * 2);
          final star = Path()
            ..moveTo(0, -sc)
            ..quadraticBezierTo(sc * 0.22, -sc * 0.22, sc, 0)
            ..quadraticBezierTo(sc * 0.22, sc * 0.22, 0, sc)
            ..quadraticBezierTo(-sc * 0.22, sc * 0.22, -sc, 0)
            ..quadraticBezierTo(-sc * 0.22, -sc * 0.22, 0, -sc);
          canvas.drawPath(star, paint);
          canvas.drawCircle(
            Offset.zero,
            sc * 0.22,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.9 * (1 - a) * tw),
          );
          canvas.restore();
        case _FxKind.bubble:
          // A soap bubble wobbling up from the shower.
          final bx = h.pos.dx * size.width +
              math.sin(h.age * 6 + h.seed * 8) * 10;
          final by = h.pos.dy * size.height - 40 - h.age * 70;
          final r = 4 + (1 - a) * 4;
          canvas.drawCircle(
            Offset(bx, by),
            r,
            Paint()
              ..color = const Color(0xFF9ED9F2).withValues(alpha: 0.30 * (1 - a)),
          );
          canvas.drawCircle(
            Offset(bx, by),
            r,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.55 * (1 - a))
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4,
          );
        case _FxKind.crumb:
          // A golden corn crumb popping up from the trough.
          final cx = h.pos.dx * size.width + math.cos(h.seed * 9) * (6 + a * 22);
          final cy = h.pos.dy * size.height -
              20 -
              math.sin(a * math.pi) * 26 -
              a * 8;
          canvas.drawCircle(
            Offset(cx, cy),
            3.2 * (1 - a) + 1,
            Paint()
              ..color = const Color(0xFFF7C948)
                  .withValues(alpha: 0.95 * (1 - a)),
          );
        case _FxKind.heart:
          // A floating heart: two lobes and a tip, rising with a wobble.
          final cx = h.pos.dx * size.width +
              math.sin(h.age * 7 + h.seed * 6) * 9;
          final cy = h.pos.dy * size.height - 70 - h.age * 55;
          final sc = 1 + a * 0.5;
          final alpha = (1 - a) * 0.95;
          final paint = Paint()
            ..color = const Color(0xFFFF6D8D).withValues(alpha: alpha);
          canvas.save();
          canvas.translate(cx, cy);
          canvas.scale(sc);
          canvas.drawCircle(const Offset(-3.4, -2), 3.6, paint);
          canvas.drawCircle(const Offset(3.4, -2), 3.6, paint);
          final tip = Path()
            ..moveTo(-6.6, -0.5)
            ..lineTo(0, 7.5)
            ..lineTo(6.6, -0.5)
            ..close();
          canvas.drawPath(tip, paint);
          canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_WorldPainter old) => true;
}

/// The corn basket: buy ears for the trough. Hungry pigs trot over and
/// help themselves, so keeping the basket stocked IS feeding the herd.
/// The world picker: where the herd lives. Locked worlds show their
/// unlock level; the current one carries the herd.
Future<void> showWorldPicker(BuildContext context, FarmProfile profile) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => GlassScope(
      palette: GlassScope.of(context).palette,
      fontSize: 14.5,
      child: _WorldPickerSheet(profile: profile),
    ),
  );
}

class _WorldPickerSheet extends StatelessWidget {
  final FarmProfile profile;

  const _WorldPickerSheet({required this.profile});

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    final current = profile.world;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: p.solidFill,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: p.borderFaint),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Worlds', style: GlassText.display(p, 17)),
            const SizedBox(height: 4),
            Text(
              'Move the herd. Every world keeps your pigs, pens and props.',
              style: GlassText.body(p, 12, color: p.textSecondary),
            ),
            const SizedBox(height: 12),
            for (final theme in worldCatalog) ...[
              _worldRow(context, theme, current),
              if (theme != worldCatalog.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _worldRow(BuildContext context, WorldTheme theme, WorldId current) {
    final p = GlassScope.of(context).palette;
    final locked = profile.level < theme.unlockLevel;
    final selected = theme.id == current;
    return Pressable(
      pressedScale: 0.98,
      onTap: locked || selected
          ? null
          : () async {
              HapticFeedback.mediumImpact();
              await profile.setWorld(theme.id);
              if (context.mounted) Navigator.of(context).pop();
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? p.accent.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? p.accent : p.borderFaint,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(theme.emoji,
                style: const TextStyle(fontSize: 22),
                // Locked worlds keep their icon but lose their colour.
                semanticsLabel: theme.name),
            if (locked)
              Icon(FontAwesomeIcons.lock, size: 12,
                  color: p.textSecondary.withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(theme.name,
                      style: GlassText.body(p, 14, weight: FontWeight.w700)),
                  Text(
                    locked
                        ? 'Unlocks at Farm Lv.${theme.unlockLevel}'
                        : theme.blurb,
                    style:
                        GlassText.body(p, 11.5, color: p.textSecondary),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(FontAwesomeIcons.circleCheck,
                  size: 18, color: p.accent),
          ],
        ),
      ),
    );
  }
}

Future<void> showCornBasket(
  BuildContext context,
  AppSettings settings,
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
      child: _CornBasketSheet(settings: settings, profile: profile),
    ),
  );
}

class _CornBasketSheet extends StatelessWidget {
  final AppSettings settings;
  final FarmProfile profile;

  const _CornBasketSheet({required this.settings, required this.profile});

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    return AnimatedBuilder(
      animation: Listenable.merge([profile, settings.coinsChanged]),
      builder: (context, _) => GlassContainer(
        solid: true,
        blur: 14,
        borderRadius: 34,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Corn Basket',
                          style:
                              GlassText.display(p, 21, weight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('THE TROUGH · ${profile.corn} ears in the basket',
                          style: GlassText.eyebrow(p)),
                    ],
                  ),
                ),
                GlassIconButton(
                  icon: FontAwesomeIcons.xmark,
                  size: 36,
                  iconSize: 13,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "Hungry pigs walk to the trough and eat on their own. "
              "A pig that runs dry stops growing — and a starving sow "
              "won't start a family — so keep the basket topped up.",
              style: GlassText.body(p, 12.5, height: 1.5, color: p.textSecondary),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final (i, amount) in [1, 5, 10].indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: Pressable(
                      onTap: () async {
                        if (await settings
                            .spendCoins(amount * PigService.cornPrice)) {
                          await profile.addCorn(amount);
                          HapticFeedback.lightImpact();
                        } else {
                          HapticFeedback.selectionClick();
                        }
                      },
                      pressedScale: 0.96,
                      child: Material(
                        color: settings.coins >= amount * PigService.cornPrice
                            ? p.accent
                            : p.textSecondary.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(20),
                        elevation: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          child: Text(
                            '+$amount 🌽 · ${amount * PigService.cornPrice} 🪙',
                            style: GlassText.body(p, 13,
                                weight: FontWeight.w700,
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
          ],
        ),
      ),
    );
  }
}

/// The long-press pig card: identity, gender, mood, growth, worth —
/// and the care verbs: feed, match-make, rename, sell.
Future<void> showPigProfile(
  BuildContext context,
  PigService pigs,
  FarmProfile profile,
  Pig pig,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => GlassScope(
      palette: GlassScope.of(context).palette,
      fontSize: 14.5,
      child: _PigProfileSheet(pigs: pigs, profile: profile, pig: pig),
    ),
  );
}

class _PigProfileSheet extends StatefulWidget {
  final PigService pigs;
  final FarmProfile profile;
  final Pig pig;

  const _PigProfileSheet({
    required this.pigs,
    required this.profile,
    required this.pig,
  });

  @override
  State<_PigProfileSheet> createState() => _PigProfileSheetState();
}

class _PigProfileSheetState extends State<_PigProfileSheet> {
  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    final breed = PigService.breedById(widget.pig.breedId);
    final stage = PigService.stageOf(widget.pig);
    final worth = PigService.sellValueOf(widget.pig);
    final untilNext = PigService.timeToNextStage(widget.pig);
    final stageNames = {
      PigStage.piglet: 'Piglet',
      PigStage.grown: 'Grown',
      PigStage.chunky: 'Chunky',
    };
    final pig = widget.pig;
    final female = pig.gender == PigGender.female;
    final mood = _mood();

    return GlassContainer(
      solid: true,
      blur: 14,
      borderRadius: 34,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                height: 76,
                child: CustomPaint(
                  painter: _StagePigPainter(breed, stage),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(widget.pig.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GlassText.display(p, 20,
                                  weight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 7),
                        FaIcon(
                          female
                              ? FontAwesomeIcons.venus
                              : FontAwesomeIcons.mars,
                          size: 13,
                          color: female
                              ? const Color(0xFFE87BA4)
                              : const Color(0xFF6B96E0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(breed.name,
                            style: GlassText.body(p, 12.5,
                                weight: FontWeight.w700, color: p.textSecondary)),
                        const SizedBox(width: 6),
                        for (var i = 0; i < 5; i++)
                          Text(
                            i < breed.stars ? '★' : '☆',
                            style: TextStyle(
                              fontSize: 10,
                              color: i < breed.stars
                                  ? const Color(0xFFF7C948)
                                  : p.textSecondary.withValues(alpha: 0.4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(mood,
                        style: GlassText.body(p, 11.5,
                            weight: FontWeight.w600, color: p.textSecondary)),
                    Text(
                      pig.isPregnant
                          ? 'Expecting a litter · due ${_fmt(pig.dueAt!.difference(DateTime.now()))}'
                          : '${stageNames[stage]}'
                              '${untilNext == null ? ' · fully raised' : ' · next stage in ${_fmt(untilNext)}'}',
                      style: GlassText.body(p, 11.5, color: p.textSecondary),
                    ),
                    Text('Petted ${widget.pig.pets}×',
                        style: GlassText.body(p, 11.5, color: p.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Worth line — the whole point of waiting.
          GlassContainer(
            blur: 0,
            chrome: true,
            sheen: false,
            borderRadius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                const FaIcon(FontAwesomeIcons.coins,
                    size: 12, color: Color(0xFFE8A13C)),
                const SizedBox(width: 8),
                Text('Worth',
                    style: GlassText.body(p, 12.5, color: p.textSecondary)),
                const Spacer(),
                Text('$worth 🪙',
                    style: GlassText.body(p, 15,
                        weight: FontWeight.w700,
                        color: const Color(0xFFE8A13C))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Pressable(
                  pressedScale: 0.96,
                  onTap: () => _rename(),
                  child: GlassContainer(
                    blur: 0,
                    chrome: true,
                    sheen: false,
                    borderRadius: 20,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text('Rename',
                          style: GlassText.body(p, 13, weight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Pressable(
                  pressedScale: 0.96,
                  onTap: widget.profile.corn > 0 && !widget.pig.isPregnant
                      ? _feed
                      : null,
                  child: Material(
                    color: widget.profile.corn > 0 && !widget.pig.isPregnant
                        ? p.accent
                        : p.textSecondary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    elevation: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      child: Text(
                        'Feed 🌽×1',
                        style: GlassText.body(p, 13,
                            weight: FontWeight.w700,
                            color: p.isDark
                                ? const Color(0xFF0B1020)
                                : Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Pressable(
                  pressedScale: 0.96,
                  onTap: pig.isPregnant
                      ? null
                      : () => _matchMake(),
                  child: GlassContainer(
                    blur: 0,
                    chrome: true,
                    sheen: false,
                    borderRadius: 20,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        pig.isPregnant
                            ? 'Expecting 💕'
                            : female
                                ? 'Find a boar 💕'
                                : 'Find a sow 💕',
                        style: GlassText.body(p, 13, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Pressable(
                  pressedScale: 0.96,
                  onTap: pig.isPregnant ? null : () => _sell(worth),
                  child: Material(
                    color: pig.isPregnant
                        ? p.textSecondary.withValues(alpha: 0.25)
                        : p.accent,
                    borderRadius: BorderRadius.circular(20),
                    elevation: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      child: Text(
                        pig.isPregnant
                            ? 'Sell later 🪙'
                            : 'Sell for $worth 🪙',
                        style: GlassText.body(p, 13,
                            weight: FontWeight.w700,
                            color: p.isDark
                                ? const Color(0xFF0B1020)
                                : Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// One line on how the pig is doing, from fed + clean.
  String _mood() {
    final pig = widget.pig;
    final hunger = pig.hunger();
    final dirt = pig.dirt();
    if (hunger <= 0 && dirt > 65) return '😤 Starving and filthy';
    if (hunger <= 0) return '😤 Starving — growth paused';
    if (dirt > 65) return '💩 Needs a shower';
    if (hunger < 30 || dirt > 40) return '😋 Could use some care';
    if (pig.isPregnant) return '💕 Happy and expecting';
    return '✨ Content';
  }

  Future<void> _feed() async {
    if (!await widget.profile.spendCorn(1)) return;
    await widget.pigs.feed(widget.pig);
    if (mounted) setState(() {});
  }

  Future<void> _matchMake() async {
    final partner = await showModalBottomSheet<Pig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GlassScope(
        palette: GlassScope.of(context).palette,
        fontSize: 14.5,
        child: _PartnerPicker(sow: widget.pig, pigs: widget.pigs),
      ),
    );
    if (partner == null || !mounted) return;
    if (widget.pigs.breed(widget.pig, partner)) {
      HapticFeedback.mediumImpact();
      setState(() {});
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h >= 1) return '${h}h ${m}m';
    return '${m}m';
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: widget.pig.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassScope.of(context).palette.solidFill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Rename ${widget.pig.name}',
            style: GlassText.display(GlassScope.of(context).palette, 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 16,
          decoration: const InputDecoration(counterText: ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await widget.pigs.rename(widget.pig, name);
    }
    if (mounted) setState(() {});
  }

  Future<void> _sell(int worth) async {
    final p = GlassScope.of(context).palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassScope.of(context).palette.solidFill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Sell ${widget.pig.name}?',
            style: GlassText.display(GlassScope.of(context).palette, 17)),
        content: Text(
          '$worth coins land in your purse. The pen has room for a new pull.',
          style: GlassText.body(GlassScope.of(context).palette, 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Sell',
                style: GlassText.body(p, 14,
                    weight: FontWeight.w700, color: p.warn)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.pigs.sell(widget.pig);
    if (mounted) Navigator.of(context).pop();
  }
}

/// The matchmaking list: every pen-mate who qualifies for the sow.
/// Same rules as [PigService.canBreed] — opposite gender, raised past
/// piglet, not starving, nobody already expecting.
class _PartnerPicker extends StatelessWidget {
  final Pig sow;
  final PigService pigs;

  const _PartnerPicker({required this.sow, required this.pigs});

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    final matches = pigs.matchesFor(sow);
    return GlassContainer(
      solid: true,
      blur: 14,
      borderRadius: 34,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Choose a match',
                        style:
                            GlassText.display(p, 21, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('FOR ${sow.name.toUpperCase()}',
                        style: GlassText.eyebrow(p)),
                  ],
                ),
              ),
              GlassIconButton(
                icon: FontAwesomeIcons.xmark,
                size: 36,
                iconSize: 13,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Their piglet takes after one of the parents. Litters arrive '
            'about ${PigService.pregnancy.inHours} hours later.',
            style: GlassText.body(p, 12.5, height: 1.5, color: p.textSecondary),
          ),
          const SizedBox(height: 12),
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No matches yet. A boar must be a grown pig of the other '
                'gender, fed, and unattached.',
                style: GlassText.body(p, 12.5, color: p.textSecondary),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.34,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final match in matches)
                      Pressable(
                        onTap: () => Navigator.of(context).pop(match),
                        pressedScale: 0.97,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassContainer(
                            blur: 0,
                            chrome: true,
                            sheen: false,
                            borderRadius: 18,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 52,
                                  height: 46,
                                  child: CustomPaint(
                                    painter: _StagePigPainter(
                                      PigService.breedById(match.breedId),
                                      PigService.stageOf(match),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(match.name,
                                          style: GlassText.body(p, 14,
                                              weight: FontWeight.w700)),
                                      Text(
                                        '${PigService.breedById(match.breedId).name}'
                                        ' · ${PigService.stageOf(match) == PigStage.chunky ? 'Chunky' : 'Grown'}',
                                        style: GlassText.body(p, 11,
                                            color: p.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                FaIcon(
                                  match.gender == PigGender.female
                                      ? FontAwesomeIcons.venus
                                      : FontAwesomeIcons.mars,
                                  size: 13,
                                  color: match.gender == PigGender.female
                                      ? const Color(0xFFE87BA4)
                                      : const Color(0xFF6B96E0),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A static pig in its growth stage, for the profile card.
class _StagePigPainter extends CustomPainter {
  final PigBreed breed;
  final PigStage stage;

  _StagePigPainter(this.breed, this.stage);

  @override
  void paint(Canvas canvas, Size size) {
    final stageScale = switch (stage) {
      PigStage.piglet => 0.72,
      PigStage.grown => 1.0,
      PigStage.chunky => 1.22,
    };
    final chub = switch (stage) {
      PigStage.piglet => 0.0,
      PigStage.grown => 0.4,
      PigStage.chunky => 1.0,
    };
    canvas.translate(size.width / 2, size.height - 6);
    canvas.scale(0.66 * stageScale);
    PigArt.paint(
      canvas,
      breed,
      PigPose(t: 1.25, chub: chub, blink: true),
    );
  }

  @override
  bool shouldRepaint(_StagePigPainter old) =>
      old.breed != breed || old.stage != stage;
}
