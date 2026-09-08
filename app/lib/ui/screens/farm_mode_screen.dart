import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/app_settings.dart';
import '../../services/farm_profile.dart';
import '../../services/pig_service.dart';
import '../theme/glass_theme.dart';
import '../widgets/reward_chips.dart';
import 'farm_view.dart';

/// The farm as its own app. Pushed full-screen over the dictionary — no
/// top bar, no bottom nav, no aurora: just the farm's own sky and chrome.
/// Left via the in-world door button (or the system back gesture).
class FarmModeScreen extends StatelessWidget {
  final AppSettings settings;
  final PigService pigs;
  final FarmProfile profile;
  final int wordCount;

  const FarmModeScreen({
    super.key,
    required this.settings,
    required this.pigs,
    required this.profile,
    required this.wordCount,
  });

  /// An app-launch transition: the dictionary sinks back while the farm
  /// rises to meet it. Opaque, so the shell below stops painting/ticking.
  static Route<void> route({
    required AppSettings settings,
    required PigService pigs,
    required FarmProfile profile,
    required int wordCount,
  }) {
    return PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 460),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => FarmModeScreen(
        settings: settings,
        pigs: pigs,
        profile: profile,
        wordCount: wordCount,
      ),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: Tween<double>(begin: 0, end: 1).animate(curved),
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.05), end: Offset.zero)
                .animate(curved),
            child: ScaleTransition(
              scale: Tween(begin: 1.06, end: 1.0).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = settings.isDarkMode ? GlassPalette.dark : GlassPalette.light;
    return GlassScope(
      palette: p,
      fontSize: settings.fontSize,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              p.isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: p.isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              p.isDark ? Brightness.light : Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: p.bgTop,
          body: Stack(
            children: [
              Positioned.fill(
                child: FarmView(
                  settings: settings,
                  pigs: pigs,
                  profile: profile,
                  wordCount: wordCount,
                  onExit: () => Navigator.of(context).pop(),
                ),
              ),
              // Farm-earned crumbs (pulls, quests, level-ups) drop under
              // the pill row and the name plate.
              Positioned(
                top: MediaQuery.of(context).padding.top + 96,
                left: 0,
                right: 0,
                child: IgnorePointer(child: RewardChips(profile: profile)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
