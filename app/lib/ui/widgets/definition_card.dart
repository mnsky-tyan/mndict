import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/glass_theme.dart';
import 'aurora_orb.dart';
import 'blocked_image.dart';
import 'glass_container.dart';
import 'pressable.dart';

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
    final scope = GlassScope.of(context);
    final p = scope.palette;
    // Reading size sits ~2pt under the UI font size — Literata's large
    // x-height reads a size bigger than Inter at the same nominal pt.
    final bodySize = (scope.fontSize - 2.0).clamp(11.0, 30.0);
    // Softened ink for long-form reading; pure primary gray is too stiff
    // against the translucent aurora fill.
    final ink = p.textPrimary.withValues(alpha: 0.90);
    final streaming = isLoading && content != null && content!.isNotEmpty;

    // Empty: nothing to show.
    if ((content == null || content!.isEmpty) && !isLoading) {
      return const SizedBox.shrink();
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - t)),
          child: child,
        ),
      ),
      child: GlassContainer(
        borderRadius: 30,
        reading: true,
        rim: true,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
        child: isLoading && (content == null || content!.isEmpty)
            ? _LoadingState(palette: p, title: title)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DICTIONARY',
                              style: GlassText.eyebrow(p)
                                  .copyWith(fontSize: 10, letterSpacing: 2),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              title ?? 'Definition',
                              // Dictionary-head style: the entry word is
                              // serif, like a printed dictionary.
                              style: GlassText.reading(p, 23,
                                  weight: FontWeight.w700,
                                  tracking: -0.2, height: 1.15),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _SaveButton(
                        palette: p,
                        isSaved: isSaved,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          onSave?.call();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  // While tokens stream in, the divider is a live pulse.
                  streaming
                      ? const _LiveLine()
                      : Container(height: 1, color: p.hairline),
                  const SizedBox(height: 13),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: MarkdownBody(
                        data: content!,
                        softLineBreak: true,
                        builders: {
                          'img': BlockedImageBuilder(p),
                        },
                        styleSheet: MarkdownStyleSheet(
                          p: GlassText.reading(p, bodySize,
                              height: 1.7,
                              tracking: 0.1, color: ink),
                          strong: GlassText.reading(
                            p,
                            bodySize,
                            weight: FontWeight.w700,
                            height: 1.7,
                            tracking: 0.1,
                            color: ink,
                          ),
                          em: GlassText.reading(
                            p,
                            bodySize,
                            height: 1.7,
                            color: p.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                          // Serif headings keep the whole entry in the
                          // bookish reading voice — mixing the sans UI
                          // face in here is what read as "stiff".
                          h1: GlassText.reading(p, bodySize + 5,
                              weight: FontWeight.w700, height: 1.3),
                          h2: GlassText.reading(p, bodySize + 3.5,
                              weight: FontWeight.w700, height: 1.3),
                          h3: GlassText.reading(p, bodySize + 2,
                              weight: FontWeight.w600, height: 1.3),
                          listBullet: GlassText.reading(
                            p,
                            bodySize,
                            height: 1.7,
                            tracking: 0.1,
                            color: ink,
                          ),
                          a: GlassText.body(
                            p,
                            bodySize,
                            color: p.accent,
                          ),
                          blockSpacing: 12,
                          listIndent: 20,
                          horizontalRuleDecoration:
                              BoxDecoration(color: p.hairline),
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

class _SaveButton extends StatelessWidget {
  final GlassPalette palette;
  final bool isSaved;
  final VoidCallback? onTap;

  const _SaveButton({
    required this.palette,
    required this.isSaved,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.84,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSaved
              ? palette.danger.withValues(alpha: 0.13)
              : Colors.transparent,
        ),
        child: Center(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutBack,
            scale: isSaved ? 1.15 : 1.0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: child,
              ),
              child: FaIcon(
                isSaved
                    ? FontAwesomeIcons.solidHeart
                    : FontAwesomeIcons.heart,
                key: ValueKey(isSaved),
                size: 16,
                color: isSaved ? palette.danger : palette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin animated pulse shown while tokens are streaming in.
class _LiveLine extends StatefulWidget {
  const _LiveLine();

  @override
  State<_LiveLine> createState() => _LiveLineState();
}

class _LiveLineState extends State<_LiveLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(height: 2, color: p.accent.withValues(alpha: 0.5));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 2,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return Align(
              alignment: Alignment(t * 2 - 1, 0),
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        p.accent.withValues(alpha: 0),
                        p.accent,
                        p.accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  final GlassPalette palette;
  final String? title;

  const _LoadingState({required this.palette, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const AuroraOrb(size: 60),
        const SizedBox(height: 18),
        Text(
          title == null || title!.isEmpty
              ? 'Looking up…'
              : 'Looking up \u201C$title\u201D…',
          style: GlassText.body(palette, 13.5,
              weight: FontWeight.w500, color: palette.textSecondary),
        ),
      ],
    );
  }
}
