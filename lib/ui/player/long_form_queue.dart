import 'package:audio_service/audio_service.dart';

/// Full show notes of episodes whose queue copy was shortened by
/// [prepareLongFormQueue], keyed by episode id.
final Map<String, String> _fullNotes = <String, String>{};

/// The episode's show notes: the full text when the queue copy was
/// shortened, else whatever the item carries.
String episodeNotes(MediaItem? item) {
  if (item == null) return '';
  return _fullNotes[item.id] ?? '${item.extras?['description'] ?? ''}';
}

/// Podcast queues are sent to Android's media session, which copies every
/// item and its text extras across processes. A show with thousands of
/// daily episodes, each with kilobytes of show notes, overflows that
/// transaction and crashes the app. Keep a window of [max] episodes around
/// [index] and shorten notes over [notesMax] characters (the full text stays
/// available through [episodeNotes]).
({List<MediaItem> items, int index}) prepareLongFormQueue(
  List<MediaItem> items,
  int index, {
  int max = 120,
  int notesMax = 600,
}) {
  var start = 0;
  var end = items.length;
  if (items.length > max) {
    start = (index - 10).clamp(0, items.length);
    end = (start + max).clamp(0, items.length);
    start = (end - max).clamp(0, items.length);
  }
  final window = <MediaItem>[];
  for (var i = start; i < end; i++) {
    final m = items[i];
    final notes = m.extras?['description'];
    if (notes is String && notes.length > notesMax) {
      if (_fullNotes.length > 600) _fullNotes.clear();
      _fullNotes[m.id] = notes;
      window.add(m.copyWith(extras: {
        ...?m.extras,
        'description': '${notes.substring(0, notesMax)}…',
      }));
    } else {
      window.add(m);
    }
  }
  return (items: window, index: index - start);
}
