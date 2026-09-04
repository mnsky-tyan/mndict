import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'ui/glass_dictionary_app.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mndict',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D6BFF)),
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(),
        scaffoldBackgroundColor: const Color(0xFFEDF1FB),
      ),
      home: const GlassDictionaryApp(),
    );
  }
}
