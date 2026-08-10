import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'glass_container.dart';

class DefinitionCard extends StatelessWidget {
  final String? content;
  final bool isLoading;
  final bool isSaved;
  final VoidCallback? onSave;
  final String? title;

  const DefinitionCard({
    super.key,
    this.content,
    this.isLoading = false,
    this.isSaved = false,
    this.onSave,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return GlassContainer(
        borderRadius: 30,
        padding: const EdgeInsets.all(30),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (content == null || content!.isEmpty) {
      return const SizedBox.shrink();
    }

    return GlassContainer(
      borderRadius: 30,
      padding: const EdgeInsets.all(30),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with Save Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title ?? "Definition",
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
                IconButton(
                  icon: FaIcon(
                    isSaved ? FontAwesomeIcons.solidHeart : FontAwesomeIcons.heart,
                    color: isSaved ? Colors.red : const Color(0xFF64748B),
                  ),
                  onPressed: onSave,
                ),
              ],
            ),
            const SizedBox(height: 15),
            const SizedBox(height: 15),
            MarkdownBody(
              data: content!,
              styleSheet: MarkdownStyleSheet(
                p: GoogleFonts.outfit(
                  fontSize: 16,
                  height: 1.5,
                  color: const Color(0xFF1E293B),
                ),
                strong: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
