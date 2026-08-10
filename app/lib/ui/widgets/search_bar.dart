import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'glass_container.dart';

class GlassSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final Function(String)? onSubmitted;
  final bool enabled;

  const GlassSearchBar({
    super.key,
    this.controller,
    this.onSubmitted,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      height: 50, // Reduced height
      padding: const EdgeInsets.only(left: 10, right: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center, // Ensure vertical center
        children: [
          IconButton(
            icon: const FaIcon(
              FontAwesomeIcons.magnifyingGlass,
              color: Color(0xFF64748B), // text-light
              size: 18, // Slightly smaller icon
            ),
            onPressed: () {
              if (onSubmitted != null && controller != null) {
                onSubmitted!(controller!.text);
              }
            },
          ),
          const SizedBox(width: 15),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              onSubmitted: onSubmitted,
              textAlignVertical: TextAlignVertical.center, // Center text vertically
              style: GoogleFonts.outfit(
                color: const Color(0xFF1E293B), // text-dark
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true, // Removes default padding
                contentPadding: const EdgeInsets.symmetric(vertical: 10), // Center content
                hintText: 'Search for a word...',
                hintStyle: GoogleFonts.outfit(
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
