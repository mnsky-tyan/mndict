import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/ui/glass_dictionary_app.dart';
import 'package:app/ui/widgets/glass_page.dart' show GlassIconButton;
import 'package:app/ui/widgets/search_bar.dart';
import 'package:app/ui/widgets/definition_card.dart';
import 'package:app/ui/widgets/bottom_nav_bar.dart';
import 'package:app/ui/widgets/side_menu.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('GlassDictionaryApp renders all main components', (WidgetTester tester) async {
    // Don't fetch fonts over the network in tests; fall back silently.
    GoogleFonts.config.allowRuntimeFetching = false;

    // Mock SharedPreferences
    SharedPreferences.setMockInitialValues({});

    // Mock path_provider so DictionaryService can check for a model file.
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => '/tmp');

    // Build our app and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: GlassDictionaryApp()));

    // Let async init settle. The aurora background animates forever, so we
    // pump a few fixed frames instead of pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // Verify that the main components are present.
    expect(find.byType(GlassSearchBar), findsOneWidget);
    // With no lookup yet, the aurora-orb hint stands in for the card.
    expect(find.byType(DefinitionCard), findsNothing);
    expect(find.text('Look up any word'), findsOneWidget);
    expect(find.byType(GlassBottomNavBar), findsOneWidget);

    // Verify Bottom Nav Labels
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Vocabulary'), findsOneWidget);

    // The menu button must open the scale-reveal drawer.
    await tester.tap(find.byType(GlassIconButton).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SideMenu), findsOneWidget);
  });

  testWidgets('switching tabs fades to the new page content', (WidgetTester tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => '/tmp');

    await tester.pumpWidget(const MaterialApp(home: GlassDictionaryApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // Tap the Home tab (non-adjacent switch) via the nav bar and let the
    // fade-through play.
    await tester.tap(find.descendant(
      of: find.byType(GlassBottomNavBar),
      matching: find.text('Home'),
    ));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 700));

    // The home page hero must be visible after the switch.
    expect(find.text('Your library'), findsOneWidget);

    // The search field is Search-tab-only: on Home the top bar shows the
    // tab title instead (nav label + top-bar title both say 'Home').
    expect(find.byType(GlassSearchBar), findsNothing);
    expect(find.text('Home'), findsNWidgets(2));

    // Back to Search: the field returns.
    await tester.tap(find.descendant(
      of: find.byType(GlassBottomNavBar),
      matching: find.text('Search'),
    ));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GlassSearchBar), findsOneWidget);
  });

  testWidgets('dragging the page area scrubs to the neighboring tab', (WidgetTester tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => '/tmp');

    await tester.pumpWidget(const MaterialApp(home: GlassDictionaryApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // Swipe left across the page area: Search -> Vocabulary. The hint
    // leaves, the vocabulary (empty-state) page arrives — all scrubbed by
    // the drag, not replayed after it. timedDrag keeps the fling velocity
    // finite and modest so the settle lands on page 1.
    await tester.timedDragFrom(
      const Offset(300, 400),
      const Offset(-400, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('No saved words yet'), findsOneWidget);
    // The heading followed the page: the vocabulary title is mounted on top
    // of the nav label, the search field is gone.
    expect(find.text('Vocabulary'), findsNWidgets(2));
    expect(find.byType(GlassSearchBar), findsNothing);
  });
}
