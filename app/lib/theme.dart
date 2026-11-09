import 'package:flutter/material.dart';

/// App colours, the same values as the studied app (sampled from its screens, light and dark).
class AppColors {
  const AppColors._({
    required this.background,
    required this.sheet,
    required this.card,
    required this.pictureCard,
    required this.primary,
    required this.onPrimary,
    required this.selected,
    required this.onSelected,
    required this.strip,
    required this.text,
    required this.muted,
    required this.outline,
    required this.chip,
  });

  final Color background;
  final Color sheet;
  final Color card;
  final Color pictureCard;
  final Color primary;
  final Color onPrimary;
  final Color selected;
  final Color onSelected;
  final Color strip;
  final Color text;
  final Color muted;
  final Color outline;
  final Color chip;

  static const light = AppColors._(
    background: Color(0xFFF7F9FF),
    sheet: Color(0xFFF1F4F9),
    card: Color(0xFFFFFFFF),
    pictureCard: Color(0xFFE5E8ED),
    primary: Color(0xFF28638A),
    onPrimary: Color(0xFFFFFFFF),
    selected: Color(0xFFBBE9FF),
    onSelected: Color(0xFF001F2A),
    strip: Color(0xFFDDE3EA),
    text: Color(0xFF181C20),
    muted: Color(0xFF41474D),
    outline: Color(0xFF71787E),
    chip: Color(0xFFE0E3E8),
  );

  static const dark = AppColors._(
    background: Color(0xFF101417),
    sheet: Color(0xFF1C2024),
    card: Color(0xFF181C20),
    pictureCard: Color(0xFF262A2E),
    primary: Color(0xFF96CCF8),
    onPrimary: Color(0xFF00344F),
    selected: Color(0xFF004D64),
    onSelected: Color(0xFFBBE9FF),
    strip: Color(0xFF41474D),
    text: Color(0xFFDFE3E8),
    muted: Color(0xFFC1C7CE),
    outline: Color(0xFF8B9198),
    chip: Color(0xFF31353A),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Outfit at a given weight (variable font axis).
TextStyle outfit(double size, {double weight = 400, Color? color, double? height}) => TextStyle(
      fontFamily: 'Outfit',
      fontSize: size,
      fontVariations: [FontVariation('wght', weight)],
      fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
      color: color,
      height: height,
      letterSpacing: 0,
    );

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF28638A), brightness: brightness)
      .copyWith(
    primary: c.primary,
    onPrimary: c.onPrimary,
    surface: c.background,
    onSurface: c.text,
    onSurfaceVariant: c.muted,
    secondaryContainer: c.selected,
    onSecondaryContainer: c.onSelected,
    outline: c.outline,
  );
  final base = ThemeData(colorScheme: scheme, brightness: brightness, fontFamily: 'Outfit');
  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    textTheme: base.textTheme.apply(fontFamily: 'Outfit', bodyColor: c.text, displayColor: c.text),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.sheet,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
  );
}
