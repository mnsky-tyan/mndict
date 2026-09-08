// Design-preview renderer — not a test gate.
// Regenerates app/build/design_previews/*.png for human review.
//
//   RENDER_PREVIEWS=1 flutter test test/design_preview_test.dart
//
// Skipped unless RENDER_PREVIEWS is set, so the normal `flutter test` run
// ignores it.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/services/app_settings.dart';
import 'package:app/services/farm_profile.dart';
import 'package:app/services/pig_service.dart';
import 'package:app/services/worlds.dart';
import 'package:app/ui/screens/farm_view.dart';
import 'package:app/ui/theme/glass_theme.dart';
import 'package:app/ui/widgets/pig_painter.dart';
import 'package:app/ui/widgets/pig_shop.dart';
import 'package:app/ui/widgets/world_themes.dart';

/// The app's fonts (Google Fonts) download at runtime, which widget tests
/// can't do — register lookalike/actual fonts under the same family names
/// so preview text renders as glyphs instead of Ahem blocks. Engine font
/// registration needs the real event loop, hence [tester.runAsync], and it
/// only becomes effective after the process's first frame batch, so the
/// first test in this file is a discarded warm-up.
bool _fontsLoaded = false;

Future<void> _loadSystemFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await tester.runAsync(() async {
    final registrations = <(String, String)>[
      ('Inter', 'C:/Windows/Fonts/arial.ttf'),
      ('Literata', 'C:/Windows/Fonts/georgia.ttf'),
      ('Segoe UI Symbol', 'C:/Windows/Fonts/seguisym.ttf'), // ★ in labels
    ];
    final pubCache = Directory(
        '${Platform.environment['LOCALAPPDATA']}/Pub/Cache/hosted/pub.dev');
    if (pubCache.existsSync()) {
      for (final dir in pubCache.listSync()) {
        if (dir.path.contains('font_awesome_flutter-')) {
          registrations.add((
            'FontAwesomeSolid',
            '$dir/lib/fonts/Font-Awesome-7-Free-Solid-900.otf',
          ));
        }
      }
    }
    for (final (family, path) in registrations) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
    // The engine applies the registration asynchronously after the reply;
    // give it real time to land before the next pumped frame.
    await Future<void>.delayed(const Duration(milliseconds: 700));
  });
  _fontsLoaded = true;
}

Future<(AppSettings, PigService, FarmProfile)> _seed(
    List<String> breedIds) async {
  SharedPreferences.setMockInitialValues({});
  final settings = AppSettings();
  await settings.init();
  await settings.addCoins(1000);
  final pigs = PigService(settings);
  await pigs.init();
  for (final id in breedIds) {
    await pigs.adoptDirect(id);
  }
  final profile = FarmProfile(settings, pigs);
  await profile.init();
  // A stocked basket and a couple of yard props, so previews show the
  // care facilities in their lived-in state.
  await profile.addCorn(6);
  profile.placeDecor('pumpkin');
  profile.placeDecor('ball');
  return (settings, pigs, profile);
}

Future<void> _snap(WidgetTester tester, Key key, String name) async {
  // Advance the scene's simulated time past the spawn drop. The scene
  // clamps dt at 50 ms per tick, so pump in matching steps.
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await _snapNow(tester, key, name);
}

Future<void> _snapNow(WidgetTester tester, Key key, String name) async {
  // Rasterization and file I/O are real async — escape the fake zone.
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/design_previews').createSync(recursive: true);
    File('build/design_previews/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  final renderEnabled = Platform.environment['RENDER_PREVIEWS'] == '1';

  /// Discarded: text painted by the first farm-pumping test always rasterizes
  /// with the fallback font (registration lands only between tests), so burn
  /// one farm here — every later farm renders its pill text correctly.
  testWidgets('farm warm-up', skip: !renderEnabled, (tester) async {
    await _loadSystemFonts(tester);
    await _loadSystemFonts(tester);
    final (settings, pigs, profile) = await _seed(['truffle']);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GlassScope(
          palette: GlassPalette.light,
          fontSize: 16,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: FarmView(
                settings: settings,
                pigs: pigs,
                profile: profile,
                wordCount: 1,
                onExit: () {}),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('farm day scene preview', skip: !renderEnabled, (tester) async {
    await _loadSystemFonts(tester);
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (settings, pigs, profile) = await _seed(
        ['truffle', 'butterscotch', 'blueberry', 'ember', 'halo']);
    const key = Key('snap');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GlassScope(
          palette: GlassPalette.light,
          fontSize: 16,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: GlassPalette.light.bgTop,
                child: FarmView(
                    settings: settings,
                    pigs: pigs,
                    profile: profile,
                    wordCount: 12,
                    onExit: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    await _snap(tester, key, 'farm_day');
  });

  testWidgets('farm night scene preview', skip: !renderEnabled, (tester) async {
    await _loadSystemFonts(tester);
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (settings, pigs, profile) = await _seed(
        ['matcha', 'frosty', 'midnight', 'sol', 'truffle']);
    const key = Key('snap');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GlassScope(
          palette: GlassPalette.dark,
          fontSize: 16,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: GlassPalette.dark.bgTop,
                child: FarmView(
                    settings: settings,
                    pigs: pigs,
                    profile: profile,
                    wordCount: 12,
                    onExit: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    await _snap(tester, key, 'farm_night');
  });

  testWidgets('pig market reveal preview', skip: !renderEnabled,
      (tester) async {
    await _loadSystemFonts(tester);
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (settings, pigs, profile) = await _seed(['truffle']);
    const key = Key('snap');
    await tester.pumpWidget(
      MaterialApp(
        // The boundary wraps the Navigator so the modal sheet is captured.
        builder: (context, child) => RepaintBoundary(
          key: key,
          child: GlassScope(
            palette: GlassPalette.light,
            fontSize: 16,
            child: child!,
          ),
        ),
        home: FarmView(
            settings: settings, pigs: pigs, profile: profile, wordCount: 1),
      ),
    );
    // Small pump steps: a route pushed between pumps only registers its
    // ticker on the next frame, so big single pumps leave it at value 0.
    Future<void> settle(int steps, {int ms = 100}) async {
      for (var i = 0; i < steps; i++) {
        await tester.pump(Duration(milliseconds: ms));
      }
    }

    await settle(2);

    showPigMarket(
        tester.element(find.byType(FarmView)), settings, pigs, profile);
    await settle(4); // sheet entrance (~250 ms) done

    // Pull: tap the crate itself (the button sits in a scroll view),
    // ride out the crate wobble (~1.25 s timer), let the pop settle.
    await tester.tapAt(const Offset(215, 660));
    await settle(3, ms: 60); // pull resolves, wobble starts
    await settle(14); // wobble timer fires -> reveal + pop start
    await settle(6); // pop completes

    await _snapNow(tester, key, 'pig_market_reveal');
    await settle(20);
    await _snapNow(tester, key, 'pig_market_after');

    // Decor tab shelf.
    await tester.tap(find.text('Decor'));
    await settle(3, ms: 60);
    await _snapNow(tester, key, 'pig_market_decor');

    // Buy the toadstool so the shelf shows a fresh purchase, then the
    // Feed tab with a topped-up basket.
    await tester.tap(find.text('10 🪙'));
    await settle(3, ms: 60);
    await tester.tap(find.text('Feed'));
    await settle(3, ms: 60);
    await tester.tap(find.text('+5 🌽 · 15 🪙'));
    await settle(3, ms: 60);
    await _snapNow(tester, key, 'pig_market_feed');
  });

  testWidgets('pig profile preview', skip: !renderEnabled, (tester) async {
    await _loadSystemFonts(tester);
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (settings, pigs, profile) = await _seed(['truffle']);
    const key = Key('snap');
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => RepaintBoundary(
          key: key,
          child: GlassScope(
            palette: GlassPalette.light,
            fontSize: 16,
            child: child!,
          ),
        ),
        home: FarmView(
            settings: settings, pigs: pigs, profile: profile, wordCount: 12),
      ),
    );
    Future<void> settle(int steps, {int ms = 100}) async {
      for (var i = 0; i < steps; i++) {
        await tester.pump(Duration(milliseconds: ms));
      }
    }

    await settle(2);
    final pig = pigs.pigs.first;
    showPigProfile(tester.element(find.byType(FarmView)), pigs, profile, pig);
    await settle(4);

    await _snapNow(tester, key, 'pig_profile');
  });

  testWidgets('breed sheet preview', skip: !renderEnabled, (tester) async {
    await _loadSystemFonts(tester);
    tester.view.physicalSize = const Size(1300, 2450);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const key = Key('snap');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GlassScope(
          palette: GlassPalette.light,
          fontSize: 16,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: const Color(0xFFF4F6FD),
                padding: const EdgeInsets.all(14),
                child: GridView.count(
                  crossAxisCount: 5,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.15,
                  children: [
                    for (final (i, breed) in PigService.breeds.indexed)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0x1A17203D)),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Expanded(
                              child: CustomPaint(
                                painter: _BreedPreview(
                                  breed,
                                  pose: PigPose(
                                    t: 0.6,
                                    walk: i % 7 == 3 ? 0.3 : -1,
                                    sleeping: i == 5, // one common naps
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              '${breed.name} ${'★' * breed.stars}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: ['Segoe UI Symbol'],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF17203D)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _snap(tester, key, 'breeds');
  });

  testWidgets('worlds preview', skip: !renderEnabled, (tester) async {
    await _loadSystemFonts(tester);
    tester.view.physicalSize = const Size(880, 1560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const key = Key('snap');

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GlassScope(
          palette: GlassPalette.light,
          fontSize: 16,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: const Color(0xFFF4F6FD),
                padding: const EdgeInsets.all(10),
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.58,
                  children: [
                    for (final id in WorldId.values)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: CustomPaint(
                          painter: _WorldPreview(id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _snap(tester, key, 'worlds');
  });

  testWidgets('growth stages preview', skip: !renderEnabled, (tester) async {
    await _loadSystemFonts(tester);
    tester.view.physicalSize = const Size(1100, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const key = Key('snap');
    const showcase = [
      'truffle', 'pineapple', 'bee', 'firebird', 'royal', 'prism',
    ];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GlassScope(
          palette: GlassPalette.light,
          fontSize: 16,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: const Color(0xFFF4F6FD),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    for (final id in showcase)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0x1A17203D)),
                          ),
                          child: CustomPaint(
                            painter: _StageStrip(PigService.breedById(id)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _snap(tester, key, 'stages');
  });
}

/// Draws one pig with its feet near the card's bottom edge.
class _BreedPreview extends CustomPainter {
  final PigBreed breed;
  final PigPose pose;

  _BreedPreview(this.breed, {required this.pose});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height - 6);
    PigArt.paint(canvas, breed, pose);
  }

  @override
  bool shouldRepaint(covariant _BreedPreview oldDelegate) =>
      oldDelegate.breed != breed || oldDelegate.pose != pose;
}

/// Piglet / grown / chunky side by side, feet on one baseline.
class _StageStrip extends CustomPainter {
  final PigBreed breed;

  _StageStrip(this.breed);

  @override
  void paint(Canvas canvas, Size size) {
    const chubs = [0.0, 0.4, 1.0];
    for (var i = 0; i < chubs.length; i++) {
      canvas.save();
      canvas.translate(size.width * (0.17 + 0.33 * i), size.height - 16);
      canvas.scale(0.78);
      PigArt.paint(
        canvas,
        breed,
        PigPose(t: 0.6, chub: chubs[i]),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _StageStrip oldDelegate) =>
      oldDelegate.breed != breed;
}

/// One world backdrop with a few pigs grazing, so scale and mood read.
class _WorldPreview extends CustomPainter {
  final WorldId id;

  _WorldPreview(this.id);

  @override
  void paint(Canvas canvas, Size size) {
    WorldBackdrop.paint(canvas, size, id,
        phase: SkyPhase.day, night: false, level: 13, t: 0.6);
    const herd = [
      ('truffle', 0.28, 0.62, 0.9),
      ('buccaneer', 0.62, 0.72, 1.05),
      ('leviathan', 0.80, 0.50, 0.8),
    ];
    for (final (breedId, x, y, s) in herd) {
      canvas.save();
      canvas.translate(size.width * x, size.height * y);
      canvas.scale(s);
      PigArt.paint(
        canvas,
        PigService.breedById(breedId),
        const PigPose(t: 0.6),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _WorldPreview oldDelegate) =>
      oldDelegate.id != id;
}
