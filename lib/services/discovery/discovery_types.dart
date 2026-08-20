// Shared types / enums for the discovery engine.
// Pure Dart — no Flutter imports.

/// How a track entered the queue / was started.
///
/// Stored on [MediaItem.extras] as `discoverySource` using [wireName].
/// Allowed wire values:
/// `user_click`, `home`, `search`, `playlist`, `album`, `artist`,
/// `radio`, `daily_mix`, `fresh_finds`, `discover`, `related`, `similar`,
/// `queue`, `shuffle`, `smart_shuffle`, `android_auto`, `cloud`,
/// `podcast`, `audiobook`, `downloads`, `soulseek`, `torrent`, `unknown`.
enum DiscoverySource {
  userClick,
  home,
  search,
  playlist,
  album,
  artist,
  radio,
  dailyMix,
  freshFinds,
  discover,
  related,
  similar,
  queue,
  shuffle,
  androidAuto,
  smartShuffle,
  cloud,
  podcast,
  audiobook,
  downloads,
  soulseek,
  torrent,
  unknown;

  String get wireName {
    switch (this) {
      case DiscoverySource.userClick:
        return 'user_click';
      case DiscoverySource.home:
        return 'home';
      case DiscoverySource.search:
        return 'search';
      case DiscoverySource.playlist:
        return 'playlist';
      case DiscoverySource.album:
        return 'album';
      case DiscoverySource.artist:
        return 'artist';
      case DiscoverySource.radio:
        return 'radio';
      case DiscoverySource.dailyMix:
        return 'daily_mix';
      case DiscoverySource.freshFinds:
        return 'fresh_finds';
      case DiscoverySource.discover:
        return 'discover';
      case DiscoverySource.related:
        return 'related';
      case DiscoverySource.similar:
        return 'similar';
      case DiscoverySource.queue:
        return 'queue';
      case DiscoverySource.shuffle:
        return 'shuffle';
      case DiscoverySource.androidAuto:
        return 'android_auto';
      case DiscoverySource.smartShuffle:
        return 'smart_shuffle';
      case DiscoverySource.cloud:
        return 'cloud';
      case DiscoverySource.podcast:
        return 'podcast';
      case DiscoverySource.audiobook:
        return 'audiobook';
      case DiscoverySource.downloads:
        return 'downloads';
      case DiscoverySource.soulseek:
        return 'soulseek';
      case DiscoverySource.torrent:
        return 'torrent';
      case DiscoverySource.unknown:
        return 'unknown';
    }
  }

  static DiscoverySource fromWire(String? s) {
    switch (s) {
      case 'user_click':
        return DiscoverySource.userClick;
      case 'home':
        return DiscoverySource.home;
      case 'search':
        return DiscoverySource.search;
      case 'playlist':
        return DiscoverySource.playlist;
      case 'album':
        return DiscoverySource.album;
      case 'artist':
        return DiscoverySource.artist;
      case 'radio':
        return DiscoverySource.radio;
      case 'daily_mix':
        return DiscoverySource.dailyMix;
      case 'fresh_finds':
        return DiscoverySource.freshFinds;
      case 'discover':
        return DiscoverySource.discover;
      case 'related':
        return DiscoverySource.related;
      case 'similar':
        return DiscoverySource.similar;
      case 'queue':
        return DiscoverySource.queue;
      case 'shuffle':
        return DiscoverySource.shuffle;
      case 'android_auto':
        return DiscoverySource.androidAuto;
      case 'smart_shuffle':
        return DiscoverySource.smartShuffle;
      case 'cloud':
        return DiscoverySource.cloud;
      case 'podcast':
        return DiscoverySource.podcast;
      case 'audiobook':
        return DiscoverySource.audiobook;
      case 'downloads':
        return DiscoverySource.downloads;
      case 'soulseek':
        return DiscoverySource.soulseek;
      case 'torrent':
        return DiscoverySource.torrent;
      default:
        return DiscoverySource.unknown;
    }
  }

  /// Intentional start (search, album tap, enqueue) vs engine-picked radio.
  bool get isUserInitiated {
    switch (this) {
      case DiscoverySource.userClick:
      case DiscoverySource.home:
      case DiscoverySource.search:
      case DiscoverySource.playlist:
      case DiscoverySource.album:
      case DiscoverySource.artist:
      case DiscoverySource.queue:
      case DiscoverySource.downloads:
      case DiscoverySource.cloud:
      case DiscoverySource.podcast:
      case DiscoverySource.audiobook:
      case DiscoverySource.soulseek:
      case DiscoverySource.torrent:
        return true;
      case DiscoverySource.radio:
      case DiscoverySource.dailyMix:
      case DiscoverySource.freshFinds:
      case DiscoverySource.discover:
      case DiscoverySource.related:
      case DiscoverySource.similar:
      case DiscoverySource.shuffle:
      case DiscoverySource.androidAuto:
      case DiscoverySource.smartShuffle:
      case DiscoverySource.unknown:
        return false;
    }
  }
}

/// Logged event kinds.
enum DiscoveryEventKind {
  playStarted,
  playEnded,
  skip,
  quickSkip,
  favorite,
  unfavorite,
  playlistAdd,
  download,
  follow,
  unfollow,
  thumbsUp,
  thumbsDown,
  dismiss,
  neverPlay,
  impression;

  String get wireName {
    switch (this) {
      case DiscoveryEventKind.playStarted:
        return 'play_started';
      case DiscoveryEventKind.playEnded:
        return 'play_ended';
      case DiscoveryEventKind.skip:
        return 'skip';
      case DiscoveryEventKind.quickSkip:
        return 'quick_skip';
      case DiscoveryEventKind.favorite:
        return 'favorite';
      case DiscoveryEventKind.unfavorite:
        return 'unfavorite';
      case DiscoveryEventKind.playlistAdd:
        return 'playlist_add';
      case DiscoveryEventKind.download:
        return 'download';
      case DiscoveryEventKind.follow:
        return 'follow';
      case DiscoveryEventKind.unfollow:
        return 'unfollow';
      case DiscoveryEventKind.thumbsUp:
        return 'thumbs_up';
      case DiscoveryEventKind.thumbsDown:
        return 'thumbs_down';
      case DiscoveryEventKind.dismiss:
        return 'dismiss';
      case DiscoveryEventKind.neverPlay:
        return 'never_play';
      case DiscoveryEventKind.impression:
        return 'impression';
    }
  }

  static DiscoveryEventKind fromWire(String? s) {
    switch (s) {
      case 'play_started':
        return DiscoveryEventKind.playStarted;
      case 'play_ended':
        return DiscoveryEventKind.playEnded;
      case 'skip':
        return DiscoveryEventKind.skip;
      case 'quick_skip':
        return DiscoveryEventKind.quickSkip;
      case 'favorite':
        return DiscoveryEventKind.favorite;
      case 'unfavorite':
        return DiscoveryEventKind.unfavorite;
      case 'playlist_add':
        return DiscoveryEventKind.playlistAdd;
      case 'download':
        return DiscoveryEventKind.download;
      case 'follow':
        return DiscoveryEventKind.follow;
      case 'unfollow':
        return DiscoveryEventKind.unfollow;
      case 'thumbs_up':
        return DiscoveryEventKind.thumbsUp;
      case 'thumbs_down':
        return DiscoveryEventKind.thumbsDown;
      case 'dismiss':
        return DiscoveryEventKind.dismiss;
      case 'never_play':
        return DiscoveryEventKind.neverPlay;
      case 'impression':
        return DiscoveryEventKind.impression;
      default:
        return DiscoveryEventKind.playEnded;
    }
  }
}

/// Discovery surfaces (for impressions + skip fingerprints).
class DiscoverySurface {
  static const String home = 'home';
  static const String similar = 'similar';
  static const String radio = 'radio';
  static const String dailyMix = 'daily_mix';
  static const String freshFinds = 'fresh_finds';
  static const String releaseRadar = 'release_radar';
  static const String rediscover = 'rediscover';
  static const String smartShuffle = 'smart_shuffle';
  static const String playlistSuggest = 'playlist_suggest';
  static const String likedSuggest = 'liked_suggest';
  static const String becauseYouLiked = 'because_you_liked';
  static const String fansAlsoLike = 'fans_also_like';
}

/// Playlist kind flags for system-generated mixes.
class MixKind {
  static const String dailyMix = 'daily_mix';
  static const String freshFinds = 'fresh_finds';
  static const String releaseRadar = 'release_radar';
  static const String rediscover = 'rediscover';
}

/// Lightweight event record (serialized to Hive).
class DiscoveryEvent {
  DiscoveryEvent({
    required this.videoId,
    required this.artistKey,
    required this.ts,
    required this.source,
    required this.event,
    this.fraction,
    this.surface,
    this.title,
    this.artist,
  });

  final String videoId;
  final String artistKey;
  final int ts; // ms since epoch
  final DiscoverySource source;
  final DiscoveryEventKind event;
  final double? fraction;
  final String? surface;
  final String? title;
  final String? artist;

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'artistKey': artistKey,
        'ts': ts,
        'source': source.wireName,
        'event': event.wireName,
        if (fraction != null) 'fraction': fraction,
        if (surface != null) 'surface': surface,
        if (title != null) 'title': title,
        if (artist != null) 'artist': artist,
      };

  factory DiscoveryEvent.fromJson(Map map) => DiscoveryEvent(
        videoId: map['videoId'] as String? ?? '',
        artistKey: map['artistKey'] as String? ?? '',
        ts: map['ts'] as int? ?? 0,
        source: DiscoverySource.fromWire(map['source'] as String?),
        event: DiscoveryEventKind.fromWire(map['event'] as String?),
        fraction: (map['fraction'] as num?)?.toDouble(),
        surface: map['surface'] as String?,
        title: map['title'] as String?,
        artist: map['artist'] as String?,
      );
}

/// A named home/discover section of tracks.
class DiscoverySection {
  DiscoverySection({
    required this.id,
    required this.title,
    required this.reason,
    required this.tracks,
    this.subtitle,
    this.surface = DiscoverySurface.home,
  });

  final String id;
  final String title;
  final String reason;
  final String? subtitle;
  final List<Map<String, dynamic>> tracks; // MediaItem JSON maps
  final String surface;
}

/// Generated mix metadata + track list (JSON MediaItems).
class GeneratedMix {
  GeneratedMix({
    required this.id,
    required this.title,
    required this.reason,
    required this.kind,
    required this.tracks,
    required this.generatedTs,
  });

  final String id;
  final String title;
  final String reason;
  final String kind;
  final List<Map<String, dynamic>> tracks;
  final int generatedTs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'reason': reason,
        'kind': kind,
        'tracks': tracks,
        'generatedTs': generatedTs,
      };

  factory GeneratedMix.fromJson(Map map) => GeneratedMix(
        id: map['id'] as String? ?? '',
        title: map['title'] as String? ?? '',
        reason: map['reason'] as String? ?? '',
        kind: map['kind'] as String? ?? MixKind.dailyMix,
        tracks: List<Map<String, dynamic>>.from(
            (map['tracks'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map))),
        generatedTs: map['generatedTs'] as int? ?? 0,
      );
}

/// Candidate with scoring metadata before constraint re-rank.
class ScoredCandidate {
  ScoredCandidate({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.artistKey,
    required this.score,
    required this.mediaJson,
    this.reason = '',
  });

  final String videoId;
  final String title;
  final String artist;
  final String artistKey;
  double score;
  final Map<String, dynamic> mediaJson;
  String reason;
}
