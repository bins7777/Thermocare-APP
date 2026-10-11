import 'dart:math' as math;
import 'package:flutter/material.dart';

bool reduceMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);
Duration motionTime(BuildContext context, [int milliseconds = 320]) =>
    reduceMotion(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

class MotionSize extends StatelessWidget {
  const MotionSize({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => reduceMotion(context)
      ? child
      : AnimatedSize(
          alignment: Alignment.topCenter,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          child: child,
        );
}

/// Keeps native button gestures, focus, scrolling, and semantics intact.
class MotionPress extends StatefulWidget {
  const MotionPress({super.key, required this.child});
  final Widget child;

  @override
  State<MotionPress> createState() => _MotionPressState();
}

class _MotionPressState extends State<MotionPress> {
  bool pressed = false;
  bool hovered = false;
  Offset? origin;

  bool get enabled => switch (widget.child) {
    ButtonStyleButton button =>
      button.onPressed != null || button.onLongPress != null,
    IconButton button => button.onPressed != null,
    InkWell well => well.onTap != null || well.onLongPress != null,
    ChoiceChip chip => chip.onSelected != null,
    FilterChip chip => chip.onSelected != null,
    _ => true,
  };

  void press(bool value) {
    if (pressed != value) setState(() => pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final animate = !reduceMotion(context) && enabled;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Listener(
        onPointerDown: (event) {
          origin = event.position;
          if (enabled) press(true);
        },
        onPointerMove: (event) {
          if (origin != null && (event.position - origin!).distance > 10) {
            press(false);
          }
        },
        onPointerUp: (_) => press(false),
        onPointerCancel: (_) => press(false),
        child: AnimatedScale(
          scale: !animate
              ? 1
              : pressed
              ? .965
              : hovered
              ? 1.015
              : 1,
          duration: motionTime(context, pressed ? 110 : 280),
          curve: pressed ? Curves.easeOutCubic : Curves.easeOutBack,
          child: widget.child,
        ),
      ),
    );
  }
}

class EnterMotion extends StatefulWidget {
  const EnterMotion({super.key, required this.child, this.delay = 0});
  final Widget child;
  final int delay;

  @override
  State<EnterMotion> createState() => _EnterMotionState();
}

class _EnterMotionState extends State<EnterMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 460 + widget.delay),
  );
  late final CurvedAnimation progress = CurvedAnimation(
    parent: controller,
    curve: Interval(
      widget.delay / (460 + widget.delay),
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      controller.value = 1;
    } else if (controller.status == AnimationStatus.dismissed) {
      controller.forward();
    }
  }

  @override
  void dispose() {
    progress.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: progress,
    child: AnimatedBuilder(
      animation: progress,
      child: widget.child,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, (1 - progress.value) * 13),
        child: child,
      ),
    ),
  );
}

class CheerMotion extends StatefulWidget {
  const CheerMotion({super.key, required this.trigger, required this.child});
  final int trigger;
  final Widget child;

  @override
  State<CheerMotion> createState() => _CheerMotionState();
}

class _CheerMotionState extends State<CheerMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: 1,
  );

  @override
  void didUpdateWidget(CheerMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger && !reduceMotion(context)) {
      controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) controller.value = 1;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (_, child) {
      final lift = math.sin(controller.value * math.pi);
      return Transform.translate(
        offset: Offset(0, -lift * 9),
        child: Transform.rotate(
          angle: math.sin(controller.value * math.pi * 2) * .035,
          child: child,
        ),
      );
    },
  );
}
