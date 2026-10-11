import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'motion.dart';

/// The sky and companion are decorative, independent of the sensor reading.
class NightBackdrop extends StatefulWidget {
  const NightBackdrop({super.key, required this.child, this.showMoon = true});
  final Widget child;
  final bool showMoon;

  @override
  State<NightBackdrop> createState() => _NightBackdropState();
}

class NightClock extends InheritedWidget {
  const NightClock({super.key, required this.clock, required super.child});
  final Animation<double> clock;
  static Animation<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NightClock>()?.clock ??
      const AlwaysStoppedAnimation(0);
  @override
  bool updateShouldNotify(NightClock oldWidget) => oldWidget.clock != clock;
}

class _NightBackdropState extends State<NightBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      clock.stop();
      clock.value = 0;
    } else if (!clock.isAnimating) {
      clock.repeat();
    }
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF15132F), Color(0xFF302865), Color(0xFF454274)],
      ),
    ),
    child: NightClock(
      clock: clock,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: motionTime(context, 320),
                child: SizedBox.expand(
                  key: ValueKey(widget.showMoon),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _SkyPainter(widget.showMoon, clock),
                    ),
                  ),
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    ),
  );
}

class CareMascot extends StatelessWidget {
  const CareMascot({super.key, this.width = 210, this.pawsOnly = false});
  final double width;
  final bool pawsOnly;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: width,
      height: width * .62,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _MascotPainter(pawsOnly, NightClock.of(context)),
        ),
      ),
    ),
  );
}

class _MascotPainter extends CustomPainter {
  _MascotPainter(this.pawsOnly, this.clock) : super(repaint: clock);
  final bool pawsOnly;
  final Animation<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 240, size.height / 149);
    final wave = math.sin(clock.value * math.pi * 2);
    canvas.translate(0, -wave * 2);
    canvas.translate(120, 130);
    canvas.scale(1 + wave * .006, 1 + wave * .012);
    canvas.translate(-120, -130);
    final blink = clock.value > .76 && clock.value < .81
        ? math.sin((clock.value - .76) / .05 * math.pi)
        : 0.0;
    final body = Path()
      ..moveTo(34, 130)
      ..cubicTo(34, 62, 62, 15, 119, 15)
      ..cubicTo(178, 15, 207, 65, 207, 130)
      ..close();
    if (!pawsOnly) {
      canvas.drawPath(
        body,
        Paint()
          ..color = const Color(0x557E55F1)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 17),
      );
      canvas.drawPath(
        body,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFD5B8FF), Color(0xFFB58DF0)],
          ).createShader(const Rect.fromLTWH(34, 15, 173, 120)),
      );
      canvas.drawPath(
        body,
        Paint()
          ..color = const Color(0xFFE7D4FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(83, 87),
          width: 14,
          height: 22 - blink * 20,
        ),
        Paint()..color = const Color(0xFF291445),
      );
      final wink = Path()
        ..moveTo(146, 88)
        ..quadraticBezierTo(154, 75, 163, 87);
      canvas.drawPath(
        wink,
        Paint()
          ..color = const Color(0xFF291445)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
      final smile = Path()
        ..moveTo(109, 94)
        ..quadraticBezierTo(120, 101, 131, 94)
        ..quadraticBezierTo(130, 111, 120, 110)
        ..quadraticBezierTo(110, 110, 109, 94);
      canvas.drawPath(smile, Paint()..color = const Color(0xFF291445));
      canvas.drawOval(
        const Rect.fromLTWH(65, 99, 22, 13),
        Paint()..color = const Color(0xFFF6AEDF),
      );
      canvas.drawOval(
        const Rect.fromLTWH(163, 97, 22, 13),
        Paint()..color = const Color(0xFFF6AEDF),
      );
      final heart = Path()
        ..moveTo(223, 83)
        ..cubicTo(198, 68, 207, 55, 219, 63)
        ..cubicTo(232, 52, 246, 67, 223, 83);
      canvas.save();
      canvas.translate(0, -wave * 3);
      canvas.drawPath(heart, Paint()..color = const Color(0xFFF5ACD6));
      canvas.restore();
      final sparkle = Paint()
        ..color = const Color(0xFFFFF1CC)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(193, 28), const Offset(196, 14), sparkle);
      canvas.drawLine(const Offset(210, 39), const Offset(221, 28), sparkle);
    }
    for (final paw in [
      const Rect.fromLTWH(12, 113, 37, 27),
      const Rect.fromLTWH(191, 113, 37, 27),
    ]) {
      canvas.drawOval(paw, Paint()..color = const Color(0xFFCBA8FF));
      canvas.drawOval(
        paw,
        Paint()
          ..color = const Color(0xFF8151D9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MascotPainter old) =>
      old.pawsOnly != pawsOnly || old.clock != clock;
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.showMoon, this.clock) : super(repaint: clock);
  final bool showMoon;
  final Animation<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final random = math.Random(24);
    for (var i = 0; i < 65; i++) {
      final point = Offset(random.nextDouble() * w, random.nextDouble() * h);
      canvas.drawCircle(
        point,
        i % 7 == 0 ? 1.5 : .8,
        Paint()
          ..color = const Color(0xFFBFAAFF).withValues(
            alpha:
                (i % 3 == 0 ? .4 : .18) +
                .10 * math.sin(clock.value * math.pi * 2 + i * .8),
          ),
      );
    }
    void star(double x, double y, double radius) {
      radius *= 1 + .08 * math.sin(clock.value * math.pi * 2);
      final p = Path()
        ..moveTo(x, y - radius)
        ..quadraticBezierTo(x + radius * .22, y - radius * .16, x + radius, y)
        ..quadraticBezierTo(x + radius * .18, y + radius * .15, x, y + radius)
        ..quadraticBezierTo(x - radius * .2, y + radius * .2, x - radius, y)
        ..quadraticBezierTo(x - radius * .2, y - radius * .16, x, y - radius);
      canvas.drawPath(
        p,
        Paint()
          ..color = const Color(0x77FFD78B)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(p, Paint()..color = const Color(0xFFFFE5A2));
    }

    if (showMoon) {
      star(w * .12, h * .15, 4);
      star(w * .87, h * .24, 7);
      star(w * .23, h * .34, 5);
    }
    final moonCenter = Offset(w * .12, h * .25);
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: moonCenter, radius: 20)),
      Path()..addOval(
        Rect.fromCircle(center: moonCenter.translate(10, -8), radius: 19),
      ),
    );
    if (showMoon) {
      canvas.drawPath(
        moon,
        Paint()
          ..color = const Color(0x55FFD989)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawPath(moon, Paint()..color = const Color(0xFFFFE4A0));
    }
    // Quiet layers of hills at the bottom, with a tiny lighted home.
    for (var i = 0; i < 3; i++) {
      final y = h - 35 - (2 - i) * 30;
      final hill = Path()
        ..moveTo(0, y)
        ..cubicTo(w * .23, y - 60 + i * 30, w * .35, y + 35, w * .57, y)
        ..cubicTo(w * .8, y - 40, w * .9, y - 45, w, y - 15)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(
        hill,
        Paint()
          ..color = [
            const Color(0xFF575488),
            const Color(0xFF36375D),
            const Color(0xFF20233F),
          ][i],
      );
    }
    final x = w * .91;
    final y = h - 30;
    final house = Path()
      ..moveTo(x - 22, y - 20)
      ..lineTo(x, y - 39)
      ..lineTo(x + 23, y - 20)
      ..lineTo(x + 17, y - 20)
      ..lineTo(x + 17, y + 8)
      ..lineTo(x - 17, y + 8)
      ..lineTo(x - 17, y - 20)
      ..close();
    canvas.drawPath(house, Paint()..color = const Color(0xFF171A32));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 5, y - 15, 12, 15),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFFFFDF94),
    );
    canvas.drawLine(
      Offset(x + 1, y - 15),
      Offset(x + 1, y),
      Paint()
        ..color = const Color(0xFF34304E)
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      Offset(x - 5, y - 8),
      Offset(x + 7, y - 8),
      Paint()
        ..color = const Color(0xFF34304E)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SkyPainter oldDelegate) =>
      oldDelegate.showMoon != showMoon || oldDelegate.clock != clock;
}
