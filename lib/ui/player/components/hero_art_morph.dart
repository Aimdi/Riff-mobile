import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// The minimise / expand animation of the music player: the full-bleed
/// cover shrinks into a rounded card that lands on the mini player's
/// artwork (and grows back out of it), while the page behind fades in.
///
/// [progress] is the player panel's position: 1 fully open, 0 collapsed to
/// the mini player.
class HeroArtMorph {
  HeroArtMorph._();

  /// Size follows an ease-out of the panel position, so the cover stays
  /// big for most of the way down and shrinks quickly at the end.
  static double eased(double progress) =>
      Curves.easeOut.transform(progress.clamp(0.0, 1.0));

  /// Where the cover is at [progress], between [thumb] (the mini player's
  /// art) and [full] (the full-bleed cover).
  static Rect rect(double progress, {required Rect thumb, required Rect full}) =>
      Rect.lerp(thumb, full, eased(progress))!;

  /// Corner radius: the mini art's own at 0, square at 1, and rounder in
  /// between so the travelling cover reads as a card.
  static double radius(double progress,
      {required double thumbRadius, double cardRadius = 22}) {
    final e = eased(progress);
    return lerpDouble(thumbRadius, 0, e)! + cardRadius * 4 * e * (1 - e);
  }

  /// How far the cover's bottom fades into the page (0 = not at all).
  /// Only near the top, so the moving card keeps its sharp edges.
  static double fade(double progress) =>
      math.pow(eased(progress), 3).toDouble();

  /// Page colour, title and controls: gone in the bottom part of the
  /// travel so the screen behind shows through, like a lifted sheet.
  static double pageOpacity(double progress) =>
      const Interval(0.08, 0.6, curve: Curves.easeOut)
          .transform(progress.clamp(0.0, 1.0));

  static double controlsOpacity(double progress) =>
      const Interval(0.3, 0.85, curve: Curves.easeOut)
          .transform(progress.clamp(0.0, 1.0));
}
