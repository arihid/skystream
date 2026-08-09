import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skystream/core/theme/app_theme.dart';

void main() {
  test('dark SnackBars use the application surface colors', () {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppTheme.primary,
      brightness: Brightness.dark,
    );
    final theme = AppTheme.snackBarThemeFor(colorScheme);

    expect(theme.backgroundColor, AppTheme.surface);
    expect(theme.contentTextStyle?.color, AppTheme.onSurface);
  });

  test(
    'light SnackBars use nearby surface colors instead of inverse colors',
    () {
      final colorScheme = ColorScheme.fromSeed(seedColor: AppTheme.lightCoral);
      final theme = AppTheme.snackBarThemeFor(colorScheme);

      expect(theme.backgroundColor, colorScheme.surfaceContainerHigh);
      expect(theme.contentTextStyle?.color, colorScheme.onSurface);
    },
  );
}
