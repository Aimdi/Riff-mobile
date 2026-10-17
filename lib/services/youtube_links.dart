/// What a YouTube or YouTube Music link shared to Riff opens: a video's
/// plays, a playlist's, an album's or an artist's page opens, an @handle
/// is looked up. Every form YouTube shares: watch?v=, youtu.be (with ?t=
/// or ?si=), /live/, /embed/, /shorts/, /playlist?list=, /channel/,
/// YouTube Music's /browse/ pages, /@handle, /c/ and /user/.
library;

enum YoutubeLinkKind {
  /// A video to play ([YoutubeLink.id]: its id).
  song,

  /// A playlist's (or an album's, OLAK5uy…) page; a podcast's (MPSP…).
  playlist,

  /// An album's page (MPRE…).
  album,

  /// An artist's (channel's) page (UC…).
  artist,

  /// A channel by its @handle, /c/ or /user/ name, to be looked up.
  handle,

  /// A YouTube Short: not a song.
  short,

  /// Nothing Riff opens.
  invalid,
}

class YoutubeLink {
  const YoutubeLink(this.kind, [this.id = '']);
  final YoutubeLinkKind kind;
  final String id;

  static const invalid = YoutubeLink(YoutubeLinkKind.invalid);
}

const youtubeHosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
  'youtu.be',
};

final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _channelId = RegExp(r'^UC[\w-]{20,}$');

/// What [uri] (a YouTube or YouTube Music link) opens.
YoutubeLink youtubeLinkFrom(Uri uri) {
  if (!youtubeHosts.contains(uri.host.toLowerCase())) {
    return YoutubeLink.invalid;
  }
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final first = segments.isEmpty ? '' : segments.first;
  final second = segments.length > 1 ? segments[1] : '';
  YoutubeLink video(String id) => _videoId.hasMatch(id)
      ? YoutubeLink(YoutubeLinkKind.song, id)
      : YoutubeLink.invalid;

  if (uri.host.toLowerCase() == 'youtu.be') return video(first);
  switch (first) {
    case 'watch':
      return video(uri.queryParameters['v'] ?? '');
    case 'live' || 'embed' || 'v' || 'e':
      return video(second);
    case 'shorts':
      return const YoutubeLink(YoutubeLinkKind.short);
    case 'playlist':
      final list = uri.queryParameters['list'] ?? '';
      return list.isEmpty
          ? YoutubeLink.invalid
          : YoutubeLink(YoutubeLinkKind.playlist, list);
    case 'channel':
      return _channelId.hasMatch(second)
          ? YoutubeLink(YoutubeLinkKind.artist, second)
          : YoutubeLink.invalid;
    // YouTube Music's pages: an album (MPRE…), an artist (UC…), a
    // playlist (VL…), a podcast (MPSP…).
    case 'browse':
      if (second.startsWith('MPRE')) {
        return YoutubeLink(YoutubeLinkKind.album, second);
      }
      if (_channelId.hasMatch(second)) {
        return YoutubeLink(YoutubeLinkKind.artist, second);
      }
      if (second.startsWith('VL') && second.length > 2) {
        return YoutubeLink(YoutubeLinkKind.playlist, second.substring(2));
      }
      if (second.startsWith('MPSP')) {
        return YoutubeLink(YoutubeLinkKind.playlist, second);
      }
      return YoutubeLink.invalid;
    case 'c' || 'user':
      return second.isEmpty
          ? YoutubeLink.invalid
          : YoutubeLink(YoutubeLinkKind.handle, second);
  }
  if (first.startsWith('@') && first.length > 1) {
    return YoutubeLink(YoutubeLinkKind.handle, first.substring(1));
  }
  return YoutubeLink.invalid;
}

final _clock = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?$');

/// Where [uri] starts its video, as YouTube's "Share at 1:23" links say
/// (?t=83, ?t=83s, ?t=1m23s, ?t=1h2m3s, ?start=83 or #t=83); zero when it
/// doesn't.
Duration youtubeLinkStart(Uri uri) {
  final fragment = Uri.splitQueryString(uri.fragment);
  final raw = (uri.queryParameters['t'] ??
          uri.queryParameters['start'] ??
          fragment['t'] ??
          '')
      .trim()
      .toLowerCase();
  if (raw.isEmpty) return Duration.zero;
  final m = _clock.firstMatch(raw);
  if (m == null) return Duration.zero;
  int part(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  return Duration(hours: part(1), minutes: part(2), seconds: part(3));
}
