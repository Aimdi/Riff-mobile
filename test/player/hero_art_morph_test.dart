import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/components/hero_art_morph.dart';

void main() {
  const thumb = Rect.fromLTWH(24, 11, 40, 40);
  const full = Rect.fromLTWH(0, 0, 412, 478);

  test('starts on the mini player art and ends full-bleed', () {
    expect(HeroArtMorph.rect(0, thumb: thumb, full: full), thumb);
    expect(HeroArtMorph.rect(1, thumb: thumb, full: full), full);
  });

  test('grows steadily as the player opens', () {
    var last = 0.0;
    for (var i = 0; i <= 20; i++) {
      final w = HeroArtMorph.rect(i / 20, thumb: thumb, full: full).width;
      expect(w, greaterThanOrEqualTo(last));
      last = w;
    }
  });

  test('stays big for most of the way down', () {
    final mid = HeroArtMorph.rect(0.5, thumb: thumb, full: full);
    expect(mid.width, greaterThan(full.width * 0.6));
  });

  test('round mini art, square full cover, rounded card between', () {
    expect(HeroArtMorph.radius(0, thumbRadius: 20), 20);
    expect(HeroArtMorph.radius(1, thumbRadius: 20), 0);
    expect(HeroArtMorph.radius(0.5, thumbRadius: 20), greaterThan(15));
  });

  test('page, controls and fade are clear collapsed and full open', () {
    for (final f in [
      HeroArtMorph.pageOpacity,
      HeroArtMorph.controlsOpacity,
      HeroArtMorph.fade,
    ]) {
      expect(f(0), 0);
      expect(f(1), 1);
    }
    // Controls appear after the page has started to.
    expect(HeroArtMorph.controlsOpacity(0.3),
        lessThan(HeroArtMorph.pageOpacity(0.3)));
  });

  test('out-of-range positions are clamped', () {
    expect(HeroArtMorph.rect(-0.2, thumb: thumb, full: full), thumb);
    expect(HeroArtMorph.rect(1.3, thumb: thumb, full: full), full);
  });
}
