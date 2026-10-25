import 'package:flutter/material.dart';

import '/ui/theme/riff_tokens.dart';
import '../../widgets/image_widget.dart';
import 'home_feed_builder.dart';

/// The picture beside a shelf's header, as YouTube Music and Spotify draw
/// it: the artist a shelf is like (round), the song it grew from (a small
/// cover). Decorative: the header's text says the same.
class ShelfHeaderArt extends StatelessWidget {
  const ShelfHeaderArt({super.key, required this.url, this.round = false});

  final String url;
  final bool round;

  /// [shelf]'s picture, or null when it has none.
  static Widget? of(HomeShelfData shelf) {
    final url = shelf.headerArt;
    if (url == null || url.isEmpty) return null;
    return ShelfHeaderArt(url: url, round: shelf.headerArtRound);
  }

  @override
  Widget build(BuildContext context) {
    const size = RiffComponentSizes.shelfHeaderArt;
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    final image = RiffNetworkImage(
      imageUrl: url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      memCacheWidth: px,
      placeholder: (_, __) => ColoredBox(color: fill),
      errorWidget: (_, __, ___) => ColoredBox(color: fill),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: round
            ? ClipOval(child: image)
            : ClipRRect(
                borderRadius: BorderRadius.circular(RiffRadii.xs),
                child: image),
      ),
    );
  }
}
