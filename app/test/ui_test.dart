import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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
    // Mock flutter_secure_storage: reads answer null (no stored key),
    // so lookups exercise the no-key gate. A real call would never
    // complete inside the fake-async test clock.
    const secureChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async => null);

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

  testWidgets('the farm opens as its own full-screen mode and exits via its door', (WidgetTester tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => '/tmp');
    // Mock flutter_secure_storage: reads answer null (no stored key),
    // so lookups exercise the no-key gate. A real call would never
    // complete inside the fake-async test clock.
    const secureChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async => null);

    await tester.pumpWidget(const MaterialApp(home: GlassDictionaryApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // Tap the Farm launch pad in the nav bar. It is not a tab: the farm
    // pushes over the whole shell with an app-launch transition. The farm
    // animates forever, so fixed pumps, never pumpAndSettle.
    await tester.tap(find.descendant(
      of: find.byType(GlassBottomNavBar),
      matching: find.text('Farm'),
    ));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 700));

    // First run gifts the Truffle starter, so the pen already holds 1/12.
    expect(find.text('Pig Market'), findsOneWidget);
    expect(find.text('My Farm'), findsOneWidget);
    expect(find.text('Your farm is waiting'), findsNothing);
    expect(find.text('1/12'), findsOneWidget);

    // Farm mode covers the dictionary — no search field, no nav bar. The
    // way out is the door button in the farm's pill row.
    expect(find.byType(GlassSearchBar), findsNothing);
    expect(find.byType(GlassBottomNavBar), findsNothing);
    expect(find.byIcon(FontAwesomeIcons.doorOpen), findsOneWidget);

    // Leave through the door: back to the dictionary, bars and all.
    await tester.tap(find.byIcon(FontAwesomeIcons.doorOpen));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GlassSearchBar), findsOneWidget);
    expect(find.byType(GlassBottomNavBar), findsOneWidget);
  });

  testWidgets('dragging the page area scrubs to the neighboring tab', (WidgetTester tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => '/tmp');
    // Mock flutter_secure_storage: reads answer null (no stored key),
    // so lookups exercise the no-key gate. A real call would never
    // complete inside the fake-async test clock.
    const secureChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async => null);

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

  testWidgets('submitting a search without a model surfaces the error card', (WidgetTester tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => '/tmp');
    // Mock flutter_secure_storage: reads answer null (no stored key),
    // so lookups exercise the no-key gate. A real call would never
    // complete inside the fake-async test clock.
    const secureChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async => null);

    await tester.pumpWidget(const MaterialApp(home: GlassDictionaryApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // No model file exists in the mocked '/tmp', so the service reports
    // "not loaded" and searchWord must forward the error to the UI card.
    await tester.enterText(find.byType(TextField), 'test');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(DefinitionCard), findsOneWidget);
    expect(find.text('test'), findsWidgets); // the entry-word title
  });
}
