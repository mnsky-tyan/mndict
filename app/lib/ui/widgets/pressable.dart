import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Universal press feedback: the child compresses slightly under the finger
/// and settles back on release, with a soft tick on touch-down.
///
/// The press is observed with a [Listener] (not a GestureDetector) so it
/// never enters the gesture arena — inner TextFields, scrollables and other
/// recognizers keep working untouched. When [onTap] is provided this widget
/// also owns the tap; don't wrap it around something that already handles
/// taps, or wrap with [onTap] null for feedback-only.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// Scale while pressed. Small controls go lower (0.86–0.92), full-width
  /// rows and cards stay subtler (0.96–0.98).
  final double pressedScale;
  final bool haptic;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.haptic = true,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

    return Listener(
      onPointerDown: enabled
          ? (_) {
              setState(() => _pressed = true);
              if (widget.haptic) HapticFeedback.selectionClick();
            }
          : null,
      onPointerUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onPointerCancel:
          enabled ? (_) => setState(() => _pressed = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          scale: _pressed ? widget.pressedScale : 1.0,
          child: widget.child,
        ),
      ),
    );
  }
}
