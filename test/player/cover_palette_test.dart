import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/components/cover_palette.dart';

double _contrastWithWhite(Color c) => 1.05 / (c.computeLuminance() + 0.05);

double _hue(Color c) => HSLColor.fromColor(c).hue;

void main() {
  group('coverPaletteFrom', () {
    // Royal blue from the reference player's page.
    const blue = Color(0xFF291AA7);

    test('keeps a dark cover colour as it is', () {
      final p = coverPaletteFrom(dominant: blue);
      expect(_hue(p.fill), closeTo(_hue(blue), 1));
      expect(HSLColor.fromColor(p.fill).lightness, closeTo(0.38, 0.03));
    });

    test('white text reads on the fill for any cover', () {
      for (final c in [
        Colors.white,
        Colors.yellow,
        const Color(0xFFFFE082),
        Colors.cyanAccent,
        Colors.lightGreenAccent,
        Colors.pink.shade100,
        Colors.black,
        blue,
      ]) {
        final p = coverPaletteFrom(dominant: c);
        expect(_contrastWithWhite(p.fill), greaterThanOrEqualTo(6),
            reason: 'fill for $c is ${p.fill}');
        expect(_contrastWithWhite(p.deep), greaterThan(_contrastWithWhite(p.fill)),
            reason: 'bottom edge is darker than the fill');
      }
    });

    test('a black cover still gets a little colour, not pure black', () {
      final p = coverPaletteFrom(dominant: Colors.black);
      expect(p.fill, isNot(Colors.black));
    });

    test('glow uses the second colour when it stands apart', () {
      const magenta = Color(0xFFA9429D);
      final p = coverPaletteFrom(dominant: blue, secondary: magenta);
      expect(_hue(p.glow), closeTo(_hue(magenta), 2));
    });

    test('glow is shifted off the fill when the second colour matches it', () {
      final p = coverPaletteFrom(
          dominant: blue, secondary: const Color(0xFF3020B0));
      final d = (_hue(p.glow) - _hue(p.fill)).abs() % 360;
      expect(d > 180 ? 360 - d : d, closeTo(CoverTone.glowHueShift, 1));
    });
  });
}
