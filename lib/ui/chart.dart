import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import 'theme.dart';
import 'motion.dart';

class TemperatureChart extends StatelessWidget {
  const TemperatureChart({
    super.key,
    required this.readings,
    required this.unit,
  });
  final List<Reading> readings;
  final TemperatureUnit unit;
  @override
  Widget build(BuildContext context) {
    if (readings.length < 2) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.show_chart_rounded, color: muted, size: 32),
              SizedBox(height: 12),
              Text(
                'Your temperature trend will appear here',
                style: TextStyle(color: muted),
              ),
              Text(
                'Save at least two readings to see a trend.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }
    final values = readings.map((r) => unit.convert(r.celsius)).toList();
    final span = readings.last.at.difference(readings.first.at).inMilliseconds;
    final positions = List.generate(
      readings.length,
      (i) => span == 0
          ? i / (readings.length - 1)
          : readings[i].at.difference(readings.first.at).inMilliseconds / span,
    );
    final timeFormat = DateFormat(
      readings.last.at
                      .toLocal()
                      .difference(readings.first.at.toLocal())
                      .inHours >=
                  24 ||
              readings.first.at.toLocal().day != readings.last.at.toLocal().day
          ? 'MMM d'
          : 'h:mm a',
    );
    final min = (values.reduce(math.min) - .25).floorToDouble();
    final max = math.max(
      min + 1,
      (values.reduce(math.max) + .25).ceilToDouble(),
    );
    return Semantics(
      label:
          'Temperature trend, ${unit.format(readings.first.celsius)} to ${unit.format(readings.last.celsius)} ${unit.symbol}',
      child: Column(
        children: [
          SizedBox(
            height: 170,
            child: Row(
              children: [
                SizedBox(
                  width: 35,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [max, (min + max) / 2, min]
                        .map(
                          (v) => Text(
                            v.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                        )
                        .toList(),
                  ),
                ),
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: motionTime(context, 650),
                    curve: Curves.easeOutCubic,
                    builder: (_, progress, _) => CustomPaint(
                      size: const Size(double.infinity, 170),
                      painter: _ChartPainter(
                        values,
                        positions,
                        min,
                        max,
                        progress,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 35),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  timeFormat.format(readings.first.at.toLocal()),
                  style: const TextStyle(fontSize: 10, color: muted),
                ),
                Text(
                  timeFormat.format(
                    readings.first.at
                        .add(Duration(milliseconds: span ~/ 2))
                        .toLocal(),
                  ),
                  style: const TextStyle(fontSize: 10, color: muted),
                ),
                Text(
                  timeFormat.format(readings.last.at.toLocal()),
                  style: const TextStyle(fontSize: 10, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.values, this.positions, this.min, this.max, this.progress);
  final List<double> values;
  final List<double> positions;
  final double min;
  final double max;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = 5 + (size.height - 10) * i / 2;
      for (double x = 0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 3, y), grid);
      }
    }
    final points = List.generate(
      values.length,
      (i) => Offset(
        positions[i] * (size.width - 8),
        5 + (size.height - 10) * (1 - (values[i] - min) / (max - min)),
      ),
    );
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final next = points[i];
      path.lineTo(next.dx, next.dy);
    }
    final fill = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x336D4ED0), Color(0x006D4ED0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 5, Paint()..color = Colors.white);
      canvas.drawCircle(point, 3, Paint()..color = teal);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.values != values ||
      old.positions != positions ||
      old.min != min ||
      old.max != max ||
      old.progress != progress;
}
