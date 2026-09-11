import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/glass_theme.dart';

/// Markdown `img` builder that renders a static placeholder instead of
/// letting flutter_markdown fetch the URL over the network — a hostile
/// definition must not be able to make the app phone home.
class BlockedImageBuilder extends MarkdownElementBuilder {
  final GlassPalette palette;

  BlockedImageBuilder(this.palette);

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: palette.textSecondary.withValues(alpha: 0.07),
        border: Border.all(color: palette.hairline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            FontAwesomeIcons.image,
            size: 11,
            color: palette.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            'image blocked',
            style: GlassText.body(palette, 11.5, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
