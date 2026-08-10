import 'package:flutter_test/flutter_test.dart';
import 'package:app/ui/glass_dictionary_app.dart';
import 'package:app/ui/widgets/search_bar.dart';
import 'package:app/ui/widgets/definition_card.dart';
import 'package:app/ui/widgets/bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('GlassDictionaryApp renders all main components', (WidgetTester tester) async {
    // Mock SharedPreferences
    SharedPreferences.setMockInitialValues({});

    // Build our app and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: GlassDictionaryApp()));
    
    // Allow FutureBuilder/Init to complete
    await tester.pumpAndSettle();

    // Verify that the main components are present.
    expect(find.byType(GlassSearchBar), findsOneWidget);
    // DefinitionCard might be hidden or empty initially, but the widget is in the tree
    expect(find.byType(DefinitionCard), findsOneWidget);
    expect(find.byType(GlassBottomNavBar), findsOneWidget);

    // Verify Bottom Nav Labels
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Vocabulary'), findsOneWidget);
  });
}
