import 'package:flutter/material.dart';
import 'theme.dart';

/// Small, bundled portraits that render consistently without emoji fonts.
class FamilyPortrait extends StatelessWidget {
  const FamilyPortrait({super.key, required this.kind, required this.size});
  final int kind;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ClipOval(child: CustomPaint(painter: _PortraitPainter(kind))),
  );
}

class _PortraitPainter extends CustomPainter {
  const _PortraitPainter(this.kind);
  final int kind;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    final baby = kind == 0;
    final child = kind == 1 || kind == 2;
    final longHair = kind == 2 || kind == 4;
    final elder = kind == 5 || kind == 6;
    final hair = elder ? const Color(0xFFB9AACD) : const Color(0xFF54406C);
    final skin = [
      const Color(0xFFFFD9BD),
      const Color(0xFFEDBC9D),
      const Color(0xFFF6C9AD),
      const Color(0xFFD7A482),
    ][kind % 4];
    final paint = Paint()..isAntiAlias = true;
    void oval(Rect rect, Color color) => canvas.drawOval(
      rect,
      paint
        ..color = color
        ..style = PaintingStyle.fill,
    );
    void rounded(Rect rect, double radius, Color color) => canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint
        ..color = color
        ..style = PaintingStyle.fill,
    );
    void stroke(Path path, Color color, double width) => canvas.drawPath(
      path,
      paint
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    oval(const Rect.fromLTWH(0, 0, 64, 64), pale);
    if (kind == 6) oval(const Rect.fromLTWH(23, 3, 19, 18), hair);
    if (longHair || kind == 6) {
      rounded(const Rect.fromLTWH(12, 10, 40, 48), 19, hair);
    }
    // Rounded shoulders, collar and neck.
    oval(
      const Rect.fromLTWH(9, 48, 46, 38),
      child ? const Color(0xFFA68AEC) : teal,
    );
    rounded(const Rect.fromLTWH(26, 41, 12, 14), 5, skin);
    stroke(
      Path()
        ..moveTo(24, 53)
        ..quadraticBezierTo(32, 61, 40, 53),
      const Color(0xFFDCCAFF),
      2.5,
    );
    final head = baby
        ? const Rect.fromLTWH(15, 15, 34, 36)
        : const Rect.fromLTWH(16, 12, 32, 38);
    oval(const Rect.fromLTWH(12, 29, 10, 12), skin);
    oval(const Rect.fromLTWH(42, 29, 10, 12), skin);
    oval(head, skin);
    if (!baby) {
      final fringe = Path()
        ..moveTo(16, 30)
        ..cubicTo(9, 9, 30, 5, 42, 12)
        ..quadraticBezierTo(53, 17, 48, 31)
        ..lineTo(42, 21)
        ..quadraticBezierTo(29, 29, 23, 21)
        ..close();
      canvas.drawPath(
        fringe,
        paint
          ..color = hair
          ..style = PaintingStyle.fill,
      );
      if (kind == 2) {
        oval(const Rect.fromLTWH(7, 28, 12, 20), hair);
        oval(const Rect.fromLTWH(45, 28, 12, 20), hair);
        rounded(const Rect.fromLTWH(9, 27, 9, 5), 2, const Color(0xFFF4A9CE));
        rounded(const Rect.fromLTWH(46, 27, 9, 5), 2, const Color(0xFFF4A9CE));
      }
    } else {
      stroke(
        Path()
          ..moveTo(29, 18)
          ..cubicTo(40, 12, 28, 8, 31, 14),
        hair,
        2.5,
      );
    }
    // Friendly eyes and rosy cheeks remain legible at small sizes.
    oval(const Rect.fromLTWH(23, 31, 3.5, 5), ink);
    oval(const Rect.fromLTWH(37.5, 31, 3.5, 5), ink);
    oval(const Rect.fromLTWH(19, 37, 8, 4), const Color(0xFFEF9DAE));
    oval(const Rect.fromLTWH(37, 37, 8, 4), const Color(0xFFEF9DAE));
    stroke(
      Path()
        ..moveTo(28, 41)
        ..quadraticBezierTo(32, 45, 36, 41),
      ink,
      1.8,
    );
    if (kind == 3) {
      stroke(
        Path()
          ..moveTo(25, 44)
          ..quadraticBezierTo(32, 51, 39, 44),
        hair,
        3,
      );
    }
    if (elder) {
      final glasses = paint
        ..color = const Color(0xFF806C9E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(19, 29, 11, 9),
          const Radius.circular(4),
        ),
        glasses,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(34, 29, 11, 9),
          const Radius.circular(4),
        ),
        glasses,
      );
      canvas.drawLine(const Offset(30, 32), const Offset(34, 32), glasses);
      if (kind == 5) {
        stroke(
          Path()
            ..moveTo(28, 40)
            ..quadraticBezierTo(32, 38, 36, 40),
          hair,
          2.5,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PortraitPainter oldDelegate) => oldDelegate.kind != kind;
}
