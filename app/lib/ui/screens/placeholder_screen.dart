import 'package:flutter/material.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/glass_page.dart';

class PlaceholderScreen extends StatelessWidget {
  final String title;

  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: title,
      child: Center(
        child: GlassContainer(
          blur: 0,
          borderRadius: 24,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Coming soon',
                  style: GlassText.display(GlassPalette.light, 17)),
              const SizedBox(height: 6),
              Text(
                'This section isn\u2019t built yet.',
                style: GlassText.body(GlassPalette.light, 13,
                    color: GlassPalette.light.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
