import 'package:flutter/material.dart';
import 'motion.dart';

const ink = Color(0xFF2D194C);
const teal = Color(0xFF6D4ED0);
const canvas = Color(0xFF191632);
const muted = Color(0xFF756B8A);
const line = Color(0xFFE7E0F4);
const pale = Color(0xFFECE4FF);
const peach = Color(0xFFFFECD9);
const coral = Color(0xFF7355D9);
const coralInk = Color(0xFFFFFFFF);
const lavender = Color(0xFFF0EAFF);
const amber = Color(0xFF875325);
const card = Color(0xFFFAF7FF);
const nightText = Color(0xFFF0E8FF);
const nightMuted = Color(0xFFC5B8E7);

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: canvas,
  fontFamily: 'Nunito',
  colorScheme: ColorScheme.fromSeed(
    seedColor: teal,
    primary: teal,
    surface: card,
    onSurface: ink,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 34,
      height: 1.15,
      fontWeight: FontWeight.w800,
      letterSpacing: -.8,
      color: ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 27,
      height: 1.2,
      fontWeight: FontWeight.w800,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w800,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: ink),
    bodyMedium: TextStyle(fontSize: 15, height: 1.5, color: ink),
    bodySmall: TextStyle(fontSize: 13, height: 1.5, color: muted),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: coral,
      foregroundColor: coralInk,
      minimumSize: const Size(48, 52),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      textStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontWeight: FontWeight.w800,
        fontSize: 16,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      backgroundColor: card,
      disabledForegroundColor: muted,
      minimumSize: const Size(48, 52),
      foregroundColor: teal,
      side: const BorderSide(color: line, width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      textStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      textStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    height: 80,
    backgroundColor: const Color(0xEE191632),
    indicatorColor: const Color(0xFF4D3B7B),
    iconTheme: WidgetStateProperty.resolveWith(
      (states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? nightText : nightMuted,
      ),
    ),
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontFamily: 'Nunito',
        fontSize: 12,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w800
            : FontWeight.w600,
        color: states.contains(WidgetState.selected) ? nightText : nightMuted,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFF1ECFA),
    contentPadding: const EdgeInsets.all(18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: teal, width: 2),
    ),
    helperMaxLines: 3,
    errorMaxLines: 3,
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: ink,
    contentTextStyle: const TextStyle(
      fontFamily: 'Nunito',
      color: Colors.white,
      fontSize: 15,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    behavior: SnackBarBehavior.floating,
  ),
  dividerColor: line,
  chipTheme: ChipThemeData(
    backgroundColor: card,
    selectedColor: pale,
    side: const BorderSide(color: line),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    labelStyle: const TextStyle(fontFamily: 'Nunito', color: ink, fontSize: 14),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  ),
);

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.color = card,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => EnterMotion(
    child: Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x20100B29),
            blurRadius: 24,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = teal, this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: motionTime(context, 280),
    curve: Curves.easeOutCubic,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon ?? Icons.circle, size: icon == null ? 6 : 15, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      ?trailing,
    ],
  );
}
