import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/artist.dart';
import '/models/playlist.dart';
import '/models/playling_from.dart';
import '/models/thumbnail.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/collection_play.dart';
import '/ui/screens/Podcasts/podcasts_library_controller.dart';
import '/ui/widgets/podcast_follow_button.dart';
import '/ui/widgets/songinfo_bottom_sheet.dart';
import '../../navigator.dart';
import '../../widgets/snackbar.dart';
import 'artist_screen_controller.dart';

/// Spotify-style single-scroll artist page: a large hero header with the
/// artist name + listeners, a Follow / Shuffle / Play action row, a numbered
/// "Popular" tracks list, album & single carousels, and an About section.
class SpotifyArtistView extends StatefulWidget {
  const SpotifyArtistView({super.key, required this.controller});
  final ArtistScreenController controller;

  @override
  State<SpotifyArtistView> createState() => _SpotifyArtistViewState();
}

class _SpotifyArtistViewState extends State<SpotifyArtistView> {
  bool _popularExpanded = false;

  ArtistScreenController get c => widget.controller;

  List _content(dynamic section) {
    if (section is Map && section['content'] is List) {
      return section['content'] as List;
    }
    return const [];
  }

  List<MediaItem> _songs() =>
      _content(c.artistData['Songs']).whereType<MediaItem>().toList();

  Future<void> _playSongs(List<MediaItem> songs, int index,
      {bool shuffle = false}) async {
    if (songs.isEmpty) return;
    final player = Get.find<PlayerController>();
    final list = List<MediaItem>.from(songs);
    if (shuffle) {
      list.shuffle();
      index = 0;
    }
    final ok = await player.playPlayListSong(
      list,
      index,
      playfrom: PlaylingFrom(
          name: c.artist_.name, type: PlaylingFromType.PLAYLIST),
    );
    if (!ok) snackOperationFailed();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.isArtistContentFetced.isFalse) {
        return const Center(child: CircularProgressIndicator());
      }
      final theme = Theme.of(context);
      final songs = _songs();
      final albums = _content(c.artistData['Albums']);
      final singles = _content(c.artistData['Singles']);
      final featured = _content(c.artistData['Featured']);
      final related = _content(c.artistData['Related']);
      final description = c.artistData['description'];
      final popularCount =
          _popularExpanded ? songs.length : (songs.length > 5 ? 5 : songs.length);

      return CustomScrollView(
        slivers: [
          _heroHeader(context, theme),
          SliverToBoxAdapter(child: _actionRow(context, theme, songs)),
          if (songs.isNotEmpty)
            SliverToBoxAdapter(
              child: _sectionHeader(theme, 'popular'.tr),
            ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _songRow(context, theme, songs, i),
              childCount: popularCount,
            ),
          ),
          if (songs.length > 5)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () =>
                        setState(() => _popularExpanded = !_popularExpanded),
                    child: Text(_popularExpanded ? 'showLess'.tr : 'seeMore'.tr),
                  ),
                ),
              ),
            ),
          if (albums.isNotEmpty)
            SliverToBoxAdapter(
              child: _releaseCarousel(theme, 'albums'.tr, albums),
            ),
          if (singles.isNotEmpty)
            SliverToBoxAdapter(
              child: _releaseCarousel(theme, 'singles'.tr, singles),
            ),
          if (featured.isNotEmpty)
            SliverToBoxAdapter(
              child: _playlistCarousel(
                  theme, '${'featuring'.tr} ${c.artist_.name}', featured),
            ),
          if (related.isNotEmpty)
            SliverToBoxAdapter(
              child: _artistCarousel(theme, 'fansAlsoLike'.tr, related),
            ),
          if (description != null && '$description'.trim().isNotEmpty)
            SliverToBoxAdapter(child: _about(theme, '$description')),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      );
    });
  }

  Widget _heroHeader(BuildContext context, ThemeData theme) {
    final img = Thumbnail(c.artist_.thumbnailUrl).extraHigh;
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      stretch: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () =>
            Get.nestedKey(ScreenNavigationSetup.id)!.currentState!.pop(),
      ),
      actions: [
        Obx(() => IconButton(
              tooltip: c.isAddedToLibrary.isFalse
                  ? 'follow'.tr
                  : 'following'.tr,
              icon: Icon(c.isAddedToLibrary.isFalse
                  ? Icons.bookmark_add_outlined
                  : Icons.bookmark_added),
              onPressed: _toggleFollow,
            )),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 16, bottom: 14, right: 16),
        title: Text(
          c.artist_.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 20, color: Colors.white),
        ),
        background: GestureDetector(
          onTap: () => _playSongs(_songs(), 0),
          child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: img,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorWidget: (_, __, ___) => Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.person, size: 90),
              ),
            ),
            // Fade the bottom into the page background so the title is legible.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.15),
                    theme.scaffoldBackgroundColor.withOpacity(0.95),
                    theme.scaffoldBackgroundColor,
                  ],
                  stops: const [0.0, 0.55, 0.9, 1.0],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _actionRow(BuildContext context, ThemeData theme, List<MediaItem> songs) {
    final subs = c.artist_.subscribers;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subs != null && subs.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(subs,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color
                          ?.withOpacity(0.8))),
            ),
          Row(
            children: [
              // Artist library bookmark stays in the app bar; this Follow is
              // subscribe-as-podcast (same green pill as RSS shows).
              Obx(() {
                if (!Get.isRegistered<LibraryPodcastsController>()) {
                  return OutlinedButton(
                    onPressed: _toggleFollow,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text(c.isAddedToLibrary.isFalse
                        ? 'follow'.tr
                        : 'following'.tr),
                  );
                }
                final lib = Get.find<LibraryPodcastsController>();
                final rawId = c.artist_.browseId;
                final id =
                    rawId.startsWith('MPLA') ? rawId.substring(4) : rawId;
                final subscribed =
                    lib.libraryPodcasts.any((p) => p.playlistId == id);
                return PodcastFollowButton(
                  following: subscribed,
                  onPressed: () async {
                    if (subscribed) {
                      await lib.removeFromLibrary(id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(snackbar(
                        context,
                        'removeFromLib'.tr,
                        size: SanckBarSize.MEDIUM,
                      ));
                      return;
                    }
                    final pl = Playlist(
                      title: c.artist_.name,
                      playlistId: id,
                      thumbnailUrl: c.artist_.thumbnailUrl,
                      description:
                          c.artist_.subscribers ?? 'YouTube channel',
                      kind: 'yt_channel',
                    );
                    final saved =
                        await lib.subscribeYoutubeChannel(id, seed: pl);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(snackbar(
                      context,
                      saved != null
                          ? 'subscribedAsPodcast'.tr
                          : 'operationFailed'.tr,
                      size: SanckBarSize.MEDIUM,
                    ));
                  },
                );
              }),
              const Spacer(),
              IconButton(
                tooltip: 'startRadio'.tr,
                icon: const Icon(Icons.sensors),
                onPressed: () async {
                  final radioId = c.artist_.radioId;
                  final player = Get.find<PlayerController>();
                  var ok = false;
                  if (radioId != null && radioId.isNotEmpty) {
                    ok = await player.startRadio(null, playlistid: radioId);
                  } else if (songs.isNotEmpty) {
                    ok = await player.startRadio(songs.first);
                  }
                  if (ok || !context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(snackbar(
                      context, "radioNotAvailable".tr,
                      size: SanckBarSize.BIG));
                },
              ),
              IconButton(
                tooltip: 'shuffle'.tr,
                icon: const Icon(Icons.shuffle),
                onPressed: songs.isEmpty
                    ? null
                    : () => _playSongs(songs, 0, shuffle: true),
              ),
              const SizedBox(width: 4),
              // Big accent Play button (Spotify's green circle).
              Material(
                color: theme.colorScheme.secondary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: songs.isEmpty ? null : () => _playSongs(songs, 0),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(Icons.play_arrow,
                        size: 30, color: theme.colorScheme.onSecondary),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(title,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700)),
    );
  }

  Widget _songRow(
      BuildContext context, ThemeData theme, List<MediaItem> songs, int i) {
    final song = songs[i];
    final art = Thumbnail(song.artUri?.toString() ?? '').medium;
    final subtitle = (song.extras?['album']?['name'] ?? song.artist ?? '')
        .toString()
        .trim();
    return InkWell(
      onTap: () => _playSongs(songs, i),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text('${i + 1}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.textTheme.bodySmall?.color)),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: art,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.music_note, size: 30),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _openSongMenu(context, song),
            ),
          ],
        ),
      ),
    );
  }

  Widget _releaseCarousel(ThemeData theme, String title, List items) {
    // Only Album-typed, non-null entries (artist shelves can contain nulls).
    final albums = items
        .where((e) => e != null && e.runtimeType.toString() == 'Album')
        .toList();
    if (albums.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(theme, title),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            itemCount: albums.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) => _releaseCard(theme, albums[i]),
          ),
        ),
      ],
    );
  }

  void _openAlbum(dynamic album) {
    Get.toNamed(
      ScreenNavigationSetup.albumScreen,
      id: ScreenNavigationSetup.id,
      arguments: (album, album.browseId),
    );
  }

  Future<void> _playOrOpenAlbum(dynamic album) async {
    final ok = await playCollection(
      isAlbum: true,
      id: (album.browseId ?? '').toString(),
      title: (album.title ?? '').toString(),
    );
    if (!ok) _openAlbum(album);
  }

  void _openPlaylist(dynamic playlist) {
    Get.toNamed(
      ScreenNavigationSetup.playlistScreen,
      id: ScreenNavigationSetup.id,
      arguments: [playlist, playlist.playlistId, false],
    );
  }

  Future<void> _playOrOpenPlaylist(dynamic playlist) async {
    final ok = await playCollection(
      isAlbum: false,
      id: (playlist.playlistId ?? '').toString(),
      title: (playlist.title ?? '').toString(),
      isPipedPlaylist: playlist.isPipedPlaylist == true,
      isCloudPlaylist: playlist.isCloudPlaylist != false,
    );
    if (!ok) _openPlaylist(playlist);
  }

  void _openRelatedArtist(dynamic artist) {
    Get.toNamed(
      ScreenNavigationSetup.artistScreen,
      id: ScreenNavigationSetup.id,
      preventDuplicates: false,
      arguments: [true, artist.browseId],
    );
  }

  Future<void> _playOrOpenArtist(dynamic artist) async {
    final model = artist is Artist
        ? artist
        : Artist(
            name: (artist.name ?? '').toString(),
            browseId: (artist.browseId ?? '').toString(),
            radioId: artist.radioId?.toString(),
            thumbnailUrl: (artist.thumbnailUrl ?? '').toString(),
          );
    if (model.browseId.isEmpty) {
      _openRelatedArtist(artist);
      return;
    }
    final ok = await playArtist(model);
    if (!ok) _openRelatedArtist(artist);
  }

  /// A safe album card (avoids ContentListItem's unguarded artists[0] access,
  /// which throws for an artist's own-page album shelf where YTM omits it).
  Widget _releaseCard(ThemeData theme, dynamic album) {
    final art = Thumbnail((album.thumbnailUrl ?? '').toString()).high;
    final year = (album.year ?? '').toString();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _playOrOpenAlbum(album),
      onLongPress: () => _openAlbum(album),
      child: SizedBox(
        width: 124,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: art,
                width: 124,
                height: 124,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 124,
                  height: 124,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.album, size: 40),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              (album.title ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500, height: 1.1),
            ),
            if (year.isNotEmpty)
              Text(year,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }

  /// "Featuring X" — playlists the artist appears on (Spotify-style).
  Widget _playlistCarousel(ThemeData theme, String title, List items) {
    final playlists = items
        .where((e) => e != null && e.runtimeType.toString() == 'Playlist')
        .toList();
    if (playlists.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(theme, title),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            itemCount: playlists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) => _playlistCard(theme, playlists[i]),
          ),
        ),
      ],
    );
  }

  Widget _playlistCard(ThemeData theme, dynamic playlist) {
    final art = Thumbnail((playlist.thumbnailUrl ?? '').toString()).high;
    final desc = (playlist.description ?? '').toString();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _playOrOpenPlaylist(playlist),
      onLongPress: () => _openPlaylist(playlist),
      child: SizedBox(
        width: 124,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: art,
                width: 124,
                height: 124,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 124,
                  height: 124,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.queue_music, size: 40),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              (playlist.title ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500, height: 1.1),
            ),
            if (desc.isNotEmpty)
              Text(desc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }

  /// "Fans also like" — related artists as circular avatars (Spotify-style).
  Widget _artistCarousel(ThemeData theme, String title, List items) {
    final artists = items
        .where((e) => e != null && e.runtimeType.toString() == 'Artist')
        .toList();
    if (artists.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(theme, title),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            itemCount: artists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) => _artistCard(theme, artists[i]),
          ),
        ),
      ],
    );
  }

  Widget _artistCard(ThemeData theme, dynamic artist) {
    final art = Thumbnail((artist.thumbnailUrl ?? '').toString()).high;
    return InkWell(
      borderRadius: BorderRadius.circular(62),
      onTap: () => _playOrOpenArtist(artist),
      onLongPress: () => _openRelatedArtist(artist),
      child: SizedBox(
        width: 124,
        child: Column(
          children: [
            ClipOval(
              child: CachedNetworkImage(
                imageUrl: art,
                width: 116,
                height: 116,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: const Icon(Icons.person, size: 44),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              (artist.name ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _about(ThemeData theme, String description) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(theme, 'about'.tr),
          Text(description, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  void _toggleFollow() {
    final add = c.isAddedToLibrary.isFalse;
    c.addNremoveFromLibrary(add: add).then((ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context,
          ok
              ? add
                  ? 'artistBookmarkAddAlert'.tr
                  : 'artistBookmarkRemoveAlert'.tr
              : 'operationFailed'.tr,
          size: SanckBarSize.MEDIUM));
    });
  }

  void _openSongMenu(BuildContext context, MediaItem song) {
    showModalBottomSheet(
      useRootNavigator: true,
      constraints: const BoxConstraints(maxWidth: 500),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
      ),
      isScrollControlled: true,
      context: context,
      barrierColor: Colors.transparent.withAlpha(100),
      builder: (context) => SongInfoBottomSheet(song),
    ).whenComplete(() => Get.delete<SongInfoController>());
  }
}
