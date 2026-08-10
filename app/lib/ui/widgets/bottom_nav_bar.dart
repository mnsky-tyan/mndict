import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'glass_container.dart';

class GlassBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const GlassBottomNavBar({
    super.key,
    this.currentIndex = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      height: 70,
      borderRadius: 25,
      child: Row(
        children: [
          Expanded(child: _buildNavItem(FontAwesomeIcons.magnifyingGlass, 'Search', 0)),
          Expanded(child: _buildNavItem(FontAwesomeIcons.bookOpen, 'Vocabulary', 1)),
          Expanded(child: _buildNavItem(FontAwesomeIcons.graduationCap, 'Test', 2)),
          Expanded(child: _buildNavItem(FontAwesomeIcons.house, 'Home', 3)),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isActive = index == currentIndex;
    final color = isActive ? const Color(0xFF4FACFE) : const Color(0xFF64748B);

    // Shift Vocabulary (1) and Test (2) slightly to the right
    double xOffset = 0;
    if (index == 1 || index == 2) {
      xOffset = 5.0; // Reduced shift
    }

    return GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        color: Colors.transparent, // Hit test target
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Transform.translate(
          offset: Offset(xOffset, 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(
                icon,
                color: color,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
