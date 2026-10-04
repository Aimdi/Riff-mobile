import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';

void main() {
  for (final entry in ThemeController.riffAccents.entries) {
    test('${entry.key} accent: Lights out with that accent', () {
      final t = RiffTheme.dark(entry.value);
      final s = t.colorScheme;
      expect(t.useMaterial3, isTrue);
      expect(t.scaffoldBackgroundColor, RiffPalette.bg);
      expect(s.surface, RiffPalette.bg);
      expect(s.surfaceTint, Colors.transparent);
      expect(s.primary, entry.value);
      // Widgets that still read the accent from `secondary` keep working.
      expect(s.secondary, entry.value);
      expect(s.onPrimary, RiffPalette.onAccent);
      expect(s.outlineVariant, RiffPalette.divider);
      expect(t.extension<RiffColors>()!.accentMuted,
          RiffPalette.accentMuted(entry.value));
    });
  }

  test('every text slot is Inter with a set size and weight', () {
    final text = RiffTheme.dark(const Color(0xFF1DB954)).textTheme;
    final slots = <String, TextStyle?>{
      'displayLarge': text.displayLarge,
      'displayMedium': text.displayMedium,
      'displaySmall': text.displaySmall,
      'headlineLarge': text.headlineLarge,
      'headlineMedium': text.headlineMedium,
      'headlineSmall': text.headlineSmall,
      'titleLarge': text.titleLarge,
      'titleMedium': text.titleMedium,
      'titleSmall': text.titleSmall,
      'bodyLarge': text.bodyLarge,
      'bodyMedium': text.bodyMedium,
      'bodySmall': text.bodySmall,
      'labelLarge': text.labelLarge,
      'labelMedium': text.labelMedium,
      'labelSmall': text.labelSmall,
    };
    slots.forEach((name, style) {
      expect(style?.fontFamily, kRiffFontFamily, reason: name);
      expect(style?.fontSize, isNotNull, reason: name);
      expect(style?.fontWeight, isNotNull, reason: name);
    });
    expect(text.titleLarge!.fontSize, 20);
    expect(text.titleLarge!.fontWeight, FontWeight.w800);
    expect(text.bodyLarge!.fontSize, 15);
    expect(text.bodyMedium!.color, RiffPalette.textSecondary);
  });

  test('Material 2 geometry is kept where layout depends on it', () {
    final t = RiffTheme.dark(const Color(0xFF1DB954));
    expect(t.appBarTheme.toolbarHeight, kToolbarHeight);
    expect(t.listTileTheme.contentPadding,
        const EdgeInsets.symmetric(horizontal: 16));
    expect(t.dividerTheme.space, isNull);
    expect(t.iconButtonTheme.style!.minimumSize!.resolve({}),
        const Size.square(kMinInteractiveDimension));
  });
}
