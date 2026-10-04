import 'package:flutter/material.dart';

/// Artwork for something without a cover: a gradient picked from the
/// title, with its first letter. Used instead of a generic music-note
/// icon, so a missing cover still tells items apart.
class LetterArt extends StatelessWidget {
  const LetterArt({
    super.key,
    required this.title,
    required this.size,
    this.radius = 0,
    this.circle = false,
  });

  final String title;
  final double size;
  final double radius;
  final bool circle;

  /// The letter shown: the first letter or digit of [title], upper-cased;
  /// '#' when the title has none.
  static String initialOf(String title) {
    for (final rune in title.runes) {
      final c = String.fromCharCode(rune);
      if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c)) {
        return c.toUpperCase();
      }
    }
    return '#';
  }

  /// Two colours derived from [title], stable across runs.
  static List<Color> gradientFor(String title) {
    var h = 0;
    for (final unit in title.codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff;
    }
    final hue = (h % 360).toDouble();
    return [
      HSLColor.fromAHSL(1, hue, 0.55, 0.32).toColor(),
      HSLColor.fromAHSL(1, (hue + 40) % 360, 0.65, 0.52).toColor(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientFor(title),
        ),
      ),
      child: ExcludeSemantics(
        child: Text(
          initialOf(title),
          style: TextStyle(
            color: Colors.white.withOpacity(0.92),
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}
