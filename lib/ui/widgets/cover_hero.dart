import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A cover that flies from the card you tapped to the page it opens, as
/// Apple Music's and Spotify's covers do.
///
/// The card wraps its cover in a [CoverHero] tagged with its own
/// [BuildContext] (one per card, the same across rebuilds, so an album on
/// two shelves never shares a tag), and calls [CoverHero.launch] with it
/// just before opening the page. The page takes the tag
/// ([CoverHero.take]) for its own cover; back, the cover flies home.
class CoverHero extends StatelessWidget {
  const CoverHero({super.key, required this.tag, required this.child});

  /// Null: just [child], nothing flies.
  final Object? tag;
  final Widget child;

  static Object? _pending;

  /// The page opened next takes [tag]; it's forgotten after that frame,
  /// so a page opened later some other way doesn't.
  static void launch(Object tag) {
    _pending = tag;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _pending = null)
      // That frame comes even if nothing opens.
      ..ensureVisualUpdate();
  }

  /// The tag of the cover that's flying in, once (null: none is).
  static Object? take() {
    final tag = _pending;
    _pending = null;
    return tag;
  }

  @override
  Widget build(BuildContext context) {
    final tag = this.tag;
    if (tag == null) return child;
    return Hero(tag: tag, child: child);
  }
}
