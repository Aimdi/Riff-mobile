import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '/services/show_notes_links.dart';

/// Show notes whose timestamps play the episode from there ([onTime]) and
/// whose web addresses open ([onLink]), as in Pocket Casts, Spotify and
/// YouTube; both in the accent, as links are (§2.5).
class ShowNotesText extends StatefulWidget {
  const ShowNotesText({
    super.key,
    required this.notes,
    this.onTime,
    required this.onLink,
    this.length,
    this.style,
  });

  final String notes;

  /// The episode's length: timestamps past it stay text.
  final Duration? length;

  /// Null for notes that aren't an episode's: timestamps stay text.
  final void Function(int seconds)? onTime;
  final void Function(String url) onLink;
  final TextStyle? style;

  @override
  State<ShowNotesText> createState() => _ShowNotesTextState();
}

class _ShowNotesTextState extends State<ShowNotesText> {
  List<ShowNotesPart> _parts = const [];

  /// One per timestamp or link, by its index in [_parts].
  final _taps = <int, TapGestureRecognizer>{};

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(ShowNotesText old) {
    super.didUpdateWidget(old);
    if (old.notes != widget.notes || old.length != widget.length) _parse();
  }

  void _parse() {
    _disposeTaps();
    _parts = showNotesParts(widget.notes,
        length: widget.length, times: widget.onTime != null);
    for (var i = 0; i < _parts.length; i++) {
      final part = _parts[i];
      final seconds = part.seconds;
      final url = part.url;
      if (seconds != null) {
        _taps[i] = TapGestureRecognizer()
          ..onTap = () => widget.onTime?.call(seconds);
      } else if (url != null) {
        _taps[i] = TapGestureRecognizer()..onTap = () => widget.onLink(url);
      }
    }
  }

  void _disposeTaps() {
    for (final tap in _taps.values) {
      tap.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _disposeTaps();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    final linkStyle =
        style.copyWith(color: Theme.of(context).colorScheme.primary);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (var i = 0; i < _parts.length; i++)
            _taps[i] == null
                ? TextSpan(text: _parts[i].text)
                : TextSpan(
                    text: _parts[i].text,
                    style: linkStyle,
                    recognizer: _taps[i],
                  ),
        ],
      ),
    );
  }
}
