import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/album.dart';
import '/models/artist.dart';
import '/models/home_shelf_content.dart';
import '/models/media_Item_builder.dart';
import '/models/media_item_extras.dart';
import '/models/playlist.dart';
import '/models/thumbnail.dart';
import '/services/audiobook_progress_service.dart';
import '/services/discovery/discovery_service.dart';
import '/services/podcast_progress_service.dart';
import '/services/podcast_service.dart';
import '/services/stats_service.dart';
import '/ui/player/player_controller.dart';
import 'home_feed_builder.dart';
import 'home_screen_controller.dart';
import 'podcast_continue.dart';

/// What a Jump back in tile resumes.
enum ResumeKind { session, episode, book }

class HomeResumable {
  const HomeResumable({
    required this.kind,
    required this.id,
    required this.title,
    this.art,
    this.progress,
    this.record,
  });

  final ResumeKind kind;

  /// Episode / track id, or the book id.
  final String id;
  final String title;

  /// Item whose cover the tile shows.
  final MediaItem? art;

  /// 0..1 listened (episodes and books).
  final double? progress;

  /// The stored progress row (books need it to resume).
  final Map<String, dynamic>? record;
}

/// A subscribed show on the personalized shelf.
class HomeShow {
  const HomeShow(this.data);
  final Map<String, dynamic> data;
  String get title => '${data['title'] ?? ''}';
  String get author => '${data['author'] ?? ''}';
  String get artwork => '${data['artwork'] ?? ''}';
  String get feedUrl => '${data['feedUrl'] ?? ''}';
}

/// Something pinned to Speed dial from a shelf's long-press menu.
class SpeedDialPin {
  const SpeedDialPin({
    required this.type,
    required this.id,
    required this.title,
    this.art = '',
  });

  /// album / playlist / artist.
  final String type;
  final String id;
  final String title;
  final String art;

  String get key => '$type:$id';

  Map<String, dynamic> toJson() =>
      {'type': type, 'id': id, 'title': title, 'art': art};

  static SpeedDialPin? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final type = '${raw['type'] ?? ''}';
    final id = '${raw['id'] ?? ''}';
    if (id.isEmpty || !const {'album', 'playlist', 'artist'}.contains(type)) {
      return null;
    }
    return SpeedDialPin(
        type: type,
        id: id,
        title: '${raw['title'] ?? ''}',
        art: '${raw['art'] ?? ''}');
  }

  /// A pin for a shelf item, or null when it can't be pinned.
  static SpeedDialPin? of(Object? value) {
    if (value is Album) {
      return SpeedDialPin(
          type: 'album',
          id: value.browseId,
          title: value.title,
          art: value.thumbnailUrl);
    }
    if (value is Playlist) {
      return SpeedDialPin(
          type: 'playlist',
          id: value.playlistId,
          title: value.title,
          art: value.thumbnailUrl == Playlist.thumbPlaceholderUrl
              ? ''
              : value.thumbnailUrl);
    }
    if (value is Artist) {
      return SpeedDialPin(
          type: 'artist',
          id: value.browseId,
          title: value.name,
          art: value.thumbnailUrl);
    }
    return null;
  }
}

/// Pins, newest first, kept in AppPrefs.
class SpeedDialPins {
  SpeedDialPins._();
  static const key = 'speedDialPins';
  static const max = 9;
  static final pins = <SpeedDialPin>[].obs;
  static bool _loaded = false;

  static Box? get _box =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static void ensureLoaded() {
    if (_loaded) return;
    final box = _box;
    if (box == null) return;
    _loaded = true;
    final raw = box.get(key);
    pins.assignAll([
      if (raw is List)
        for (final r in raw)
          if (SpeedDialPin.fromJson(r) != null) SpeedDialPin.fromJson(r)!,
    ]);
  }

  static bool isPinned(String pinKey) => pins.any((p) => p.key == pinKey);

  static void _save() => _box?.put(key, pins.map((p) => p.toJson()).toList());

  static void pin(SpeedDialPin p) {
    ensureLoaded();
    pins.removeWhere((e) => e.key == p.key);
    pins.insert(0, p);
    if (pins.length > max) pins.removeRange(max, pins.length);
    _save();
  }

  static void unpin(String pinKey) {
    pins.removeWhere((e) => e.key == pinKey);
    _save();
  }
}

/// Item keys shared by every section, so "each item once" works across
/// songs, episodes, collections and artists.
String homeSongKey(String id) => 'song:$id';

bool _hasArtUrl(String? url) =>
    url != null && url.isNotEmpty && url != Playlist.thumbPlaceholderUrl;

HomeItem homeSongItem(MediaItem m) =>
    HomeItem(homeSongKey(m.id), m, hasArt: _hasArtUrl(m.artUri?.toString()));

HomeItem homeAlbumItem(Album a) =>
    HomeItem('album:${a.browseId}', a, hasArt: _hasArtUrl(a.thumbnailUrl));

HomeItem homePlaylistItem(Playlist p) =>
    HomeItem('playlist:${p.playlistId}', p, hasArt: _hasArtUrl(p.thumbnailUrl));

HomeItem homeArtistItem(Artist a) =>
    HomeItem('artist:${a.browseId}', a, hasArt: _hasArtUrl(a.thumbnailUrl));

/// A shelf of songs whose art is mostly 16:9 video frames is a video shelf.
HomeShelfKind songShelfKind(List<MediaItem> songs) {
  if (songs.isEmpty) return HomeShelfKind.songs;
  final frames = songs
      .where((s) => Thumbnail.isVideoFrameUrl(s.artUri?.toString() ?? ''))
      .length;
  return frames * 2 > songs.length ? HomeShelfKind.videos : HomeShelfKind.songs;
}

/// One YouTube Music home shelf as builder input.
HomeShelfData? youTubeShelf(dynamic shelf) {
  if (shelf is SongContent) {
    return HomeShelfData(
      id: 'yt:${shelf.title}',
      title: shelf.title,
      kind: songShelfKind(shelf.songs),
      items: [for (final s in shelf.songs) homeSongItem(s)],
    );
  }
  if (shelf is ArtistShelf) {
    return HomeShelfData(
      id: 'yt:${shelf.title}',
      title: shelf.title,
      kind: HomeShelfKind.artists,
      items: [for (final a in shelf.artists) homeArtistItem(a)],
    );
  }
  if (shelf is AlbumContent) {
    return HomeShelfData(
      id: 'yt:${shelf.title}',
      title: shelf.title,
      items: [for (final a in shelf.albumList) homeAlbumItem(a)],
    );
  }
  if (shelf is PlaylistContent) {
    return HomeShelfData(
      id: 'yt:${shelf.title}',
      title: shelf.title,
      items: [for (final p in shelf.playlistList) homePlaylistItem(p)],
    );
  }
  return null;
}

/// Recently played songs (newest first), music only: episodes and
/// chapters belong in Jump back in.
List<MediaItem> recentSongs() {
  if (!Hive.isBoxOpen('LIBRP')) return const [];
  final out = <MediaItem>[];
  for (final raw in Hive.box('LIBRP').values.toList().reversed) {
    try {
      final m = MediaItemBuilder.fromJson(raw);
      if (m.id.isEmpty || m.isPodcastEpisode || m.isAudiobook) continue;
      out.add(m);
    } catch (_) {}
  }
  return out;
}

/// Things to resume, most recent first: the saved queue (when nothing is
/// playing), in-progress podcast episodes and audiobooks.
List<HomeResumable> homeResumables() {
  final out = <HomeResumable>[];
  if (Get.isRegistered<PlayerController>()) {
    final player = Get.find<PlayerController>();
    // Read every observable before deciding (an Obx that reads none throws).
    final current = player.currentSong.value;
    final showSession = player.showContinueListening.value;
    final item = player.continueListeningItem.value;
    final title = player.continueListeningTitle.value;
    final idle = current == null || player.initFlagForPlayer;
    if (showSession && idle && (item != null || title.isNotEmpty)) {
      out.add(HomeResumable(
        kind: ResumeKind.session,
        id: item?.id ?? 'session',
        // The bare title: "Continue: " would cut it off in a half-width
        // tile; TalkBack still says "Continue: …".
        title: item?.title ?? title,
        art: item,
      ));
    }
    for (final r in PodcastProgressService.inProgress().take(4)) {
      final ep = PodcastProgressService.toMediaItem(r);
      if (!shouldShowPodcastContinueChip(
          hasEpisode: true,
          currentSongId: current?.id,
          continueEpisodeId: ep.id)) {
        continue;
      }
      out.add(HomeResumable(
        kind: ResumeKind.episode,
        id: ep.id,
        title: ep.title,
        art: ep,
        progress: PodcastProgressService.progress(ep.id),
        record: r,
      ));
    }
    for (final r in AudiobookProgressService.latestPerBook(
            AudiobookProgressService.inProgress())
        .take(4)) {
      if ('${r['id']}' == current?.id) continue;
      final book = '${r['album'] ?? ''}';
      final pos = r['positionMs'], dur = r['durationMs'];
      out.add(HomeResumable(
        kind: ResumeKind.book,
        id: '${r['bookId']}',
        title: book.isNotEmpty ? book : '${r['title'] ?? ''}',
        art: MediaItem(
          id: '${r['id']}',
          title: book.isNotEmpty ? book : '${r['title'] ?? ''}',
          artUri: r['artUri'] != null ? Uri.tryParse('${r['artUri']}') : null,
        ),
        progress: pos is int && dur is int && dur > 0
            ? (pos / dur).clamp(0.0, 1.0)
            : null,
        record: r,
      ));
    }
  }
  return out;
}

HomeItem _resumeItem(HomeResumable r) => HomeItem(
      r.kind == ResumeKind.book ? 'book:${r.id}' : homeSongKey(r.id),
      r,
    );

/// Riff's own personal shelves: your mixes and your shows. "Because you
/// played…" rows go too, with the reason as the kicker.
List<HomeShelfData> riffPersonalShelves() {
  final out = <HomeShelfData>[];
  final disc = Get.isRegistered<DiscoveryService>()
      ? Get.find<DiscoveryService>()
      : null;
  if (disc != null) {
    final mixes = disc.dailyMixes.where((m) => m.tracks.isNotEmpty).toList();
    if (mixes.isNotEmpty) {
      out.add(HomeShelfData(
        id: 'riff:mixes',
        title: 'dailyMixes'.tr,
        kind: HomeShelfKind.mixes,
        items: [for (final m in mixes) HomeItem('mix:${m.id}', m)],
      ));
    }
    for (final s in disc.personalSections) {
      if (!s.id.startsWith('because_') || s.tracks.isEmpty) continue;
      final songs = <MediaItem>[];
      for (final t in s.tracks) {
        try {
          songs.add(MediaItemBuilder.fromJson(t));
        } catch (_) {}
      }
      out.add(HomeShelfData(
        id: 'riff:${s.id}',
        title: s.title,
        kicker: s.reason.isNotEmpty ? s.reason : null,
        kind: HomeShelfKind.songs,
        items: [for (final m in songs) homeSongItem(m)],
      ));
      break;
    }
  }
  final shows = Hive.isBoxOpen('PodcastSubs')
      ? PodcastService.subscriptions
      : const <Map<String, dynamic>>[];
  if (shows.isNotEmpty) {
    out.add(HomeShelfData(
      id: 'riff:shows',
      title: 'yourShows'.tr,
      kind: HomeShelfKind.collections,
      items: [
        for (final s in shows)
          HomeItem('show:${s['feedUrl']}', HomeShow(s),
              hasArt: _hasArtUrl('${s['artwork'] ?? ''}')),
      ],
    ));
  }
  return out;
}

/// Bumped when something Home shows changes outside an observable (an
/// episode marked played, a book finished).
final homeFeedRev = 0.obs;

/// Everything Home shows, read from the live controllers and stores.
/// Call inside an Obx: it reads the observables the feed depends on.
HomeFeedInput readHomeFeedInput({required List<MediaItem> recent}) {
  final home = Get.find<HomeScreenController>();
  homeFeedRev.value;
  SpeedDialPins.ensureLoaded();
  final pins = SpeedDialPins.pins.toList();
  final disc = Get.isRegistered<DiscoveryService>()
      ? Get.find<DiscoveryService>()
      : null;
  // Rebuild when mixes or shows change.
  disc?.dailyMixes.length;
  disc?.personalSections.length;
  PodcastService.subsRev.value;
  final yt = [
    for (final s in [...home.middleContent, ...home.fixedContent])
      if (youTubeShelf(s) != null) youTubeShelf(s)!,
  ];
  return HomeFeedInput(
    jumpBackIn: [for (final r in homeResumables()) _resumeItem(r)],
    speedDial: [
      for (final p in pins) HomeItem(p.key, p, hasArt: _hasArtUrl(p.art)),
      for (final m in recent) homeSongItem(m),
    ],
    quickPicks: [
      for (final m in home.quickPicks.value.songList) homeSongItem(m)
    ],
    personalized: riffPersonalShelves(),
    editorial: yt,
    hasWeek: _hasWeek(),
    hasExplore: home.homeChips.isNotEmpty,
    chartsTitle: 'chartsAndHits'.tr,
    moodTitle: 'forYourMood'.tr,
  );
}

bool _hasWeek() {
  if (!Hive.isBoxOpen('DailyStats') || !Hive.isBoxOpen('SongStats')) {
    return false;
  }
  return StatsService.lastDays(7).any((d) => (d['plays'] as int) > 0);
}
