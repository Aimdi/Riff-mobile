import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '/models/playlist.dart';
import '/ui/theme/palettes/generated_covers.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_theme.dart';
import '/ui/theme/riff_tokens.dart';

/// Artwork for a playlist without a cover of its own: soft, blurred colour
/// blobs flowing into each other, fine film grain, and the playlist's title
/// in bold white at the bottom (Spotify-style generated cover).
///
/// The look is picked from [seed] (the playlist id), so a playlist always
/// gets the same cover and different playlists get different ones. The
/// blobs are drawn once per seed and raster size into an image that is
/// cached ([GeneratedCoverCache]), so scrolling a grid never re-blurs.
class GeneratedCover extends StatelessWidget {
  const GeneratedCover({
    super.key,
    required this.seed,
    required this.title,
    required this.size,
    this.radius = 0,
    this.showTitle,
    this.titleRightInset = 0,
  });

  /// The cover of [playlist] (seeded by its id, else its title).
  GeneratedCover.playlist(
    Playlist playlist, {
    super.key,
    required this.size,
    this.radius = 0,
    this.showTitle,
    this.titleRightInset = 0,
  })  : seed = seedOf(playlist),
        title = playlist.title;

  /// Picks the colours and shapes.
  final String seed;

  /// Printed on covers of at least [RiffCoverArt.titleMinSize].
  final String title;
  final double size;
  final double radius;

  /// Overrides the size rule for the title (e.g. off for a hero backdrop
  /// that has the title under it).
  final bool? showTitle;

  /// Room (dp) kept clear between the title and the cover's right edge,
  /// for a button over the bottom-right corner: the title wraps before it.
  final double titleRightInset;

  /// A playlist's seed: its id, or its title when it has none.
  static String seedOf(Playlist playlist) {
    final id = playlist.playlistId.trim();
    return id.isNotEmpty ? id : playlist.title.trim();
  }

  /// Whether a cover of [size] prints the title.
  static bool titleShownAt(double size) => size >= RiffCoverArt.titleMinSize;

  @override
  Widget build(BuildContext context) {
    final text = title.trim();
    final titled = (showTitle ?? titleShownAt(size)) && text.isNotEmpty;
    Widget art = _GeneratedCoverArt(seed: seed, size: size);
    if (titled) {
      art = Stack(
        fit: StackFit.expand,
        children: [
          art,
          _CoverTitle(
            title: text,
            // In the title's layout units (a titleDesignSize cover).
            rightInset: titleRightInset * RiffCoverArt.titleDesignSize / size,
          ),
        ],
      );
    }
    if (radius > 0) {
      art = ClipRRect(borderRadius: BorderRadius.circular(radius), child: art);
    }
    return RepaintBoundary(
      child: SizedBox.square(dimension: size, child: art),
    );
  }
}

/// The blobs and grain, from the shared cache, at the screen's resolution.
class _GeneratedCoverArt extends StatefulWidget {
  const _GeneratedCoverArt({required this.seed, required this.size});
  final String seed;
  final double size;

  @override
  State<_GeneratedCoverArt> createState() => _GeneratedCoverArtState();
}

class _GeneratedCoverArtState extends State<_GeneratedCoverArt> {
  /// This element's own handle on the cached image (disposed with it).
  ui.Image? _image;
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _GeneratedCoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed || oldWidget.size != widget.size) {
      _sync();
    }
  }

  void _sync() {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final px = GeneratedCoverCache.rasterSizeFor(widget.size * dpr);
    final key = GeneratedCoverCache.keyFor(widget.seed, px);
    if (key == _key && _image != null) return;
    final image = GeneratedCoverCache.obtain(widget.seed, px);
    _image?.dispose();
    _image = image;
    _key = key;
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawImage(
      image: _image,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// How a title is set on a generated cover.
@immutable
class GeneratedCoverTitleFit {
  const GeneratedCoverTitleFit(
      {required this.compact, required this.maxLines, required this.scale});

  /// The compact style instead of the large one.
  final bool compact;
  final int maxLines;

  /// Below 1 when a single word is wider than the cover even in the compact
  /// style: the text shrinks so no word is split.
  final double scale;

  /// Room for the title on a [RiffCoverArt.titleDesignSize] cover.
  static const double fullWidth =
      RiffCoverArt.titleDesignSize - 2 * _CoverTitle._inset;

  static final Map<String, GeneratedCoverTitleFit> _memo = {};
  static const int _memoLimit = 512;

  /// The large style when [title] fits [RiffCoverArt.titleMaxLines] lines
  /// of it without splitting a word, else the compact one over
  /// [RiffCoverArt.titleMaxLinesCompact] lines, shrunk if a word is still
  /// too wide, all within [width]. Memoised: grids rebuild the same titles.
  static GeneratedCoverTitleFit of(
      String title, TextStyle large, TextStyle compact, TextDirection dir,
      {double width = fullWidth}) {
    final key =
        '${large.hashCode}|${compact.hashCode}|${dir.index}|$width|$title';
    final hit = _memo[key];
    if (hit != null) return hit;

    TextPainter painter(String text, TextStyle style, int? lines) =>
        TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: dir,
          maxLines: lines,
          textScaler: TextScaler.noScaling,
        );
    double widestWord(TextStyle style) {
      var widest = 0.0;
      for (final word in title.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final one = painter(word, style, 1)..layout();
        widest = math.max(widest, one.width);
        one.dispose();
      }
      return widest;
    }

    final all = painter(title, large, RiffCoverArt.titleMaxLines)
      ..layout(maxWidth: width);
    final fitsLarge = !all.didExceedMaxLines && widestWord(large) <= width;
    all.dispose();
    final GeneratedCoverTitleFit fit;
    if (fitsLarge) {
      fit = const GeneratedCoverTitleFit(
          compact: false, maxLines: RiffCoverArt.titleMaxLines, scale: 1);
    } else {
      final widest = widestWord(compact);
      fit = GeneratedCoverTitleFit(
        compact: true,
        maxLines: RiffCoverArt.titleMaxLinesCompact,
        scale: widest > width ? width / widest : 1,
      );
    }
    if (_memo.length >= _memoLimit) _memo.clear();
    return _memo[key] = fit;
  }
}

/// The title, laid out on a [RiffCoverArt.titleDesignSize] cover and
/// scaled to the real one, so it wraps the same at every size.
class _CoverTitle extends StatelessWidget {
  const _CoverTitle({required this.title, this.rightInset = 0});
  final String title;

  /// Clear room on the right, in layout units (at least [_inset]).
  final double rightInset;

  static const double _inset = RiffSpacing.md;

  @override
  Widget build(BuildContext context) {
    final styles = RiffTextStyles.of(context);
    final right = math.max(_inset, rightInset);
    final fit = GeneratedCoverTitleFit.of(title, styles.coverTitle,
        styles.coverTitleCompact, Directionality.of(context),
        width: RiffCoverArt.titleDesignSize - _inset - right);
    return ExcludeSemantics(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox.square(
          dimension: RiffCoverArt.titleDesignSize,
          child: Padding(
            padding: EdgeInsets.only(
                left: _inset, top: _inset, right: right, bottom: _inset),
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              child: Text(
                title,
                maxLines: fit.maxLines,
                overflow: TextOverflow.ellipsis,
                // Part of the artwork: it scales with the cover, not with
                // the system text size.
                textScaler: TextScaler.linear(fit.scale),
                style:
                    fit.compact ? styles.coverTitleCompact : styles.coverTitle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small deterministic generator (xorshift32): the same seed gives the same
/// cover on every device and Dart version, unlike `math.Random`.
class _Rng {
  _Rng(int seed) : _state = (seed & _mask) == 0 ? 0x9E3779B9 : seed & _mask {
    // Spread nearby seeds apart before the first draw.
    for (var i = 0; i < 4; i++) {
      _nextInt();
    }
  }

  static const int _mask = 0xFFFFFFFF;
  int _state;

  int _nextInt() {
    var x = _state;
    x ^= (x << 13) & _mask;
    x ^= x >> 17;
    x ^= (x << 5) & _mask;
    _state = x & _mask;
    return _state;
  }

  /// In [0, 1).
  double next() => _nextInt() / 4294967296.0;

  double range(double min, double max) => min + (max - min) * next();
}

/// One soft colour shape of a cover, in unit coordinates (0–1 across).
@immutable
class GeneratedCoverBlob {
  const GeneratedCoverBlob({
    required this.color,
    required this.center,
    required this.radius,
    required this.wobble,
    required this.rotation,
  });

  final Color color;
  final Offset center;

  /// Mean radius, as a share of the cover's side.
  final double radius;

  /// Radius multiplier of each outline point (organic, not a circle).
  final List<double> wobble;

  /// Angle of the first outline point.
  final double rotation;

  /// The closed, smooth outline at [side] pixels.
  Path path(double side) {
    final n = wobble.length;
    final points = [
      for (var i = 0; i < n; i++)
        Offset(
          (center.dx +
                  math.cos(rotation + i * 2 * math.pi / n) *
                      radius *
                      wobble[i]) *
              side,
          (center.dy +
                  math.sin(rotation + i * 2 * math.pi / n) *
                      radius *
                      wobble[i]) *
              side,
        ),
    ];
    // Catmull-Rom through the points, as cubic Béziers.
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 0; i < n; i++) {
      final p0 = points[(i - 1 + n) % n];
      final p1 = points[i];
      final p2 = points[(i + 1) % n];
      final p3 = points[(i + 2) % n];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path..close();
  }

  @override
  bool operator ==(Object other) =>
      other is GeneratedCoverBlob &&
      other.color == color &&
      other.center == center &&
      other.radius == radius &&
      other.rotation == rotation &&
      listEquals(other.wobble, wobble);

  @override
  int get hashCode =>
      Object.hash(color, center, radius, rotation, Object.hashAll(wobble));
}

/// Everything a seed decides: the palette, and the blobs' colours,
/// positions, sizes and shapes.
@immutable
class GeneratedCoverRecipe {
  const GeneratedCoverRecipe({
    required this.paletteIndex,
    required this.base,
    required this.blobs,
  });

  final int paletteIndex;
  final Color base;
  final List<GeneratedCoverBlob> blobs;

  GeneratedCoverPalette get palette => GeneratedCoverPalettes.all[paletteIndex];

  /// FNV-1a over the seed's UTF-16 units: stable across runs and devices
  /// (`String.hashCode` is not).
  static int hashOf(String seed) {
    var h = 0x811C9DC5;
    for (final unit in seed.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// Points on each blob's outline.
  static const int _outline = 7;

  /// Strength of the title shade from the bottom edge up (ease-in).
  static const List<double> _shadeStops = [0, 0.3, 0.6, 1];
  static const List<double> _shadeCurve = [1, 0.55, 0.18, 0];

  factory GeneratedCoverRecipe.forSeed(String seed) {
    final hash = hashOf(seed);
    final paletteIndex = hash % GeneratedCoverPalettes.all.length;
    final p = GeneratedCoverPalettes.all[paletteIndex];
    final rng = _Rng(hash ^ 0x5BD1E995);

    // Which colour gets the bigger field, and the axis the two flow along.
    final primaryLeads = rng.next() < 0.5;
    final angle = rng.range(0, 2 * math.pi);
    final along = Offset(math.cos(angle), math.sin(angle));
    final across = Offset(-along.dy, along.dx);
    final side = rng.next() < 0.5 ? -1.0 : 1.0;
    const mid = Offset(0.5, 0.5);

    GeneratedCoverBlob blob(Color color, Offset center, double radius) =>
        GeneratedCoverBlob(
          color: color,
          center: center,
          radius: radius,
          wobble: [
            for (var i = 0; i < _outline; i++) rng.range(0.72, 1.28),
          ],
          rotation: rng.range(0, 2 * math.pi),
        );

    final leadCenter =
        mid + along * rng.range(0.16, 0.32) + across * rng.range(-0.12, 0.12);
    final otherCenter =
        mid - along * rng.range(0.2, 0.34) + across * rng.range(-0.16, 0.16);
    final lead = primaryLeads ? p.primary : p.secondary;
    final other = primaryLeads ? p.secondary : p.primary;
    final secondaryCenter = primaryLeads ? otherCenter : leadCenter;
    final blobs = [
      // Two big fields of colour on either side of the axis.
      blob(lead, leadCenter, rng.range(0.48, 0.62)),
      blob(other, otherCenter, rng.range(0.38, 0.5)),
      // A deep pool for depth, off to one side.
      blob(p.base, mid + across * (side * rng.range(0.32, 0.46)),
          rng.range(0.2, 0.3)),
      // The lead colour reaching into the other one, so they interleave.
      blob(
          lead,
          otherCenter +
              across * (-side * rng.range(0.2, 0.34)) +
              along * rng.range(-0.08, 0.08),
          rng.range(0.14, 0.2)),
      // A light glow inside the secondary colour.
      blob(
          p.highlight,
          secondaryCenter +
              across * (side * rng.range(0.02, 0.16)) +
              along * rng.range(-0.1, 0.1),
          rng.range(0.1, 0.16)),
    ];
    return GeneratedCoverRecipe(
        paletteIndex: paletteIndex, base: p.base, blobs: blobs);
  }

  /// Paints the cover into the square [side] × [side] at the origin.
  void paint(Canvas canvas, double side) {
    final rect = Offset.zero & Size.square(side);
    final sigma = side * RiffCoverArt.blobBlur;
    canvas.save();
    canvas.clipRect(rect);
    // One blur over all the blobs, edges clamped so the corners keep their
    // colour instead of fading to black.
    canvas.saveLayer(
      rect,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
    );
    canvas.drawRect(rect, Paint()..color = base);
    for (final b in blobs) {
      canvas.drawPath(b.path(side), Paint()..color = b.color);
    }
    canvas.restore();
    // Shade the bottom, where the title sits, easing in from above.
    const shade = GeneratedCoverPalettes.titleShade;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, side),
          Offset(0, side * (1 - RiffCoverArt.titleShadeExtent)),
          [
            for (final f in _shadeCurve)
              shade.withOpacity(RiffCoverArt.titleShadeOpacity * f),
          ],
          _shadeStops,
        ),
    );
    // Film grain.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ImageShader(_Grain.tile, TileMode.repeated,
            TileMode.repeated, Matrix4.identity().storage),
    );
    canvas.restore();
  }

  /// The cover as a [px] × [px] image (rasterised on the GPU, not here).
  ui.Image render(int px) {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder), px.toDouble());
    final picture = recorder.endRecording();
    final image = picture.toImageSync(px, px);
    picture.dispose();
    return image;
  }

  @override
  bool operator ==(Object other) =>
      other is GeneratedCoverRecipe &&
      other.paletteIndex == paletteIndex &&
      other.base == base &&
      listEquals(other.blobs, blobs);

  @override
  int get hashCode => Object.hash(paletteIndex, base, Object.hashAll(blobs));
}

/// A repeating tile of light and dark specks, made once for the app.
class _Grain {
  _Grain._();

  static ui.Image? _tile;
  static ui.Image get tile => _tile ??= _make();

  static ui.Image _make() {
    const n = RiffCoverArt.grainTile;
    final rng = _Rng(0x6A09E667);
    // Two strengths each of light and dark specks.
    final buckets = List.generate(4, (_) => <double>[]);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (rng.next() >= RiffCoverArt.grainDensity) continue;
        buckets[(rng.next() * 4).floor().clamp(0, 3)]
          ..add(x + 0.5)
          ..add(y + 0.5);
      }
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < buckets.length; i++) {
      final light = i < 2;
      final strength = i.isEven ? 1.0 : 0.5;
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(buckets[i]),
        Paint()
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.square
          ..color = (light
                  ? GeneratedCoverPalettes.grainLight
                  : GeneratedCoverPalettes.grainDark)
              .withOpacity(strength *
                  (light
                      ? RiffCoverArt.grainLightOpacity
                      : RiffCoverArt.grainDarkOpacity)),
      );
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(n, n);
    picture.dispose();
    return image;
  }
}

/// Drawn covers by seed and raster size, least recently used dropped first
/// once they pass [RiffCoverArt.cacheBytes]. Callers get their own handle
/// (a clone) and dispose it; the pixels live until the last handle goes.
class GeneratedCoverCache {
  GeneratedCoverCache._();

  static final LinkedHashMap<String, ui.Image> _images =
      LinkedHashMap<String, ui.Image>();
  static int _bytes = 0;

  /// Recipes are cheap but rebuilt per draw otherwise.
  static final Map<String, GeneratedCoverRecipe> _recipes = {};
  static const int _recipeLimit = 512;

  /// The smallest raster size at least [physicalSide] pixels across.
  static int rasterSizeFor(double physicalSide) {
    for (final s in RiffCoverArt.rasterSizes) {
      if (s >= physicalSide) return s;
    }
    return RiffCoverArt.rasterSizes.last;
  }

  static String keyFor(String seed, int px) => '$px|$seed';

  static GeneratedCoverRecipe recipeFor(String seed) {
    final hit = _recipes[seed];
    if (hit != null) return hit;
    if (_recipes.length >= _recipeLimit) _recipes.clear();
    return _recipes[seed] = GeneratedCoverRecipe.forSeed(seed);
  }

  /// A new handle on the cover for [seed] at [px] pixels; dispose it.
  static ui.Image obtain(String seed, int px) {
    final key = keyFor(seed, px);
    var image = _images.remove(key);
    if (image == null) {
      image = recipeFor(seed).render(px);
      _bytes += _sizeOf(image);
    }
    _images[key] = image; // Most recently used last.
    _evict();
    return image.clone();
  }

  static int _sizeOf(ui.Image image) => image.width * image.height * 4;

  static void _evict() {
    while (_bytes > RiffCoverArt.cacheBytes && _images.length > 1) {
      final oldest = _images.keys.first;
      final image = _images.remove(oldest)!;
      _bytes -= _sizeOf(image);
      image.dispose();
    }
  }

  /// Covers currently kept.
  @visibleForTesting
  static int get length => _images.length;

  @visibleForTesting
  static bool contains(String seed, int px) =>
      _images.containsKey(keyFor(seed, px));

  @visibleForTesting
  static void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _recipes.clear();
    _bytes = 0;
  }
}
