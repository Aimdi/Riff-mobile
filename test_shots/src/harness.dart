import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/library_view_mode.dart';
import 'package:harmonymusic/ui/home.dart';
import 'package:harmonymusic/ui/theme/riff_text_metrics.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';
import 'package:harmonymusic/ui/widgets/image_widget.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:hive/hive.dart';

import 'covers.dart';
import 'env.dart';
import 'fakes.dart';
import 'fonts.dart';
import 'media_data.dart';
import 'stores.dart';

/// A screen size the shots are taken at (logical pixels; the PNG is
/// [size] × [dpr]). [top] / [bottom] are the status and navigation bar
/// insets.
class ShotDevice {
  const ShotDevice(this.name, this.size,
      {this.dpr = 2, this.top = 28, this.bottom = 20, this.textScale = 1});
  final String name;
  final Size size;
  final double dpr;
  final double top;
  final double bottom;

  /// The phone's font size (Riff follows it up to 1.3x).
  final double textScale;
}

const phone = ShotDevice('phone', Size(411, 891));
const smallPhone = ShotDevice('small', Size(360, 780));
const tablet = ShotDevice('tablet', Size(900, 1280));

/// The worst case for room: a small phone at the largest font size Riff
/// follows (Android's "Largest", 1.3x).
const largeText = ShotDevice('large', Size(360, 780), textScale: 1.3);

const _rootKey = ValueKey('shotRoot');

/// Once per run: fonts, the in-memory boxes, the plugin stubs, the cover
/// hook and the canned catalogue HTTP.
Future<void> setUpShots() async {
  await loadShotFonts();
  shotTmp = await Directory.systemTemp.createTemp('riff_shots_');
  mockShotPlatform();
  await openShotBoxes();
  // ignore: invalid_use_of_visible_for_testing_member
  RiffNetworkImage.debugImageOverride = shotCover;
  installShotHttp(_catalogueRoutes);
}

Future<void> tearDownShots() async {
  // ignore: invalid_use_of_visible_for_testing_member
  RiffNetworkImage.debugImageOverride = null;
  await Hive.close();
  if (shotTmp.existsSync()) shotTmp.deleteSync(recursive: true);
}

/// The free (LibriVox / archive.org) and store (Apple chart) audiobook
/// catalogues.
Map<String, Object> Function(Uri uri)? _catalogueRoutes(Uri uri) {
  final s = uri.toString();
  if (s.contains('archive.org/advancedsearch.php')) {
    return (_) => ShotBooks.searchJson;
  }
  if (s.contains('archive.org/metadata/')) {
    return (u) => ShotBooks.metadataJson(u.pathSegments.last);
  }
  if (s.contains('topaudiobooks')) return (_) => ShotBooks.chartJson;
  if (s.contains('itunes.apple.com/search')) {
    return (_) => {'results': const []};
  }
  return null;
}

/// Per scenario: fresh data and controllers.
Future<void> setUpScenario() async {
  await seedShotStores();
  // Static state a scenario may have changed (the list / grid switch).
  LibraryViewMode.list.value = false;
  registerShotControllers();
}

Future<void> tearDownScenario() async {
  Get.reset();
}

/// The app as main.dart builds it ([MyApp]): GetMaterialApp with the
/// translations, Riff's page timing, the theme from [ThemeController]
/// (Lights out with the green accent) and the text scale Riff applies.
Widget shotApp(Widget home) {
  final theme = Get.find<ThemeController>().themedata.value!;
  return RepaintBoundary(
    key: _rootKey,
    child: GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Riff',
      transitionDuration: RiffDurations.page,
      translations: Languages(),
      locale: const Locale('en'),
      fallbackLocale: const Locale('en'),
      theme: theme,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: riffTextScaler(mq.textScaler)),
          child: child!,
        );
      },
      home: home,
    ),
  );
}

/// The whole app shell: rail, tab content, the mini player and the
/// (closed) full player panel, as lib/ui/home.dart lays them out.
Widget shotHome() => shotApp(const Home());

/// Sets the test view to [device].
void useDevice(WidgetTester tester, ShotDevice device) {
  tester.view
    ..physicalSize = device.size * device.dpr
    ..devicePixelRatio = device.dpr
    ..padding = FakeViewPadding(
        top: device.top * device.dpr, bottom: device.bottom * device.dpr)
    ..viewPadding = FakeViewPadding(
        top: device.top * device.dpr, bottom: device.bottom * device.dpr);
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = device.textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Lets loading, fades and page transitions finish without waiting for
/// endless animations (pulses, marquees) to settle.
Future<void> settle(WidgetTester tester,
    {Duration total = const Duration(seconds: 2)}) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// Brings what's still moving to rest for the capture: the phone's
/// Remove animations turned on for the last frame, so lines too long for
/// their row show at rest, ellipsized (RiffMarquee), instead of caught
/// mid-scroll, and every run draws the same picture.
/// `--dart-define=SHOT_LIVE_MOTION=true` captures as things are instead.
Future<void> _freezeMotion(WidgetTester tester) async {
  if (const bool.fromEnvironment('SHOT_LIVE_MOTION')) {
    await tester.pump();
    return;
  }
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// The app's root layer as an image at the device's pixel ratio (the
/// stock golden capture is at 1×, too soft to judge type at).
Future<ui.Image> _capture(WidgetTester tester, double dpr) {
  RenderObject box = tester.renderObject(find.byKey(_rootKey));
  while (!box.isRepaintBoundary) {
    box = box.parent!;
  }
  final layer = box.debugLayer! as OffsetLayer;
  return layer.toImage(box.paintBounds, pixelRatio: dpr);
}

/// Errors the frame reported (overflows, exceptions in build) while a
/// scenario ran. Image loads that fail behind the cover hook (palette and
/// pre-cache lookups) are noise and left out.
final _errors = <String>[];

bool _isNoise(FlutterErrorDetails d) {
  final library = d.library ?? '';
  final text = d.exceptionAsString();
  return library.contains('image resource service') ||
      text.contains('HttpException') ||
      text.contains('MissingPluginException') ||
      text.contains('SocketException');
}

/// Runs one screenshot scenario: [device] size, real shadows, errors
/// collected rather than thrown until the PNG is written, timers drained
/// at the end so a pending delay doesn't fail the next scenario.
///
/// [body] pumps and arranges the screen; then the whole app is written to
/// test_shots/out/[name].png (with `--update-goldens`).
Future<void> runShot(
  WidgetTester tester,
  String name,
  ShotDevice device,
  Future<void> Function() body,
) async {
  // Another accent's shots sit beside the green ones: home_phone_blue.png.
  if (shotAccentName.isNotEmpty && shotAccentName != 'Green') {
    name = '${name}_${shotAccentName.toLowerCase()}';
  }
  useDevice(tester, device);
  final onError = FlutterError.onError;
  _errors.clear();
  FlutterError.onError = (d) {
    // Described now, while the widgets it names are still mounted; the
    // message and the widget, not the whole stack.
    if (_isNoise(d)) return;
    final lines = d.toString(minLevel: DiagnosticLevel.info).split('\n');
    final stack = lines.indexWhere((l) => l.startsWith('#'));
    _errors.add(lines.take(stack < 0 ? 30 : stack.clamp(0, 30)).join('\n'));
  };
  try {
    debugDisableShadows = false;
    try {
      await body();
      await _freezeMotion(tester);
      await expectLater(
          _capture(tester, device.dpr), matchesGoldenFile('out/$name.png'));
    } finally {
      debugDisableShadows = true;
      // Unmount (also when the scenario failed, so its routes go now and
      // not under the next one) and run out the timers (debounces,
      // delayed refreshes).
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    }
  } finally {
    FlutterError.onError = onError;
  }
  final log = File('${_outDir()}/$name.errors.txt');
  if (_errors.isEmpty) {
    if (log.existsSync()) log.deleteSync();
    return;
  }
  final report = _errors.join('\n\n');
  log.writeAsStringSync('$report\n');
  final summary = '$name: ${_errors.length} error(s) while rendering '
      '(see out/$name.errors.txt)';
  if (_strict) fail('$summary:\n$report');
  final gist = _errors.map((e) => e.split('\n').take(4).join('\n'));
  // ignore: avoid_print
  print('WARNING $summary:\n${gist.join('\n')}');
}

/// `--dart-define=SHOT_STRICT=true`: a scenario that reports errors
/// (overflow, an exception in build) fails instead of only warning.
const _strict = bool.fromEnvironment('SHOT_STRICT');

/// test_shots/out, next to the goldens.
String _outDir() {
  final dir = Directory(
      '${(goldenFileComparator as LocalFileComparator).basedir.toFilePath()}out');
  dir.createSync(recursive: true);
  return dir.path;
}
