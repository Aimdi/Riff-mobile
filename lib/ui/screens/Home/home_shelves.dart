import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/album.dart';
import '/models/artist.dart';
import '/models/media_Item_builder.dart';
import '/models/media_item_extras.dart';
import '/models/playlist.dart';
import '/models/thumbnail.dart';
import '/services/discovery/discovery_service.dart';
import '/services/discovery/discovery_types.dart';
import '/services/spotify_api_service.dart';
import '/services/spotify_home.dart';
import '/services/spotify_import_service.dart';
import '/ui/navigator.dart';
import '/ui/player/player_controller.dart';
import '../../widgets/collection_play.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/letter_art.dart';
import '../../widgets/riff_sheet.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import '../Plugins/spotify_pages.dart';
import '../Plugins/spotify_widgets.dart'
    show playSpotifyTracks, startSpotifyRadio;
import '../Podcasts/podcasts_screen.dart' show PodcastEpisodesScreen;
import 'home_feed_builder.dart';
import 'home_feed_data.dart';
import 'home_metrics.dart';
import '/ui/theme/riff_text_metrics.dart';

/// Card sizes per item type on a shelf of pane width [m].
class ShelfCardSize {
  ShelfCardSize._();

  static double width(Object? value, HomeShelfKind kind, HomeMetrics m) {
    if (value is Artist || value is SpotifyArtistSummary) {
      return RiffSizes.artistCircle;
    }
    if (value is MediaItem) {
      if (value.isPodcastEpisode) return RiffSizes.episodeWidth;
      if (kind == HomeShelfKind.videos) return RiffSizes.videoWidth;
    }
    return m.shelfCard;
  }

  static double artHeight(Object? value, HomeShelfKind kind, HomeMetrics m) {
    if (value is Artist || value is SpotifyArtistSummary) {
      return RiffSizes.artistCircle;
    }
    if (value is MediaItem) {
      if (value.isPodcastEpisode) return 0;
      if (kind == HomeShelfKind.videos) return RiffSizes.videoWidth * 9 / 16;
    }
    return m.shelfCard;
  }

  /// Title + subtitle under the art: both lines always reserved.
  static double textBlock(BuildContext context) {
    return 8 +
        riffLineHeight(context, _titleStyle(context)) +
        2 +
        riffLineHeight(context, _subtitleStyle(context));
  }

  /// A podcast episode row card's height.
  static double episodeHeight(BuildContext context) {
    return (riffLineHeight(context, _titleStyle(context)) * 2 +
            riffLineHeight(context, _subtitleStyle(context)) +
            20)
        .clamp(80.0, 140.0);
  }
}

TextStyle _titleStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.labelMedium ?? const TextStyle()).copyWith(
    color: theme.colorScheme.onSurface,
  );
}

TextStyle _subtitleStyle(BuildContext context) =>
    (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
        .copyWith(color: riffMuted(context));

/// One shelf: the shared header, then a horizontal list that starts 16dp
/// in and scrolls to the screen edge, cards 12dp apart.
class RiffShelf extends StatelessWidget {
  const RiffShelf({
    super.key,
    required this.shelf,
    required this.metrics,
    this.controller,
  });

  final HomeShelfData shelf;
  final HomeMetrics metrics;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final items = shelf.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final text = ShelfCardSize.textBlock(context);
    var height = 0.0;
    for (final i in items) {
      final v = i.value;
      final h = v is MediaItem && v.isPodcastEpisode
          ? ShelfCardSize.episodeHeight(context)
          : ShelfCardSize.artHeight(v, shelf.kind, metrics) + text;
      if (h > height) height = h;
    }
    final songs = [
      for (final i in items)
        if (i.value is MediaItem) i.value as MediaItem
    ];
    final spotifySongs = [
      for (final i in items)
        if (i.value is SpotifyTrackRef) i.value as SpotifyTrackRef
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RiffSectionHeader(shelf.title, kicker: shelf.kicker),
        SizedBox(
          height: height,
          child: ListView.separated(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.only(
                start: RiffSpacing.gutter, end: RiffSpacing.gutter),
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: RiffSpacing.cardGap),
            itemBuilder: (context, i) => Align(
              alignment: Alignment.topLeft,
              child: HomeShelfItem(
                value: items[i].value,
                kind: shelf.kind,
                metrics: metrics,
                queue: songs,
                spotifyQueue: spotifySongs,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single card on a shelf, sized and laid out by what it holds.
class HomeShelfItem extends StatelessWidget {
  const HomeShelfItem({
    super.key,
    required this.value,
    required this.kind,
    required this.metrics,
    this.queue = const [],
    this.spotifyQueue = const [],
  });

  final Object? value;
  final HomeShelfKind kind;
  final HomeMetrics metrics;

  /// The shelf's songs, so a song card plays the shelf from itself.
  final List<MediaItem> queue;

  /// The shelf's Spotify songs, played the same way.
  final List<SpotifyTrackRef> spotifyQueue;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final w = ShelfCardSize.width(v, kind, metrics);
    final h = ShelfCardSize.artHeight(v, kind, metrics);
    final spotify = _spotifyCard(context, v, w, h);
    if (spotify != null) return spotify;
    if (v is Album) {
      final artist = (v.artists != null && v.artists!.isNotEmpty)
          ? '${v.artists!.first['name'] ?? ''}'
          : '';
      return _Card(
        width: w,
        art: ImageWidget(album: v, size: w, borderRadius: 0),
        artHeight: h,
        title: v.title,
        subtitle: [artist, v.year ?? ''].where((s) => s.isNotEmpty).join(' • '),
        onTap: () => Get.toNamed(ScreenNavigationSetup.albumScreen,
            id: ScreenNavigationSetup.id, arguments: (v, v.browseId)),
        onLongPress: () => _collectionMenu(context,
            title: v.title,
            isAlbum: true,
            id: v.browseId,
            pin: SpeedDialPin.of(v)),
      );
    }
    if (v is Playlist) {
      return _Card(
        width: w,
        art: ImageWidget(playlist: v, size: w, borderRadius: 0),
        artHeight: h,
        title: v.title,
        subtitle: v.description ?? '',
        onTap: () => _openPlaylist(v),
        onLongPress: () => _collectionMenu(context,
            title: v.title,
            isAlbum: false,
            id: v.playlistId,
            pin: SpeedDialPin.of(v)),
      );
    }
    if (v is Artist) {
      return _Card(
        width: w,
        circle: true,
        centered: true,
        art: ImageWidget(artist: v, size: w, borderRadius: 0),
        artHeight: h,
        title: v.name,
        subtitle: v.subscribers ?? '',
        onTap: () => Get.toNamed(ScreenNavigationSetup.artistScreen,
            id: ScreenNavigationSetup.id, arguments: [true, v.browseId]),
        onLongPress: () => _pinOnlyMenu(context, v.name, SpeedDialPin.of(v)),
      );
    }
    if (v is HomeShow) {
      return _Card(
        width: w,
        art: v.artwork.isEmpty
            ? LetterArt(title: v.title, size: w)
            : ImageWidget(
                song: MediaItem(
                    id: v.feedUrl,
                    title: v.title,
                    artUri: Uri.tryParse(v.artwork)),
                size: w,
                borderRadius: 0),
        artHeight: h,
        title: v.title,
        subtitle: v.author,
        onTap: () => Get.to(() => PodcastEpisodesScreen(podcast: v.data)),
      );
    }
    if (v is GeneratedMix) {
      final tracks = _mixTracks(v);
      return _Card(
        width: w,
        art: tracks.length >= 4
            ? _Collage(tracks: tracks.take(4).toList(), size: w)
            : tracks.isNotEmpty
                ? ImageWidget(song: tracks.first, size: w, borderRadius: 0)
                : LetterArt(title: v.title, size: w),
        artHeight: h,
        title: v.title,
        subtitle:
            v.reason.isNotEmpty ? v.reason : '${v.tracks.length} ${'songs'.tr}',
        onTap: () => _openMix(v),
        onLongPress: () => _mixMenu(context, v),
      );
    }
    if (v is MediaItem) {
      if (v.isPodcastEpisode) return _EpisodeCard(episode: v, queue: queue);
      final video = kind == HomeShelfKind.videos;
      return _Card(
        width: w,
        art: video
            ? _VideoArt(song: v, width: w, height: h)
            : ImageWidget(song: v, size: w, borderRadius: 0),
        artHeight: h,
        title: v.title,
        subtitle: v.artist ?? '',
        onTap: () => _playSongs(queue, v),
        onLongPress: () {
          final player = Get.find<PlayerController>();
          showCurrentSongSheet(
              song: v, context: player.homeScaffoldkey.currentContext);
        },
      );
    }
    return const SizedBox.shrink();
  }
}

extension on HomeShelfItem {
  /// Cards for Spotify items; null for everything else.
  Widget? _spotifyCard(BuildContext context, Object? v, double w, double h) {
    switch (v) {
      case SpotifyTrackRef t:
        return _Card(
          width: w,
          art: _netArt(t.artUrl, t.title, w),
          artHeight: h,
          title: t.title,
          subtitle: t.artists,
          onTap: () {
            final list = spotifyQueue.isEmpty ? [t] : spotifyQueue;
            final at = list.indexOf(t);
            playSpotifyTracks(context, list,
                start: at < 0 ? 0 : at, from: 'Spotify');
          },
          onLongPress: () => startSpotifyRadio(context, seed: t),
        );
      case SpotifyAlbumSummary a:
        return _Card(
          width: w,
          art: _netArt(a.coverUrl, a.name, w),
          artHeight: h,
          title: a.name,
          subtitle:
              [a.artists, a.year ?? ''].where((s) => s.isNotEmpty).join(' • '),
          onTap: () => openSpotifyPage(SpotifyAlbumArgs(a)),
        );
      case SpotifyHomePlaylist p:
        return _Card(
          width: w,
          art: _netArt(p.playlist.coverUrl, p.playlist.name, w),
          artHeight: h,
          title: p.playlist.name,
          subtitle: p.playlist.ownerName ?? '',
          onTap: () => openSpotifyPage(
              SpotifyPlaylistArgs(p.playlist, readable: p.readable)),
        );
      case SpotifyArtistSummary a:
        return _Card(
          width: w,
          circle: true,
          centered: true,
          art: _netArt(a.imageUrl, a.name, w, circle: true),
          artHeight: h,
          title: a.name,
          subtitle: a.genres.isEmpty ? '' : a.genres.first,
          onTap: () => openSpotifyPage(SpotifyArtistArgs(a)),
        );
      case SpotifyTasteMix m:
        return _Card(
          width: w,
          art: _CoverCollage(
              urls: m.covers, size: w, title: 'spotifyTasteMix'.tr),
          artHeight: h,
          title: 'spotifyTasteMix'.tr,
          subtitle: 'spotifyTasteMixDes'.tr,
          onTap: () => startSpotifyRadio(context),
        );
    }
    return null;
  }
}

/// Network cover, or the letter tile when there is none.
Widget _netArt(String? url, String title, double size, {bool circle = false}) {
  if (url == null || url.isEmpty) {
    return LetterArt(title: title, size: size, circle: circle);
  }
  return ImageWidget(
    song: MediaItem(id: url, title: title, artUri: Uri.tryParse(url)),
    size: size,
    borderRadius: 0,
  );
}

/// Up to four covers in a square, for mix cards built from URLs.
class _CoverCollage extends StatelessWidget {
  const _CoverCollage(
      {required this.urls, required this.size, required this.title});
  final List<String> urls;
  final double size;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (urls.length < 4) {
      return _netArt(urls.isEmpty ? null : urls.first, title, size);
    }
    final cell = size / 2;
    return Column(children: [
      Row(children: [
        _netArt(urls[0], title, cell),
        _netArt(urls[1], title, cell)
      ]),
      Row(children: [
        _netArt(urls[2], title, cell),
        _netArt(urls[3], title, cell)
      ]),
    ]);
  }
}

void _openPlaylist(Playlist p) =>
    Get.toNamed(ScreenNavigationSetup.playlistScreen,
        id: ScreenNavigationSetup.id, arguments: [p, p.playlistId, false]);

Future<void> _playSongs(List<MediaItem> queue, MediaItem song) async {
  final player = Get.find<PlayerController>();
  if (player.currentSong.value?.id == song.id) {
    player.playPause();
    return;
  }
  final list = queue.isEmpty ? [song] : queue;
  final at = list.indexWhere((s) => s.id == song.id);
  final ok = await player.playPlayListSong(list, at < 0 ? 0 : at,
      source: DiscoverySource.home);
  if (!ok) snackOperationFailed();
}

List<MediaItem> _mixTracks(GeneratedMix mix) {
  final out = <MediaItem>[];
  for (final raw in mix.tracks) {
    try {
      final m = MediaItemBuilder.fromJson(raw);
      if (m.id.isNotEmpty) out.add(m);
    } catch (_) {}
  }
  return out;
}

Future<void> _playMix(GeneratedMix mix, {bool shuffle = true}) async {
  final tracks = _mixTracks(mix);
  if (tracks.isEmpty) return;
  if (shuffle) tracks.shuffle();
  final tagged = DiscoveryService.tagAll(tracks, DiscoverySource.dailyMix);
  final ok = await Get.find<PlayerController>().playPlayListSong(tagged, 0);
  if (!ok) snackOperationFailed();
}

Future<void> _openMix(GeneratedMix mix) async {
  if (!Get.isRegistered<DiscoveryService>()) return;
  await Get.find<DiscoveryService>().materializeMixPlaylists();
  final id = 'RIFF_${mix.id}';
  final tracks = _mixTracks(mix);
  _openPlaylist(Playlist(
    title: mix.title,
    playlistId: id,
    thumbnailUrl: tracks.isNotEmpty
        ? tracks.first.artUri?.toString() ?? Playlist.thumbPlaceholderUrl
        : Playlist.thumbPlaceholderUrl,
    isCloudPlaylist: false,
  ));
}

Widget _sheet(BuildContext context, String title,
        List<Widget> Function(BuildContext) tiles) =>
    SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const RiffSheetHandle(),
          RiffSheetTitle(title),
          ...tiles(context),
          const SizedBox(height: 8),
        ],
      ),
    );

Widget _pinTile(BuildContext sheet, SpeedDialPin pin) {
  final pinned = SpeedDialPins.isPinned(pin.key);
  return RiffSheetTile(
    icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
    title: pinned ? 'unpinFromSpeedDial'.tr : 'pinToSpeedDial'.tr,
    onTap: () {
      Navigator.of(sheet).pop();
      pinned ? SpeedDialPins.unpin(pin.key) : SpeedDialPins.pin(pin);
    },
  );
}

void _collectionMenu(BuildContext context,
    {required String title,
    required bool isAlbum,
    required String id,
    SpeedDialPin? pin}) {
  Future<void> play(bool shuffle) async {
    final ok = await playCollection(
        isAlbum: isAlbum, id: id, title: title, shuffle: shuffle);
    if (!ok) snackOperationFailed();
  }

  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    shape: riffSheetShape,
    builder: (sheet) => _sheet(
        sheet,
        title,
        (sheet) => [
              RiffSheetTile(
                icon: Icons.play_arrow_rounded,
                title: 'play'.tr,
                onTap: () {
                  Navigator.of(sheet).pop();
                  play(false);
                },
              ),
              RiffSheetTile(
                icon: Icons.shuffle_rounded,
                title: 'shuffle'.tr,
                onTap: () {
                  Navigator.of(sheet).pop();
                  play(true);
                },
              ),
              if (pin != null) _pinTile(sheet, pin),
            ]),
  );
}

void _pinOnlyMenu(BuildContext context, String title, SpeedDialPin? pin) {
  if (pin == null) return;
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    shape: riffSheetShape,
    builder: (sheet) => _sheet(sheet, title, (sheet) => [_pinTile(sheet, pin)]),
  );
}

void _mixMenu(BuildContext context, GeneratedMix mix) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    shape: riffSheetShape,
    builder: (sheet) => _sheet(
        sheet,
        mix.title,
        (sheet) => [
              RiffSheetTile(
                icon: Icons.play_arrow_rounded,
                title: 'play'.tr,
                onTap: () {
                  Navigator.of(sheet).pop();
                  _playMix(mix, shuffle: false);
                },
              ),
              RiffSheetTile(
                icon: Icons.shuffle_rounded,
                title: 'shuffle'.tr,
                onTap: () {
                  Navigator.of(sheet).pop();
                  _playMix(mix);
                },
              ),
            ]),
  );
}

/// Art, then a one-line title and a one-line subtitle (space for both is
/// always kept, so every card on a shelf is the same height).
class _Card extends StatelessWidget {
  const _Card({
    required this.width,
    required this.art,
    required this.artHeight,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.onLongPress,
    this.circle = false,
    this.centered = false,
  });

  final double width;
  final Widget art;
  final double artHeight;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool circle;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final align = centered ? TextAlign.center : TextAlign.start;
    return Semantics(
      button: true,
      label: [title, if (subtitle.isNotEmpty) subtitle].join(', '),
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: InkWell(
          borderRadius: BorderRadius.circular(RiffSizes.shelfRadius),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment:
                centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: circle
                    ? BorderRadius.circular(width)
                    : BorderRadius.circular(RiffSizes.shelfRadius),
                child: SizedBox(width: width, height: artHeight, child: art),
              ),
              const SizedBox(height: 8),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: align,
                  style: _titleStyle(context)),
              const SizedBox(height: 2),
              Text(subtitle.isEmpty ? ' ' : subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: align,
                  style: _subtitleStyle(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 16:9 video frame, with the letter tile when it has none.
class _VideoArt extends StatelessWidget {
  const _VideoArt(
      {required this.song, required this.width, required this.height});
  final MediaItem song;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final raw = song.artUri?.toString() ?? '';
    Widget fallback() => LetterArt(title: song.title, size: width);
    if (raw.isEmpty) {
      return ClipRect(child: OverflowBox(maxHeight: width, child: fallback()));
    }
    return CachedNetworkImage(
      imageUrl: Thumbnail(raw).high,
      httpHeaders: kCoverImageHeaders,
      width: width,
      height: height,
      fit: BoxFit.cover,
      memCacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
      errorWidget: (_, __, ___) =>
          ClipRect(child: OverflowBox(maxHeight: width, child: fallback())),
      placeholder: (_, __) =>
          ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHigh),
    );
  }
}

/// Four covers in a square (mix cards).
class _Collage extends StatelessWidget {
  const _Collage({required this.tracks, required this.size});
  final List<MediaItem> tracks;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cell = size / 2;
    Widget tile(MediaItem s) =>
        ImageWidget(song: s, size: cell, borderRadius: 0);
    return Column(children: [
      Row(children: [tile(tracks[0]), tile(tracks[1])]),
      Row(children: [tile(tracks[2]), tile(tracks[3])]),
    ]);
  }
}

/// A podcast episode as a 280dp row card: art, two lines of title, show.
class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({required this.episode, required this.queue});
  final MediaItem episode;
  final List<MediaItem> queue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = ShelfCardSize.episodeHeight(context);
    return Semantics(
      button: true,
      label: [episode.title, episode.artist ?? ''].join(', '),
      excludeSemantics: true,
      child: SizedBox(
        width: RiffSizes.episodeWidth,
        height: height,
        child: Material(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(RiffSizes.shelfRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _playSongs(queue, episode),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(RiffSizes.tileRadius),
                    child:
                        ImageWidget(song: episode, size: 60, borderRadius: 0),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(episode.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _titleStyle(context)),
                        Text(episode.artist ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _subtitleStyle(context)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
