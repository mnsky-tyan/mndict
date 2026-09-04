import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/glass_theme.dart';
import 'glass_container.dart';

class GlassSearchBar extends StatefulWidget {
  final TextEditingController? controller;
  final Function(String)? onSubmitted;

  /// Fired when the user taps the (x) clear button — the app returns to
  /// its idle orb state.
  final VoidCallback? onClear;
  final bool enabled;

  const GlassSearchBar({
    super.key,
    this.controller,
    this.onSubmitted,
    this.onClear,
    this.enabled = true,
  });

  @override
  State<GlassSearchBar> createState() => _GlassSearchBarState();
}

class _GlassSearchBarState extends State<GlassSearchBar> {
  late final FocusNode _focusNode;
  bool _focused = false;
  bool _pressed = false;
  bool _goPressed = false;
  bool _clearPressed = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()
      ..addListener(() {
        if (!mounted) return;
        setState(() => _focused = _focusNode.hasFocus);
        // A light tick when the field gains focus — the tactile half of
        // the button-press feel.
        if (_focusNode.hasFocus) HapticFeedback.lightImpact();
      });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.onSubmitted != null && widget.controller != null) {
      widget.onSubmitted!(widget.controller!.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    final controller = widget.controller;

    // Listener (not GestureDetector) observes presses without entering the
    // gesture arena, so the TextField's own tap handling is untouched —
    // the whole bar just compresses slightly while touched, like a button.
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        scale: _pressed ? 0.97 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _focused
                    ? p.accent.withValues(alpha: p.isDark ? 0.35 : 0.22)
                    : Colors.transparent,
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: GlassContainer(
            height: 48,
            borderRadius: 24,
            chrome: true,
            rim: true,
            padding: const EdgeInsets.only(left: 15, right: 7),
            child: Row(
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  scale: _focused ? 1.15 : 1.0,
                  child: FaIcon(
                    FontAwesomeIcons.magnifyingGlass,
                    color: _focused
                        ? p.accent
                        : p.textSecondary.withValues(alpha: 0.85),
                    size: 15,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: _focusNode,
                    enabled: widget.enabled,
                    onSubmitted: widget.onSubmitted,
                    textInputAction: TextInputAction.search,
                    style: GlassText.body(p, 15, weight: FontWeight.w400),
                    cursorColor: p.accent,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      hintText: 'Search a word or phrase',
                      hintStyle: GlassText.body(
                        p,
                        14.5,
                        color: p.textSecondary.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable:
                      controller ?? ValueNotifier(const TextEditingValue()),
                  builder: (context, value, _) {
                    final hasText = value.text.isNotEmpty;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasText)
                          GestureDetector(
                            onTapDown: (_) =>
                                setState(() => _clearPressed = true),
                            onTapUp: (_) =>
                                setState(() => _clearPressed = false),
                            onTapCancel: () =>
                                setState(() => _clearPressed = false),
                            onTap: () {
                              controller?.clear();
                              widget.onClear?.call();
                              // Clearing is the "back to the idle orb" action —
                              // let the keyboard go with it instead of
                              // re-focusing the field.
                              _focusNode.unfocus();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(7),
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 110),
                                curve: Curves.easeOut,
                                scale: _clearPressed ? 0.82 : 1.0,
                                child: FaIcon(
                                  FontAwesomeIcons.circleXmark,
                                  size: 16,
                                  color: p.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        // The go button springs in when there is something to
                        // look up, and compresses like a real button on press.
                        AnimatedScale(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutBack,
                          scale: hasText ? 1.0 : 0.0,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: hasText ? 1.0 : 0.0,
                            child: GestureDetector(
                              onTapDown: (_) =>
                                  setState(() => _goPressed = true),
                              onTapUp: (_) =>
                                  setState(() => _goPressed = false),
                              onTapCancel: () =>
                                  setState(() => _goPressed = false),
                              onTap: hasText ? _submit : null,
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 110),
                                curve: Curves.easeOut,
                                scale: _goPressed ? 0.86 : 1.0,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color.lerp(
                                          p.accent,
                                          Colors.white,
                                          0.18,
                                        )!,
                                        p.accent,
                                        Color.lerp(
                                          p.accent,
                                          Colors.black,
                                          0.22,
                                        )!,
                                      ],
                                      stops: const [0.0, 0.5, 1.0],
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: p.isDark ? 0.25 : 0.55,
                                      ),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: p.accent.withValues(alpha: 0.38),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: FaIcon(
                                      FontAwesomeIcons.arrowRight,
                                      size: 12,
                                      color: p.isDark
                                          ? const Color(0xFF0B1020)
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
