import 'package:flutter/material.dart';

import 'riff_tokens.dart';

/// Bundled Inter (SIL OFL, assets/fonts/): the closest free match to X's
/// Chirp. Never fetched at runtime.
const String kRiffFontFamily = 'Inter';

/// The "X Lights out, Riff green" theme (RIFF_UI_RESTYLE.md): content on
/// pure black, structure from hairlines, three text levels, the user's
/// accent only on interactive things.
///
/// Geometry the app's layout depends on is pinned to what the previous
/// (Material 2) theme produced — toolbar height, list-tile padding,
/// divider spacing — so switching to Material 3 restyles without moving
/// anything.
class RiffTheme {
  RiffTheme._();

  static TextStyle _t(
          double size, double height, FontWeight weight, Color color) =>
      TextStyle(
        fontFamily: kRiffFontFamily,
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        letterSpacing: 0,
        color: color,
      );

  /// Type scale (§4.5). Every slot is defined so none falls back to
  /// Material's default font or sizes.
  static TextTheme textTheme({
    Color primary = RiffPalette.textPrimary,
    Color secondary = RiffPalette.textSecondary,
  }) =>
      TextTheme(
        displayLarge: _t(40, 44, FontWeight.w800, primary),
        displayMedium: _t(34, 40, FontWeight.w800, primary),
        displaySmall: _t(28, 32, FontWeight.w800, primary),
        headlineLarge: _t(28, 32, FontWeight.w800, primary),
        headlineMedium: _t(26, 30, FontWeight.w800, primary),
        headlineSmall: _t(24, 28, FontWeight.w800, primary),
        titleLarge: _t(20, 24, FontWeight.w800, primary),
        titleMedium: _t(15, 20, FontWeight.w700, primary),
        // Not in the spec's table; the app reads its colour as "muted".
        titleSmall: _t(14, 18, FontWeight.w500, secondary),
        bodyLarge: _t(15, 20, FontWeight.w400, primary),
        bodyMedium: _t(13, 16, FontWeight.w400, secondary),
        bodySmall: _t(12, 16, FontWeight.w400, secondary),
        labelLarge: _t(15, 20, FontWeight.w700, primary),
        labelMedium: _t(14, 18, FontWeight.w600, primary),
        labelSmall: _t(12, 16, FontWeight.w600, secondary),
      );

  /// Pitch Black with [accent] (Green by default; Blue, Violet, Crimson,
  /// Amber and Cyan work the same way).
  static ThemeData dark(Color accent) {
    final text = textTheme();
    final colors = RiffColors.forAccent(accent);
    const pill = StadiumBorder();
    const hairline = BorderSide(color: RiffPalette.divider, width: 0);
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: RiffPalette.onAccent,
      // Most widgets read the accent from `secondary` (Material 2 habit).
      secondary: accent,
      onSecondary: RiffPalette.onAccent,
      secondaryContainer: colors.accentMuted,
      onSecondaryContainer: accent,
      tertiary: accent,
      onTertiary: RiffPalette.onAccent,
      error: RiffPalette.danger,
      onError: RiffPalette.textPrimary,
      surface: RiffPalette.bg,
      onSurface: RiffPalette.textPrimary,
      onSurfaceVariant: RiffPalette.textSecondary,
      surfaceContainerLowest: RiffPalette.bg,
      surfaceContainerLow: RiffPalette.surface1,
      surfaceContainer: RiffPalette.surface1,
      surfaceContainerHigh: RiffPalette.surface2,
      surfaceContainerHighest: RiffPalette.surface2,
      surfaceBright: RiffPalette.surface2,
      surfaceDim: RiffPalette.bg,
      outline: RiffPalette.outlineStrong,
      outlineVariant: RiffPalette.divider,
      shadow: RiffPalette.bg,
      scrim: RiffPalette.bg,
      inverseSurface: RiffPalette.textPrimary,
      onInverseSurface: RiffPalette.bg,
      inversePrimary: accent,
      surfaceTint: Colors.transparent,
    );

    WidgetStateProperty<T> states<T>(T on, T off,
            {Set<WidgetState> when = const {WidgetState.selected}}) =>
        WidgetStateProperty.resolveWith((s) => s.any(when.contains) ? on : off);

    final buttonText = text.labelLarge!;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: kRiffFontFamily,
      textTheme: text,
      primaryTextTheme: text,
      extensions: [colors],
      // Material 2 properties some screens still read.
      primaryColor: RiffPalette.bg,
      primaryColorDark: RiffPalette.bg,
      primaryColorLight: RiffPalette.surface2,
      canvasColor: RiffPalette.bg,
      scaffoldBackgroundColor: RiffPalette.bg,
      cardColor: RiffPalette.surface1,
      dividerColor: RiffPalette.divider,
      indicatorColor: accent,
      hintColor: RiffPalette.textSecondary,
      disabledColor: RiffPalette.textSecondary,
      unselectedWidgetColor: RiffPalette.textSecondary,
      // Flat press feedback, no ink ripple (§2.7).
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: RiffPalette.surface2,
      hoverColor: RiffPalette.surface2,
      focusColor: RiffPalette.surface2,
      iconTheme: const IconThemeData(color: RiffPalette.textPrimary),
      primaryIconTheme: const IconThemeData(color: RiffPalette.textPrimary),
      dividerTheme: const DividerThemeData(
        color: RiffPalette.divider,
        // One physical pixel. `space` keeps Material's default so existing
        // Divider() gaps don't change (see docs/redesign/SKIPPED.md).
        thickness: 0,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: RiffPalette.bg,
        foregroundColor: RiffPalette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        // Material 2 height: the bars keep their place.
        toolbarHeight: kToolbarHeight,
        titleTextStyle: text.titleLarge,
        iconTheme: const IconThemeData(
            color: RiffPalette.textPrimary,
            size: RiffComponentSizes.headerIcon),
      ),
      listTileTheme: ListTileThemeData(
        // Material 2 geometry (16 both sides), Lights-out type.
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: RiffPalette.textPrimary,
        textColor: RiffPalette.textPrimary,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium,
        leadingAndTrailingTextStyle: text.bodyMedium,
        selectedColor: accent,
        tileColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: RiffPalette.onAccent,
          disabledBackgroundColor: RiffPalette.surface2,
          disabledForegroundColor: RiffPalette.textSecondary,
          textStyle: buttonText,
          shape: pill,
          elevation: 0,
          minimumSize: const Size(64, RiffComponentSizes.button),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: RiffPalette.onAccent,
          textStyle: buttonText,
          shape: pill,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: RiffPalette.textPrimary,
          textStyle: buttonText,
          shape: pill,
          side: const BorderSide(color: RiffPalette.outlineStrong),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: buttonText,
          shape: pill,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: RiffPalette.textPrimary,
          highlightColor: RiffPalette.surface2,
          // Material 2's 48 dp: existing touch targets keep their size
          // and the icons their place.
          minimumSize: const Size.square(kMinInteractiveDimension),
          // Buttons that set their own smaller constraints (dense rows)
          // keep that size, as they did under Material 2.
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: RiffPalette.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const CircleBorder(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: colors.accentMuted,
        disabledColor: RiffPalette.surface1,
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium!.copyWith(color: accent),
        side: WidgetStateBorderSide.resolveWith((s) => BorderSide(
            color: s.contains(WidgetState.selected)
                ? accent
                : RiffPalette.divider)),
        shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        showCheckmark: false,
        checkmarkColor: accent,
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      tabBarTheme: TabBarTheme(
        labelColor: RiffPalette.textPrimary,
        unselectedLabelColor: RiffPalette.textSecondary,
        labelStyle: text.labelLarge,
        unselectedLabelStyle:
            text.labelLarge!.copyWith(fontWeight: FontWeight.w500),
        indicator: ShapeDecoration(
          color: accent,
          shape: const StadiumBorder(),
        ),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: RiffPalette.divider,
        dividerHeight: 0,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: text.bodyLarge!.copyWith(color: RiffPalette.textSecondary),
        labelStyle: text.bodyLarge!.copyWith(color: RiffPalette.textSecondary),
        prefixIconColor: RiffPalette.textSecondary,
        suffixIconColor: RiffPalette.textSecondary,
        focusColor: accent,
        // Only the fallback `border`: Flutter draws it 2 dp in the accent
        // when focused, and fields that pass their own border (pill search
        // fields) keep theirs in every state.
        border: const OutlineInputBorder(
            borderSide: hairline,
            borderRadius: BorderRadius.all(Radius.circular(RiffRadii.xs))),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withOpacity(0.35),
        selectionHandleColor: accent,
      ),
      switchTheme: SwitchThemeData(
        trackColor: states(accent, RiffPalette.surface2),
        thumbColor: states(RiffPalette.onAccent, RiffPalette.textSecondary),
        trackOutlineColor:
            states<Color>(Colors.transparent, RiffPalette.outlineStrong),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: states(accent, Colors.transparent),
        checkColor: const WidgetStatePropertyAll(RiffPalette.onAccent),
        side: const BorderSide(color: RiffPalette.outlineStrong, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: states(accent, RiffPalette.textSecondary),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: RiffPalette.divider,
        thumbColor: accent,
        overlayColor: accent.withOpacity(0.12),
        valueIndicatorColor: RiffPalette.surface2,
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: RiffPalette.divider,
        circularTrackColor: Colors.transparent,
        refreshBackgroundColor: RiffPalette.surface1,
        linearMinHeight: 2,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: RiffPalette.surface1,
        modalBackgroundColor: RiffPalette.surface1,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: colors.barrier,
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: colors.handle,
        dragHandleSize: const Size(
            RiffComponentSizes.handleWidth, RiffComponentSizes.handleHeight),
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(RiffRadii.lg)),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: RiffPalette.surface1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        barrierColor: colors.barrier,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyLarge,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(RiffRadii.lg)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: RiffPalette.surface1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: text.bodyLarge,
        labelTextStyle: WidgetStatePropertyAll(text.bodyLarge),
        shape: const RoundedRectangleBorder(
          side: hairline,
          borderRadius: BorderRadius.all(Radius.circular(RiffRadii.sm)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: accent,
        contentTextStyle: text.bodyLarge!
            .copyWith(color: RiffPalette.onAccent, fontWeight: FontWeight.w600),
        actionTextColor: RiffPalette.onAccent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(RiffRadii.sm)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: RiffPalette.surface2,
          borderRadius: BorderRadius.all(Radius.circular(RiffRadii.xs)),
        ),
        textStyle: text.labelSmall!.copyWith(color: RiffPalette.textPrimary),
      ),
      cardTheme: const CardTheme(
        color: RiffPalette.surface1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: RiffPalette.bg,
        indicatorColor: Colors.transparent,
        selectedIconTheme:
            IconThemeData(color: accent, size: RiffComponentSizes.railIcon),
        unselectedIconTheme: const IconThemeData(
            color: RiffPalette.textPrimary, size: RiffComponentSizes.railIcon),
        selectedLabelTextStyle: text.labelSmall!.copyWith(color: accent),
        unselectedLabelTextStyle: text.labelSmall,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        // Keep the transition types the app had (Material 2 defaults).
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
