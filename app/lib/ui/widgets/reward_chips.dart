import 'package:flutter/material.dart';
import '../../services/farm_profile.dart';
import '../theme/glass_theme.dart';
import 'glass_container.dart';

/// The one route observer the app's [MaterialApp] must carry in
/// [navigatorObservers]. [RewardChips] subscribes through it so a chip
/// overlay that was covered by another route re-drains the reward queue
/// the moment it becomes visible again.
final RouteObserver<ModalRoute<void>> kRewardRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// Floating reward crumbs — "+1 🪙 +4 XP", quests, level-ups, badges —
/// dropping in wherever they were earned. The dictionary shell and the
/// farm each mount one; the queue in [FarmProfile] is drained only by the
/// overlay whose route is currently on top, so the hidden one never
/// steals the visible one's rewards.
class RewardChips extends StatefulWidget {
  final FarmProfile profile;

  const RewardChips({super.key, required this.profile});

  @override
  State<RewardChips> createState() => _RewardChipsState();
}

class _RewardChipsState extends State<RewardChips> with RouteAware {
  final List<_ChipData> _chips = [];
  var _nextId = 1;

  @override
  void initState() {
    super.initState();
    widget.profile.addListener(_drain);
    // _drain reads ModalRoute.of, which isn't legal inside initState —
    // and the queue is empty at mount anyway. Flush on the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _drain();
    });
  }

  @override
  void didUpdateWidget(RewardChips old) {
    super.didUpdateWidget(old);
    if (old.profile != widget.profile) {
      old.profile.removeListener(_drain);
      widget.profile.addListener(_drain);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      kRewardRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    // Back on top (a pushed farm or sheet just closed): flush anything
    // that queued while this overlay was covered.
    _drain();
  }

  @override
  void dispose() {
    kRewardRouteObserver.unsubscribe(this);
    widget.profile.removeListener(_drain);
    super.dispose();
  }

  void _drain() {
    // Covered by another route — leave the rewards queued for whoever
    // is actually on screen.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final rewards = widget.profile.takeRewards();
    if (rewards.isEmpty || !mounted) return;
    setState(() {
      for (final r in rewards) {
        final chip = _ChipData(_nextId++, r.label, r.celebrate);
        _chips.add(chip);
        // Each crumb lives briefly, then fades itself out.
        Future.delayed(
          Duration(milliseconds: r.celebrate ? 3200 : 1900),
          () {
            if (!mounted) return;
            setState(() => _chips.removeWhere((c) => c.id == chip.id));
          },
        );
      }
      // Never let a burst bury the screen.
      while (_chips.length > 4) {
        _chips.removeAt(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_chips.isEmpty) return const SizedBox.shrink();
    final p = GlassScope.of(context).palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final chip in _chips)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: TweenAnimationBuilder<double>(
              key: ValueKey(chip.id),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              builder: (context, t, child) => Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
              ),
              child: GlassContainer(
                blur: 0,
                chrome: !chip.celebrate,
                solid: chip.celebrate,
                sheen: false,
                borderRadius: 999,
                padding: EdgeInsets.symmetric(
                    horizontal: 14, vertical: chip.celebrate ? 9 : 6),
                child: Text(
                  chip.label,
                  style: GlassText.body(
                    p,
                    chip.celebrate ? 13 : 12,
                    weight: FontWeight.w700,
                    color: chip.celebrate
                        ? (p.isDark
                            ? const Color(0xFF0B1020)
                            : Colors.white)
                        : p.textPrimary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChipData {
  final int id;
  final String label;
  final bool celebrate;
  _ChipData(this.id, this.label, this.celebrate);
}
