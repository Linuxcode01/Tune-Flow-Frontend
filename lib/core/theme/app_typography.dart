import 'package:flutter/material.dart';

/// Type scale for the app (docs section 8).
///
/// The platform font is used intentionally - no custom font is bundled, which keeps the binary
/// small and avoids a font-loading flash on first paint.
class AppTypography {
  const AppTypography._();

  static const TextTheme darkTextTheme = TextTheme(
    displaySmall: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.5),
    headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3),
    headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 16, height: 1.4),
    bodyMedium: TextStyle(fontSize: 14, height: 1.4),
    bodySmall: TextStyle(fontSize: 12, height: 1.35),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.4),
  );

  static const TextTheme lightTextTheme = darkTextTheme;
}
