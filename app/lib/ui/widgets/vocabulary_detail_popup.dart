import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'glass_container.dart';

class VocabularyDetailPopup extends StatelessWidget {
  final String word;
  final String definition;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;

  const VocabularyDetailPopup({
    super.key,
    required this.word,
    required this.definition,
    required this.onClose,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 30,
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Word + Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  word,
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.rotate, size: 20, color: Color(0xFF64748B)),
                    onPressed: onRefresh,
                    tooltip: 'Refresh Definition',
                  ),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.trash, size: 20, color: Colors.redAccent),
                    onPressed: onDelete,
                    tooltip: 'Delete Word',
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.xmark, size: 24, color: Color(0xFF1E293B)),
                    onPressed: onClose,
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Definition Content
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                definition,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  height: 1.5,
                  color: const Color(0xFF334155),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
