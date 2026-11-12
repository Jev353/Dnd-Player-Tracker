import 'package:flutter/material.dart';

/// Dark fantasy / tabletop theme: charcoal-slate surfaces, amber-gold accents.
ThemeData buildAppTheme() {
  const gold = Color(0xFFD4A64A);
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: gold,
    onPrimary: Color(0xFF241A05),
    secondary: Color(0xFF8C6B2E),
    onSecondary: Colors.white,
    tertiary: Color(0xFF7A8CA3),
    onTertiary: Colors.white,
    error: Color(0xFFE57373),
    onError: Colors.black,
    surface: Color(0xFF1E2229),
    onSurface: Color(0xFFE6E1D6),
    surfaceContainerLowest: Color(0xFF14171C),
    surfaceContainerLow: Color(0xFF1A1E24),
    surfaceContainer: Color(0xFF232830),
    surfaceContainerHigh: Color(0xFF2A3039),
    surfaceContainerHighest: Color(0xFF333A45),
    outline: Color(0xFF5B6472),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF14171C),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: gold.withValues(alpha: 0.25)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: gold.withValues(alpha: 0.4)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: gold, width: 1.5),
      ),
    ),
    dividerTheme: DividerThemeData(color: gold.withValues(alpha: 0.2)),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? gold : null),
      checkColor: WidgetStatePropertyAll(scheme.onPrimary),
    ),
    textTheme: Typography.whiteMountainView.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
  );
}
