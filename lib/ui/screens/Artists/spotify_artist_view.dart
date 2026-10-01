import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '/models/artist.dart';
import '/models/playlist.dart';
import '/models/playling_from.dart';
import '/models/thumbnail.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/collection_play.dart';
import '/ui/screens/Podcasts/podcasts_library_controller.dart';
import '/ui/widgets/songinfo_bottom_sheet.dart';
import '../../navigator.dart';
import '../../widgets/separate_tab_item_widget.dart';
import '../../widgets/shimmer_widgets/song_list_shimmer.dart';
import '../../widgets/snackbar.dart';
import '../Home/home_layout.dart';
import 'artist_screen_controller.dart';

/// Single-scroll artist page: hero image with the name, one action row
/// (Follow, more, shuffle, play), Popular songs, then Home-style shelves for
/// videos, albums, singles, playlists and related artists, and About.
class SpotifyArtistView extends StatefulWidget {
  const SpotifyArtistView(
      {super.key, required this.controller, required this.tag});
  final ArtistScreenController controller;

  /// Controller tag, for the full "See all" lists.
  final String tag;

  @override
  State<SpotifyArtistView> createState() => _SpotifyArtistViewState();
}

/// Artist-page sections that have a full list, by controller tab index.
const _sectionTabs = {'Songs': 1, 'Videos': 2, 'Albums': 3, 'Singles': 4};

class _SpotifyArtistViewState extends State<SpotifyArtistView> {
  bool _popularExpanded = false;
  bool _aboutExpanded = false;

  ArtistScreenController get c => widget.controller;

  List _content(dynamic section) {
    if (section is Map && section['content'] is List) {
      return section['content'] as List;
    }
    return const [];
  }

  bool _hasFullList(String key) {
    final section = c.artistData[key];
    return section is Map && section.containsKey('params');
  }

  List<MediaItem> _songs() =>
      _content(c.artistData['Songs']).whereType<MediaItem>().toList();

  List<MediaItem> _videos() =>
      _content(c.artistData['Videos']).whereType<MediaItem>().toList();

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
      playfrom:
          PlaylingFrom(name: c.artist_.name, type: PlaylingFromType.PLAYLIST),
    );
    if (!ok) snackOperationFailed();
  }

  void _openSection(String key, String title) {
    final index = _sectionTabs[key];
    if (index == null) return;
    c.onDestinationSelected(index);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ArtistSectionPage(
        controller: c,
        tag: widget.tag,
        tabName: key,
        title: title,
      ),
    ));
  }

  Widget? _seeAll(String key, String title) {
    if (!_hasFullList(key)) return null;
    return TextButton(
      onPressed: () => _openSection(key, title),
      style: TextButton.styleFrom(
        foregroundColor: homeMutedColor(context),
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Text('viewAll'.tr,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.isArtistContentFetced.isFalse) {
        return const SongListShimmer(itemCount: 8, topPadding: 12);
      }
      final songs = _songs();
      final videos = _videos();
      final albums = _albumsOf(c.artistData['Albums']);
      final singles = _albumsOf(c.artistData['Singles']);
      final featured = _content(c.artistData['Featured'])
          .where((e) => e != null && e.runtimeType.toString() == 'Playlist')
          .toList();
      final related = _content(c.artistData['Related'])
          .where((e) => e != null && e.runtimeType.toString() == 'Artist')
          .toList();
      final description = '${c.artistData['description'] ?? ''}'.trim();
      final popularCount = _popularExpanded
          ? songs.length
          : (songs.length > 5 ? 5 : songs.length);

      return CustomScrollView(
        slivers: [
          _heroHeader(context),
          SliverToBoxAdapter(child: _actionRow(context, songs)),
          if (songs.isNotEmpty)
            SliverToBoxAdapter(
              child: HomeSectionHeader('popular'.tr,
                  top: 16, trailing: _seeAll('Songs', 'popular'.tr)),
            ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _songRow(context, songs, i),
              childCount: popularCount,
            ),
          ),
          if (songs.length > 5)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: HomeLayout.gutter - 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: homeMutedColor(context)),
                    onPressed: () =>
                        setState(() => _popularExpanded = !_popularExpanded),
                    child: Text(_popularExpanded ? 'showLess'.tr : 'seeMore'.tr,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          if (videos.isNotEmpty)
            SliverToBoxAdapter(child: _videoShelf(context, videos)),
          if (albums.isNotEmpty)
            SliverToBoxAdapter(
                child: _releaseShelf(context, 'Albums', 'albums'.tr, albums)),
          if (singles.isNotEmpty)
            SliverToBoxAdapter(
                child:
                    _releaseShelf(context, 'Singles', 'singles'.tr, singles)),
          if (featured.isNotEmpty)
            SliverToBoxAdapter(child: _playlistShelf(context, featured)),
          if (related.isNotEmpty)
            SliverToBoxAdapter(child: _artistShelf(context, related)),
          if (description.isNotEmpty)
            SliverToBoxAdapter(child: _about(context, description)),
          const SliverToBoxAdapter(child: SizedBox(height: 200)),
        ],
      );
    });
  }

  List _albumsOf(dynamic section) => _content(section)
      .where((e) => e != null && e.runtimeType.toString() == 'Album')
      .toList();

  // ───────────────────────────────────────────────────────────── header ──

  Widget _heroHeader(BuildContext context) {
    final theme = Theme.of(context);
    final img = Thumbnail(c.artist_.thumbnailUrl).extraHigh;
    final width = MediaQuery.sizeOf(context).width;
    Widget circle(Widget child) => Padding(
          padding: const EdgeInsets.all(6),
          child: Material(
            color: Colors.black.withOpacity(0.35),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        );
    return SliverAppBar(
      expandedHeight: (width * 0.78).clamp(260.0, 360.0),
      pinned: true,
      stretch: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      leading: circle(IconButton(
        tooltip: 'back'.tr,
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 18, color: Colors.white),
        onPressed: () =>
            Get.nestedKey(ScreenNavigationSetup.id)!.currentState!.pop(),
      )),
      flexibleSpace: LayoutBuilder(builder: (context, box) {
        // 1 = fully expanded, 0 = collapsed to the toolbar. The title starts
        // at the gutter and slides right of the back button as it collapses.
        final top = MediaQuery.paddingOf(context).top;
        final expanded = (width * 0.78).clamp(260.0, 360.0) + top;
        final collapsed = kToolbarHeight + top;
        final t = ((box.maxHeight - collapsed) / (expanded - collapsed))
            .clamp(0.0, 1.0);
        final left = HomeLayout.gutter + (1 - t) * (56 - HomeLayout.gutter);
        return FlexibleSpaceBar(
          titlePadding:
              EdgeInsets.fromLTRB(left, 0, HomeLayout.gutter, 12 + (1 - t) * 4),
          expandedTitleScale: 1.6,
          title: Text(
            c.artist_.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // The hero fades into the page colour behind the title, so the
            // page's own text colour reads on both themes.
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: -0.4,
            ),
          ),
          background: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: img,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorWidget: (_, __, ___) => ColoredBox(
                  color: homeTileColor(context),
                  child: Icon(Icons.person_rounded,
                      size: 90, color: homeMutedColor(context)),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.25),
                      Colors.transparent,
                      theme.scaffoldBackgroundColor.withOpacity(0.85),
                      theme.scaffoldBackgroundColor,
                    ],
                    stops: const [0.0, 0.35, 0.85, 1.0],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _actionRow(BuildContext context, List<MediaItem> songs) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final subs = (c.artist_.subscribers ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(HomeLayout.gutter, 0, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subs.isNotEmpty && !subs.startsWith('null'))
            Text(subs,
                style: homeCardSubtitleStyle(context).copyWith(fontSize: 13)),
          const SizedBox(height: 10),
          Row(
            children: [
              // Follow = add to Library (also drives Release Radar).
              Obx(() {
                final following = c.isAddedToLibrary.isTrue;
                return OutlinedButton(
                  onPressed: _toggleFollow,
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        following ? accent : theme.textTheme.titleMedium?.color,
                    side: BorderSide(
                        color: following
                            ? accent.withOpacity(0.6)
                            : (homeMutedColor(context) ?? Colors.grey)
                                .withOpacity(0.6)),
                    shape: const StadiumBorder(),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: Text(following ? 'following'.tr : 'follow'.tr,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                );
              }),
              _moreMenu(context, songs),
              const Spacer(),
              IconButton(
                tooltip: 'shuffle'.tr,
                icon: const Icon(Icons.shuffle_rounded, size: 26),
                onPressed: songs.isEmpty
                    ? null
                    : () => _playSongs(songs, 0, shuffle: true),
              ),
              const SizedBox(width: 4),
              Material(
                color: accent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: songs.isEmpty ? null : () => _playSongs(songs, 0),
                  child: Tooltip(
                    message: 'play'.tr,
                    child: const SizedBox.square(
                      dimension: 52,
                      child: Icon(Icons.play_arrow_rounded,
                          size: 32, color: RiffSurfaces.voidBlack),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Start radio, subscribe to the channel as a podcast, share.
  Widget _moreMenu(BuildContext context, List<MediaItem> songs) {
    final lib = Get.isRegistered<LibraryPodcastsController>()
        ? Get.find<LibraryPodcastsController>()
        : null;
    final rawId = c.artist_.browseId;
    final channelId = rawId.startsWith('MPLA') ? rawId.substring(4) : rawId;
    final subscribed =
        lib?.libraryPodcasts.any((p) => p.playlistId == channelId) ?? false;
    Widget item(IconData icon, String label) => Row(children: [
          Icon(icon, size: 20),
          const SizedBox(width: 14),
          Text(label),
        ]);
    return PopupMenuButton<String>(
      tooltip: 'more'.tr,
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) async {
        switch (v) {
          case 'radio':
            await _startRadio(songs);
          case 'podcast':
            await _togglePodcast(lib!, channelId, subscribed);
          case 'share':
            Share.share(
                "https://music.youtube.com/channel/${c.artist_.browseId}");
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
            value: 'radio', child: item(Icons.sensors, 'startRadio'.tr)),
        if (lib != null)
          PopupMenuItem(
            value: 'podcast',
            child: item(
                subscribed
                    ? Icons.remove_circle_outline_rounded
                    : Icons.podcasts_rounded,
                subscribed ? 'unsubscribePodcast'.tr : 'subscribeAsPodcast'.tr),
          ),
        PopupMenuItem(
            value: 'share', child: item(Icons.share_outlined, 'share'.tr)),
      ],
    );
  }

  Future<void> _startRadio(List<MediaItem> songs) async {
    final radioId = c.artist_.radioId;
    final player = Get.find<PlayerController>();
    var ok = false;
    if (radioId != null && radioId.isNotEmpty) {
      ok = await player.startRadio(null, playlistid: radioId);
    } else if (songs.isNotEmpty) {
      ok = await player.startRadio(songs.first);
    }
    if (ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, "radioNotAvailable".tr, size: SanckBarSize.BIG));
  }

  Future<void> _togglePodcast(
      LibraryPodcastsController lib, String id, bool subscribed) async {
    if (subscribed) {
      await lib.removeFromLibrary(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          snackbar(context, 'removeFromLib'.tr, size: SanckBarSize.MEDIUM));
      return;
    }
    final pl = Playlist(
      title: c.artist_.name,
      playlistId: id,
      thumbnailUrl: c.artist_.thumbnailUrl,
      description: c.artist_.subscribers ?? 'YouTube channel',
      kind: 'yt_channel',
    );
    final saved = await lib.subscribeYoutubeChannel(id, seed: pl);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(snackbar(
      context,
      saved != null ? 'subscribedAsPodcast'.tr : 'operationFailed'.tr,
      size: SanckBarSize.MEDIUM,
    ));
  }

  // ───────────────────────────────────────────────────────────── popular ──

  Widget _songRow(BuildContext context, List<MediaItem> songs, int i) {
    final song = songs[i];
    final art = Thumbnail(song.artUri?.toString() ?? '').medium;
    final subtitle =
        (song.extras?['album']?['name'] ?? song.artist ?? '').toString().trim();
    final player = Get.find<PlayerController>();
    final accent = Theme.of(context).colorScheme.secondary;
    return InkWell(
      onTap: () => _playSongs(songs, i),
      onLongPress: () => _openSongMenu(context, song),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(HomeLayout.gutter, 6, 0, 6),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text('${i + 1}',
                  style:
                      homeCardSubtitleStyle(context).copyWith(fontSize: 13.5)),
            ),
            const SizedBox(width: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: art,
                memCacheWidth:
                    (48 * MediaQuery.devicePixelRatioOf(context)).round(),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => ColoredBox(
                  color: homeTileColor(context),
                  child: Icon(Icons.music_note_rounded,
                      color: homeMutedColor(context)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Obx(() => Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: homeCardTitleStyle(context).copyWith(
                          fontSize: 15,
                          height: 1.25,
                          color: player.currentSong.value?.id == song.id
                              ? accent
                              : null))),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: homeCardSubtitleStyle(context)
                            .copyWith(fontSize: 12.5)),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'more'.tr,
              icon:
                  Icon(Icons.more_vert_rounded, color: homeMutedColor(context)),
              onPressed: () => _openSongMenu(context, song),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────── shelves ──

  Widget _videoShelf(BuildContext context, List<MediaItem> videos) {
    const w = 208.0;
    const h = w * 9 / 16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader('videos'.tr,
            trailing: _seeAll('Videos', 'videos'.tr)),
        SizedBox(
          height: h + HomeShelf.textBlockHeight(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
            itemCount: videos.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: HomeLayout.cardGap),
            itemBuilder: (context, i) {
              final v = videos[i];
              return SizedBox(
                width: w,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _playSongs(videos, i),
                  onLongPress: () => _openSongMenu(context, v),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: Thumbnail(v.artUri?.toString() ?? '').high,
                          width: w,
                          height: h,
                          fit: BoxFit.cover,
                          memCacheWidth:
                              (w * MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                          errorWidget: (_, __, ___) =>
                              ColoredBox(color: homeTileColor(context)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(v.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: homeCardTitleStyle(context)),
                      const SizedBox(height: 2),
                      Text(v.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: homeCardSubtitleStyle(context)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cover(BuildContext context, String url, IconData fallback) =>
      CachedNetworkImage(
        imageUrl: Thumbnail(url).high,
        fit: BoxFit.cover,
        memCacheWidth:
            (HomeLayout.shelfCard * MediaQuery.devicePixelRatioOf(context))
                .round(),
        errorWidget: (_, __, ___) => ColoredBox(
          color: homeTileColor(context),
          child: Icon(fallback, size: 40, color: homeMutedColor(context)),
        ),
      );

  Widget _releaseShelf(
      BuildContext context, String key, String title, List albums) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title, trailing: _seeAll(key, title)),
        HomeShelf(
          cardSize: HomeLayout.shelfCard,
          itemCount: albums.length,
          itemBuilder: (context, i) {
            final album = albums[i];
            return HomeShelfCard(
              size: HomeLayout.shelfCard,
              art: _cover(
                  context, '${album.thumbnailUrl ?? ''}', Icons.album_rounded),
              title: '${album.title ?? ''}',
              subtitle: '${album.year ?? ''}',
              onTap: () => _playOrOpenAlbum(album),
              onLongPress: () => _openAlbum(album),
            );
          },
        ),
      ],
    );
  }

  Widget _playlistShelf(BuildContext context, List playlists) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader('${'featuring'.tr} ${c.artist_.name}'),
        HomeShelf(
          cardSize: HomeLayout.shelfCard,
          itemCount: playlists.length,
          itemBuilder: (context, i) {
            final p = playlists[i];
            return HomeShelfCard(
              size: HomeLayout.shelfCard,
              art: _cover(context, '${p.thumbnailUrl ?? ''}',
                  Icons.queue_music_rounded),
              title: '${p.title ?? ''}',
              subtitle: '${p.description ?? ''}',
              onTap: () => _playOrOpenPlaylist(p),
              onLongPress: () => _openPlaylist(p),
            );
          },
        ),
      ],
    );
  }

  Widget _artistShelf(BuildContext context, List artists) {
    const size = 112.0;
    final scaler = MediaQuery.textScalerOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader('fansAlsoLike'.tr),
        SizedBox(
          height: size + 8 + scaler.scale(13.5) * 1.2 + 10,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
            itemCount: artists.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: HomeLayout.cardGap),
            itemBuilder: (context, i) {
              final a = artists[i];
              return SizedBox(
                width: size,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _playOrOpenArtist(a),
                  onLongPress: () => _openRelatedArtist(a),
                  child: Column(
                    children: [
                      ClipOval(
                        child: SizedBox.square(
                          dimension: size,
                          child: _cover(context, '${a.thumbnailUrl ?? ''}',
                              Icons.person_rounded),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('${a.name ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: homeCardTitleStyle(context)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _about(BuildContext context, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader('about'.tr),
        InkWell(
          onTap: () => setState(() => _aboutExpanded = !_aboutExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  maxLines: _aboutExpanded ? null : 4,
                  overflow: _aboutExpanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(height: 1.45, color: homeMutedColor(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  _aboutExpanded ? 'showLess'.tr : 'readMore'.tr,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.titleMedium?.color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────── navigation ──

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

/// Full list for one artist section (all songs, videos, albums or singles),
/// with the shared sort row; pages in more as it scrolls.
class _ArtistSectionPage extends StatelessWidget {
  const _ArtistSectionPage({
    required this.controller,
    required this.tag,
    required this.tabName,
    required this.title,
  });

  final ArtistScreenController controller;
  final String tag;
  final String tabName;
  final String title;

  ScrollController get _scroll => switch (tabName) {
        'Songs' => controller.songScrollController,
        'Videos' => controller.videoScrollController,
        'Albums' => controller.albumScrollController,
        _ => controller.singlesScrollController,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'back'.tr,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Text(controller.artist_.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Obx(() {
        if (controller.isSeparatedArtistContentFetced.isFalse ||
            !controller.sepataredContent.containsKey(tabName)) {
          return const SongListShimmer(itemCount: 8, topPadding: 12);
        }
        return SeparateTabItemWidget(
          artistControllerTag: tag,
          isResultWidget: false,
          items: controller.sepataredContent[tabName]['results'] ?? const [],
          title: tabName,
          scrollController: _scroll,
        );
      }),
    );
  }
}
