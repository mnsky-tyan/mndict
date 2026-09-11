import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/glass_theme.dart';
import 'blocked_image.dart';
import 'glass_container.dart';
import 'glass_page.dart';

/// iOS-style floating bottom sheet with a grab handle.
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
    final p = GlassScope.of(context).palette;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 46 * (1 - t)),
          child: child,
        ),
      ),
      child: GlassContainer(
        borderRadius: 32,
        blur: 18,
        reading: true,
        rim: true,
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grab handle
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: p.textSecondary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    word,
                    style: GlassText.reading(p, 24,
                        weight: FontWeight.w700, tracking: -0.2, height: 1.15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                GlassIconButton(
                  icon: FontAwesomeIcons.rotate,
                  iconSize: 13,
                  size: 38,
                  iconColor: p.textSecondary,
                  onTap: onRefresh,
                ),
                const SizedBox(width: 6),
                GlassIconButton(
                  icon: FontAwesomeIcons.trash,
                  iconSize: 13,
                  size: 38,
                  iconColor: p.danger,
                  onTap: onDelete,
                ),
                const SizedBox(width: 6),
                GlassIconButton(
                  icon: FontAwesomeIcons.xmark,
                  iconSize: 15,
                  size: 38,
                  onTap: onClose,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(height: 1, color: p.hairline),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 4),
                child: MarkdownBody(
                  data: definition,
                  softLineBreak: true,
                  builders: {
                    'img': BlockedImageBuilder(p),
                  },
                  styleSheet: MarkdownStyleSheet(
                    p: GlassText.reading(p, 13.5,
                        height: 1.7,
                        tracking: 0.1,
                        color: p.textPrimary.withValues(alpha: 0.90)),
                    strong: GlassText.reading(p, 13.5,
                        weight: FontWeight.w700,
                        height: 1.7,
                        tracking: 0.1,
                        color: p.textPrimary.withValues(alpha: 0.90)),
                    em: GlassText.reading(p, 13.5,
                        height: 1.7,
                        color: p.textSecondary,
                        fontStyle: FontStyle.italic),
                    h1: GlassText.reading(p, 18.5,
                        weight: FontWeight.w700, height: 1.3),
                    h2: GlassText.reading(p, 17,
                        weight: FontWeight.w700, height: 1.3),
                    h3: GlassText.reading(p, 15.5,
                        weight: FontWeight.w600, height: 1.3),
                    listBullet: GlassText.reading(p, 13.5,
                        height: 1.7,
                        tracking: 0.1,
                        color: p.textPrimary.withValues(alpha: 0.90)),
                    blockSpacing: 12,
                    listIndent: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
