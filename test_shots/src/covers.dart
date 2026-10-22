import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Stand-in cover art for the screenshots: network images can't load in
/// widget tests, so every cover URL gets a gradient with a soft shape,
/// picked from a hash of the URL. The same item looks the same at every
/// size and in every shot; different items look different.
Widget shotCover(String url, double? width, double? height) {
  final seed = _fnv1a(coverSeedKey(url));
  // One side given (a header fitting the cover to the screen's width):
  // the other follows from the picture's shape, as a downloaded image's
  // would. YouTube video frames are 16:9, covers square.
  final aspect = url.contains('ytimg.com/vi/') ? 16 / 9 : 1.0;
  final w = width ?? (height != null ? height * aspect : null);
  final h = height ?? (width != null ? width / aspect : null);
  return SizedBox(
    width: w,
    height: h,
    // Unsized and unbounded (rare): a thumbnail-sized square.
    child: LimitedBox(
      maxWidth: 160,
      maxHeight: 160,
      child: SizedBox.expand(
        child: CustomPaint(painter: _CoverPainter(seed)),
      ),
    ),
  );
}

/// The two colours [shotCover] paints [url] with, light one first: what
/// a palette taken from that cover would find.
(Color, Color) shotCoverColors(String url) {
  final pair = _palettes[_fnv1a(coverSeedKey(url)) % _palettes.length];
  return (pair[0], pair[1]);
}

/// The part of a cover URL that names the picture, without the size the
/// app asked for (`=w544-h544…`, `/600x600bb.jpg`, `?w=…`, YouTube's
/// `hqdefault.jpg`), so every size of one cover gets the same art.
String coverSeedKey(String url) {
  var key = url.trim();
  final query = key.indexOf('?');
  if (query >= 0) key = key.substring(0, query);
  final eq = key.indexOf('=');
  if (eq >= 0) key = key.substring(0, eq);
  key = key.replaceFirst(RegExp(r'/\d+x\d+[a-z]*\.(jpg|jpeg|png|webp)$'), '');
  key = key.replaceFirst(
      RegExp(r'/(maxres|hq720|sd|hq|mq)?default\.(jpg|webp)$'), '');
  return key;
}

int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// Gradient pairs that read as album art on a black page: saturated but
/// not neon, light enough to stand off the background.
const _palettes = <List<Color>>[
  [Color(0xFFFF7E5F), Color(0xFFB0306A)],
  [Color(0xFF43C6AC), Color(0xFF191654)],
  [Color(0xFFF7B733), Color(0xFFFC4A1A)],
  [Color(0xFF7F7FD5), Color(0xFF3D2C8D)],
  [Color(0xFF56CCF2), Color(0xFF2F80ED)],
  [Color(0xFFEE9CA7), Color(0xFF6A3093)],
  [Color(0xFF11998E), Color(0xFF38EF7D)],
  [Color(0xFFE96443), Color(0xFF904E95)],
  [Color(0xFFDCE35B), Color(0xFF45B649)],
  [Color(0xFF834D9B), Color(0xFFD04ED6)],
  [Color(0xFFFFB88C), Color(0xFFDE6262)],
  [Color(0xFF4CA1AF), Color(0xFF2C3E50)],
  [Color(0xFFF3904F), Color(0xFF3B4371)],
  [Color(0xFFA8E063), Color(0xFF2B6F4A)],
  [Color(0xFFC94B4B), Color(0xFF4B134F)],
  [Color(0xFFFFD86F), Color(0xFFFC6262)],
  [Color(0xFF6DD5ED), Color(0xFF2193B0)],
  [Color(0xFFB993D6), Color(0xFF8CA6DB)],
  [Color(0xFFF0C27B), Color(0xFF4B1248)],
  [Color(0xFF00B4DB), Color(0xFF0B3C5D)],
];

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.seed);
  final int seed;

  int _bits(int shift, int mod) => ((seed >> shift) & 0xff) % mod;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final pair = _palettes[seed % _palettes.length];
    final flip = _bits(5, 2) == 1;
    final a = flip ? pair[1] : pair[0];
    final b = flip ? pair[0] : pair[1];
    final angle = _bits(8, 8) * math.pi / 4;
    final begin = Alignment(math.cos(angle), math.sin(angle));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(begin: begin, end: -begin, colors: [a, b])
              .createShader(rect));

    final s = size.shortestSide;
    final light = Colors.white.withOpacity(0.18);
    final dark = Colors.black.withOpacity(0.16);
    final cx = size.width * (0.25 + _bits(12, 50) / 100);
    final cy = size.height * (0.25 + _bits(16, 50) / 100);
    switch (_bits(20, 5)) {
      case 0: // one large soft disc
        canvas.drawCircle(Offset(cx, cy), s * 0.42, Paint()..color = light);
        canvas.drawCircle(
            Offset(cx, cy), s * 0.22, Paint()..color = light.withOpacity(0.12));
      case 1: // concentric rings
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.035
          ..color = light;
        for (var i = 1; i <= 4; i++) {
          canvas.drawCircle(Offset(cx, cy), s * 0.12 * i, ring);
        }
      case 2: // diagonal bands
        canvas.save();
        canvas.clipRect(rect);
        canvas.translate(size.width / 2, size.height / 2);
        canvas.rotate(-math.pi / 5);
        for (var i = -3; i <= 3; i++) {
          canvas.drawRect(Rect.fromLTWH(-s, i * s * 0.22, s * 2, s * 0.08),
              Paint()..color = i.isEven ? light : dark);
        }
        canvas.restore();
      case 3: // two overlapping discs
        canvas.drawCircle(Offset(size.width * 0.35, size.height * 0.62),
            s * 0.3, Paint()..color = light);
        canvas.drawCircle(Offset(size.width * 0.65, size.height * 0.4), s * 0.3,
            Paint()..color = dark);
      default: // a sun on the horizon
        final horizon = size.height * 0.64;
        canvas.drawCircle(Offset(size.width / 2, horizon), s * 0.26,
            Paint()..color = Colors.white.withOpacity(0.28));
        canvas.drawRect(Rect.fromLTRB(0, horizon, size.width, size.height),
            Paint()..color = dark.withOpacity(0.3));
        final line = Paint()
          ..color = Colors.white.withOpacity(0.14)
          ..strokeWidth = s * 0.02;
        for (var i = 1; i <= 3; i++) {
          final y = horizon + i * s * 0.07;
          canvas.drawLine(Offset(size.width * 0.15 * i, y),
              Offset(size.width * (1 - 0.15 * i), y), line);
        }
    }

    // A little depth at the bottom, as printed sleeves have.
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withOpacity(0.22)],
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(_CoverPainter oldDelegate) => oldDelegate.seed != seed;
}
