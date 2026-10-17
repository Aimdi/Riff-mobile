/// The podcast chapter playing, where the episode shows outside the app:
/// the lock screen, the notification, Android Auto and the home screen
/// widget show the chapter's title in place of the show's name, and its
/// own art when it has some, as Overcast and Apple Podcasts do.
library;

import 'package:audio_service/audio_service.dart';

import '/services/podcast_service.dart' show PodcastChapter, chapterIndexAt;

/// [episode] as it shows [sec] into it, with its [chapters] (by start):
/// the playing chapter's title on its artist line, and the chapter's own
/// art when it has some and [art] is wanted (online: it is fetched);
/// [episode] itself before its first chapter.
MediaItem chapterNowPlaying(
    MediaItem episode, List<PodcastChapter> chapters, double sec,
    {bool art = true}) {
  final i = chapterIndexAt(chapters, sec);
  if (i < 0) return episode;
  final chapter = chapters[i];
  final title = chapter.title.trim();
  final image = art ? Uri.tryParse(chapter.imageUrl ?? '') : null;
  final hasImage =
      image != null && (image.isScheme('https') || image.isScheme('http'));
  return episode.copyWith(
    artist: title.isEmpty ? episode.artist : title,
    artUri: hasImage ? image : episode.artUri,
  );
}

/// What the audio handler announces once told what [shown] should show
/// ([extras]: its `id`, `artist` and `artUri`); null when [shown] is
/// another item by now, or shows that already.
MediaItem? chapterShown(MediaItem? shown, Map<String, dynamic>? extras) {
  if (shown == null || extras == null || shown.id != extras['id']) {
    return null;
  }
  final artist = extras['artist'] as String?;
  final art = extras['artUri'] as String?;
  final artUri = art == null ? null : Uri.tryParse(art);
  if (shown.artist == artist && shown.artUri == artUri) return null;
  return shown.copyWith(artist: artist, artUri: artUri);
}
