import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:palette_generator/palette_generator.dart';
import '/utils/helper.dart';

/// X-inspired surface tokens for the Pitch Black theme:
/// layered near-black, hairline borders, muted secondary text.
class RiffSurfaces {
  static const Color voidBlack = Color(0xFF000000);
  static const Color elevated = Color(0xFF16181C);
  static const Color elevatedSoft = Color(0xFF1E2026);
  static const Color hairline = Color(0xFF2F3336);
  static const Color textMuted = Color(0xFF8B98A5);
  static const Color textPrimary = Color(0xFFE7E9EA);
}

class ThemeController extends GetxController {
  /// Riff accent palette (used by the Pitch Black theme). Green is the
  /// signature Riff accent; the rest mirror the desktop theme gallery.
  static const Map<String, Color> riffAccents = {
    'Green': Color(0xFF1DB954),
    'Blue': Color(0xFF4A9EFF),
    'Violet': Color(0xFF9B59F5),
    'Crimson': Color(0xFFE0405A),
    'Amber': Color(0xFFFFB300),
    'Cyan': Color(0xFF1D9BF0),
  };

  final primaryColor = Colors.deepPurple[400].obs;
  final textColor = Colors.white24.obs;
  final accentColor = const Color(0xFF1DB954).obs;
  final themedata = Rxn<ThemeData>();

  /// The method channel for setting the title bar color on Windows.
  final platform = const MethodChannel('win_titlebar_color');
  String? currentSongId;
  late Brightness systemBrightness;

  ThemeController() {
    systemBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    final box = Hive.box('AppPrefs');
    final primaryRaw = box.get("themePrimaryColor") ?? 4278199603;
    primaryColor.value =
        Color(primaryRaw is int ? primaryRaw : 4278199603);

    final accentRaw = box.get("riffAccentColor") ?? 0xFF1DB954;
    accentColor.value = Color(accentRaw is int ? accentRaw : 0xFF1DB954);

    changeThemeModeType(_themeTypeFromPrefs(box));

    _listenSystemBrightness();

    super.onInit();
  }

  /// Safe Hive → ThemeType mapping (invalid/missing → dark). Used on
  /// construction — runs before SettingsScreenController and blanks the app
  /// if ThemeType.values[badIndex] throws.
  static ThemeType _themeTypeFromPrefs(Box box) {
    final modeIndex = box.get("themeModeType") ?? 2;
    if (modeIndex is int &&
        modeIndex >= 0 &&
        modeIndex < ThemeType.values.length) {
      return ThemeType.values[modeIndex];
    }
    return ThemeType.dark;
  }

  void _listenSystemBrightness() {
    final platformDispatcher = WidgetsBinding.instance.platformDispatcher;
    platformDispatcher.onPlatformBrightnessChanged = () {
      systemBrightness = platformDispatcher.platformBrightness;
      changeThemeModeType(_themeTypeFromPrefs(Hive.box('AppPrefs')),
          sysCall: true);
    };
  }

  void changeThemeModeType(dynamic value, {bool sysCall = false}) {
    if (value == ThemeType.system) {
      themedata.value = _createThemeData(
          null,
          systemBrightness == Brightness.light
              ? ThemeType.light
              : ThemeType.dark);
    } else {
      if (sysCall) return;
      themedata.value = _createThemeData(
          value == ThemeType.dynamic
              ? _createMaterialColor(primaryColor.value!)
              : null,
          value);
    }
    setWindowsTitleBarColor(themedata.value!.scaffoldBackgroundColor);
  }

  /// Changes the Pitch Black accent color and rebuilds the theme.
  void changeAccentColor(Color color) {
    accentColor.value = color;
    final box = Hive.box('AppPrefs');
    box.put("riffAccentColor", color.value);
    changeThemeModeType(_themeTypeFromPrefs(box));
  }

  void setTheme(ImageProvider imageProvider, String songId) async {
    if (songId == currentSongId) return;
    PaletteGenerator generator = await PaletteGenerator.fromImageProvider(
        ResizeImage(imageProvider, height: 200, width: 200));
    //final colorList = generator.colors;
    final paletteColor = generator.dominantColor ??
        generator.darkMutedColor ??
        generator.darkVibrantColor ??
        generator.lightMutedColor ??
        generator.lightVibrantColor;
    primaryColor.value = paletteColor!.color;
    textColor.value = paletteColor.bodyTextColor;
    // printINFO(paletteColor.color.computeLuminance().toString());0.11 ref
    if (paletteColor.color.computeLuminance() > 0.10) {
      primaryColor.value = paletteColor.color.withLightness(0.10);
      textColor.value = Colors.white54;
    }
    final primarySwatch = _createMaterialColor(primaryColor.value!);
    themedata.value = _createThemeData(primarySwatch, ThemeType.dynamic,
        textColor: textColor.value,
        titleColorSwatch: _createMaterialColor(textColor.value));
    currentSongId = songId;
    Hive.box('AppPrefs').put("themePrimaryColor", (primaryColor.value!).value);
    setWindowsTitleBarColor(themedata.value!.scaffoldBackgroundColor);
  }

  /// Plus Jakarta Sans — cleaner grotesk than Inter, closer to modern X type.
  TextTheme _applyBrandFont(TextTheme base) =>
      GoogleFonts.plusJakartaSansTextTheme(base);

  ThemeData _createThemeData(MaterialColor? primarySwatch, ThemeType themeType,
      {MaterialColor? titleColorSwatch, Color? textColor}) {
    if (themeType == ThemeType.dynamic) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.light,
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.white.withOpacity(0.002),
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarContrastEnforced: true),
      );

      final baseTheme = ThemeData(
          useMaterial3: false,
          primaryColor: primarySwatch![500],
          colorScheme: ColorScheme.fromSwatch(
              accentColor: primarySwatch[200],
              brightness: Brightness.dark,
              backgroundColor: primarySwatch[700],
              primarySwatch: primarySwatch),
          //accentColor: primarySwatch[200],
          dialogBackgroundColor: primarySwatch[700],
          cardColor: primarySwatch[600],
          primaryColorLight: primarySwatch[400],
          primaryColorDark: primarySwatch[700],
          //secondaryHeaderColor: primarySwatch[50],
          canvasColor: primarySwatch[700],
          dividerColor: primarySwatch[400]?.withOpacity(0.45),
          //scaffoldBackgroundColor: primarySwatch[700],
          bottomSheetTheme: BottomSheetThemeData(
              backgroundColor: primarySwatch[600],
              modalBarrierColor: primarySwatch[400],
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              )),
          textTheme: TextTheme(
            titleLarge: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: Colors.white),
            titleMedium: const TextStyle(
                fontWeight: FontWeight.w600, color: Colors.white),
            titleSmall: TextStyle(color: primarySwatch[100]),
            bodyMedium: TextStyle(color: primarySwatch[100]),
            labelMedium: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 22,
                letterSpacing: -0.3,
                color: textColor ?? primarySwatch[50]),
            labelSmall: TextStyle(
                fontSize: 14,
                color: titleColorSwatch != null
                    ? titleColorSwatch[900]
                    : primarySwatch[100],
                letterSpacing: 0,
                fontWeight: FontWeight.w600),
          ),
          indicatorColor: Colors.white,
          progressIndicatorTheme: ProgressIndicatorThemeData(
              linearTrackColor: (primarySwatch[300])!.computeLuminance() > 0.3
                  ? Colors.black54
                  : Colors.white70,
              color: textColor),
          navigationRailTheme: NavigationRailThemeData(
              backgroundColor: primarySwatch[700],
              selectedIconTheme: const IconThemeData(color: Colors.white),
              unselectedIconTheme: IconThemeData(color: primarySwatch[100]),
              selectedLabelTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
              unselectedLabelTextStyle: TextStyle(
                  color: primarySwatch[100], fontWeight: FontWeight.w600)),
          sliderTheme: SliderThemeData(
            inactiveTrackColor: primarySwatch[300],
            activeTrackColor: textColor,
            valueIndicatorColor: primarySwatch[400],
            thumbColor: Colors.white,
          ),
          textSelectionTheme: TextSelectionThemeData(
              cursorColor: primarySwatch[200],
              selectionColor: primarySwatch[200],
              selectionHandleColor: primarySwatch[200])
          //scaffoldBackgroundColor: primarySwatch[700]
          );
      return baseTheme.copyWith(textTheme: _applyBrandFont(baseTheme.textTheme));
    } else if (themeType == ThemeType.dark) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.light,
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.white.withOpacity(0.002),
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarContrastEnforced: true),
      );
      final accent = accentColor.value;
      final baseTheme = ThemeData(
          useMaterial3: false,
          brightness: Brightness.dark,
          canvasColor: RiffSurfaces.voidBlack,
          scaffoldBackgroundColor: RiffSurfaces.voidBlack,
          primaryColor: RiffSurfaces.voidBlack,
          primaryColorDark: RiffSurfaces.voidBlack,
          primaryColorLight: RiffSurfaces.elevatedSoft,
          cardColor: RiffSurfaces.elevated,
          dividerColor: RiffSurfaces.hairline,
          colorScheme: ColorScheme.fromSwatch(
              accentColor: accent, brightness: Brightness.dark),
          indicatorColor: accent,
          progressIndicatorTheme: ProgressIndicatorThemeData(
              color: accent, linearTrackColor: RiffSurfaces.textPrimary),
          textTheme: const TextTheme(
              titleLarge: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: RiffSurfaces.textPrimary,
              ),
              titleMedium: TextStyle(
                fontWeight: FontWeight.w600,
                color: RiffSurfaces.textPrimary,
              ),
              titleSmall: TextStyle(
                color: RiffSurfaces.textMuted,
              ),
              labelMedium: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 22,
                letterSpacing: -0.3,
                color: RiffSurfaces.textPrimary,
              ),
              labelSmall: TextStyle(
                  fontSize: 14,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w600,
                  color: RiffSurfaces.textMuted),
              bodyMedium: TextStyle(color: RiffSurfaces.textMuted)),
          navigationRailTheme: NavigationRailThemeData(
              backgroundColor: RiffSurfaces.voidBlack,
              selectedIconTheme: IconThemeData(
                color: accent,
              ),
              unselectedIconTheme:
                  const IconThemeData(color: RiffSurfaces.textMuted),
              selectedLabelTextStyle: TextStyle(
                  color: accent, fontWeight: FontWeight.w700, fontSize: 14),
              unselectedLabelTextStyle: const TextStyle(
                  color: RiffSurfaces.textMuted, fontWeight: FontWeight.w600)),
          bottomSheetTheme: BottomSheetThemeData(
              backgroundColor: RiffSurfaces.elevated,
              modalBarrierColor: Colors.black.withOpacity(0.55),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              )),
          dialogTheme: const DialogThemeData(
            backgroundColor: RiffSurfaces.elevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: RiffSurfaces.voidBlack,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          sliderTheme: SliderThemeData(
            //base bar color
            inactiveTrackColor: RiffSurfaces.hairline,
            //buffered progress
            activeTrackColor: accent,
            //progress bar color
            valueIndicatorColor: RiffSurfaces.elevatedSoft,
            thumbColor: RiffSurfaces.textPrimary,
          ),
          textSelectionTheme: TextSelectionThemeData(
              cursorColor: accent,
              selectionColor: accent.withOpacity(0.35),
              selectionHandleColor: accent),
          inputDecorationTheme: InputDecorationTheme(
              focusColor: accent,
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: accent))));
      return baseTheme.copyWith(textTheme: _applyBrandFont(baseTheme.textTheme));
    } else {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.dark,
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.white.withOpacity(0.002),
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarContrastEnforced: false),
      );
      final baseTheme = ThemeData(
          useMaterial3: false,
          brightness: Brightness.light,
          canvasColor: const Color(0xFFF7F9F9),
          scaffoldBackgroundColor: const Color(0xFFF7F9F9),
          cardColor: Colors.white,
          dividerColor: const Color(0xFFEFF3F4),
          colorScheme: ColorScheme.fromSwatch(
              accentColor: Colors.grey[500],
              backgroundColor: const Color(0xFFF7F9F9),
              cardColor: Colors.white,
              brightness: Brightness.light),
          primaryColor: Colors.white,
          primaryColorLight: const Color(0xFFEFF3F4),
          progressIndicatorTheme: ProgressIndicatorThemeData(
              linearTrackColor: Colors.grey[700], color: Colors.grey[500]),
          textTheme: TextTheme(
              titleLarge: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
              titleMedium: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
              titleSmall: TextStyle(color: Colors.grey[700]),
              labelMedium: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 22,
                letterSpacing: -0.3,
              ),
              labelSmall: TextStyle(
                  fontSize: 14,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700]),
              bodyMedium: TextStyle(color: Colors.grey[700])),
          navigationRailTheme: NavigationRailThemeData(
              backgroundColor: const Color(0xFFF7F9F9),
              selectedIconTheme: const IconThemeData(color: Colors.black),
              unselectedIconTheme: IconThemeData(color: Colors.grey[700]),
              selectedLabelTextStyle: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
              unselectedLabelTextStyle: TextStyle(
                  color: Colors.grey[700], fontWeight: FontWeight.w600)),
          bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Colors.white,
              modalBarrierColor: Color(0x66000000),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              )),
          sliderTheme: SliderThemeData(
            //base bar color
            inactiveTrackColor: Colors.black26,
            //buffered progress
            activeTrackColor: Colors.grey[800],
            //progress bar color
            valueIndicatorColor: Colors.white38,
            thumbColor: Colors.grey[800],
          ),
          textSelectionTheme: TextSelectionThemeData(
              cursorColor: Colors.grey[500],
              selectionColor: Colors.grey[400],
              selectionHandleColor: Colors.grey[500]),
          dialogTheme: DialogThemeData(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16))),
          inputDecorationTheme: const InputDecorationTheme(
              focusColor: Colors.black,
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.black))));
      return baseTheme.copyWith(textTheme: _applyBrandFont(baseTheme.textTheme));
    }
  }

  MaterialColor _createMaterialColor(Color color) {
    List strengths = <double>[.05];
    Map<int, Color> swatch = {};
    final int r = color.red, g = color.green, b = color.blue;

    for (int i = 1; i < 10; i++) {
      strengths.add(0.1 * i);
    }
    for (var strength in strengths) {
      final double ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    return MaterialColor(color.value, swatch);
  }

  Future<void> setWindowsTitleBarColor(Color color) async {
    if (!GetPlatform.isWindows) return;
    try {
      Future.delayed(
          const Duration(milliseconds: 350),
          () async => await platform.invokeMethod('setTitleBarColor', {
                'r': color.red,
                'g': color.green,
                'b': color.blue,
              }));
    } on PlatformException catch (e) {
      printERROR("Failed to set title bar color: ${e.message}");
    }
  }
}

extension ComplementaryColor on Color {
  Color get complementaryColor => getComplementaryColor(this);
  Color getComplementaryColor(Color color) {
    int r = 255 - color.red;
    int g = 255 - color.green;
    int b = 255 - color.blue;
    return Color.fromARGB(color.alpha, r, g, b);
  }
}

extension ColorWithHSL on Color {
  HSLColor get hsl => HSLColor.fromColor(this);

  Color withSaturation(double saturation) {
    return hsl.withSaturation(clampDouble(saturation, 0.0, 1.0)).toColor();
  }

  Color withLightness(double lightness) {
    return hsl.withLightness(clampDouble(lightness, 0.0, 1.0)).toColor();
  }

  Color withHue(double hue) {
    return hsl.withHue(clampDouble(hue, 0.0, 360.0)).toColor();
  }
}

extension HexColor on Color {
  /// String is in the format "aabbcc" or "ffaabbcc" with an optional leading "#".
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  /// Prefixes a hash sign if [leadingHashSign] is set to `true` (default is `true`).
  String toHex({bool leadingHashSign = true}) => '${leadingHashSign ? '#' : ''}'
      '${alpha.toRadixString(16).padLeft(2, '0')}'
      '${red.toRadixString(16).padLeft(2, '0')}'
      '${green.toRadixString(16).padLeft(2, '0')}'
      '${blue.toRadixString(16).padLeft(2, '0')}';
}

enum ThemeType {
  dynamic,
  system,
  dark,
  light,
}
