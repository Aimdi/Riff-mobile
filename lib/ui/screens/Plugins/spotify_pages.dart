import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/spotify_api_service.dart';
import '/services/spotify_auth_service.dart';
import '/services/spotify_import_service.dart';
import '/ui/navigator.dart';
import '/ui/widgets/spotify_import_dialog.dart';
import '../Home/home_layout.dart';
import 'spotify_widgets.dart';

/// One Web API client for the Spotify screens.
final spotifyApi = SpotifyApiService(auth: SpotifyAuthService());

/// What a Spotify page shows.
sealed class SpotifyPageArgs {
  const SpotifyPageArgs();
}

class SpotifyPlaylistArgs extends SpotifyPageArgs {
  const SpotifyPlaylistArgs(this.playlist, {required this.readable});
  final SpotifyPlaylistSummary playlist;

  /// Spotify shares the songs only of playlists the user owns or
  /// collaborates on.
  final bool readable;
}

class SpotifyAlbumArgs extends SpotifyPageArgs {
  const SpotifyAlbumArgs(this.album);
  final SpotifyAlbumSummary album;
}

class SpotifyArtistArgs extends SpotifyPageArgs {
  const SpotifyArtistArgs(this.artist);
  final SpotifyArtistSummary artist;
}

class SpotifySearchArgs extends SpotifyPageArgs {
  const SpotifySearchArgs();
}

void openSpotifyPage(SpotifyPageArgs args) => Get.toNamed(
      ScreenNavigationSetup.spotifyPageScreen,
      id: ScreenNavigationSetup.id,
      arguments: args,
    );

/// Routes a [SpotifyPageArgs] to its page.
class SpotifyPage extends StatelessWidget {
  const SpotifyPage({super.key, required this.args});
  final SpotifyPageArgs args;

  @override
  Widget build(BuildContext context) => switch (args) {
        SpotifyPlaylistArgs a => _PlaylistPage(args: a),
        SpotifyAlbumArgs a => _TracksPage(
            title: a.album.name,
            subtitle: [a.album.artists, a.album.year ?? '']
                .where((s) => s.isNotEmpty)
                .join(' · '),
            coverUrl: a.album.coverUrl,
            load: ({bool force = false}) =>
                spotifyApi.fetchAlbumTracks(a.album.id, force: force),
          ),
        SpotifyArtistArgs a => _ArtistPage(artist: a.artist),
        SpotifySearchArgs _ => const _SearchPage(),
      };
}

/// A list of tracks under a cover and title, with Play and Shuffle.
class _TracksPage extends StatelessWidget {
  const _TracksPage({
    required this.title,
    required this.load,
    this.subtitle = '',
    this.coverUrl,
  });
  final String title;
  final String subtitle;
  final String? coverUrl;
  final Future<List<SpotifyTrackRef>> Function({bool force}) load;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiffPageHeader(title, subtitle: subtitle.isEmpty ? null : subtitle),
          Expanded(
            child: SpotifyAsync<List<SpotifyTrackRef>>(
              load: load,
              isEmpty: (l) => l.isEmpty,
              builder: (context, tracks, reload) => RefreshIndicator(
                onRefresh: reload,
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 200),
                  itemCount: tracks.length + 1,
                  itemBuilder: (context, i) => i == 0
                      ? Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Row(children: [
                            if (coverUrl != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: HomeLayout.gutter),
                                child: SpotifyArt(url: coverUrl, size: 56),
                              ),
                            Expanded(
                                child: SpotifyPlayBar(
                                    tracks: tracks, from: title)),
                          ]),
                        )
                      : SpotifyTrackRow(
                          tracks: tracks, index: i - 1, from: title),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistPage extends StatelessWidget {
  const _PlaylistPage({required this.args});
  final SpotifyPlaylistArgs args;

  @override
  Widget build(BuildContext context) {
    final p = args.playlist;
    final owner = (p.ownerName ?? '').isEmpty
        ? ''
        : 'spotifyByOwner'.trParams({'name': p.ownerName!});
    if (args.readable) {
      return _TracksPage(
        title: p.name,
        subtitle: owner,
        coverUrl: p.coverUrl,
        load: ({bool force = false}) =>
            spotifyApi.fetchPlaylistTracks(p.id, force: force),
      );
    }
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiffPageHeader(p.name, subtitle: owner.isEmpty ? null : owner),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              SpotifyArt(url: p.coverUrl, size: 120),
              const SizedBox(height: 16),
              Text('spotifyPlaylistLocked'.tr,
                  textAlign: TextAlign.center,
                  style: homeCardSubtitleStyle(context).copyWith(fontSize: 14)),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.link_rounded),
                label: Text('spotifyImportByLink'.tr),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => SpotifyImportDialog(
                      initialUrl: 'https://open.spotify.com/playlist/${p.id}'),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _ArtistPage extends StatelessWidget {
  const _ArtistPage({required this.artist});
  final SpotifyArtistSummary artist;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiffPageHeader(artist.name),
          Expanded(
            child: SpotifyAsync<List<SpotifyAlbumSummary>>(
              load: ({bool force = false}) =>
                  spotifyApi.fetchArtistAlbums(artist.id, force: force),
              isEmpty: (l) => l.isEmpty,
              builder: (context, albums, reload) => RefreshIndicator(
                onRefresh: reload,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 200),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                          child: SpotifyArt(
                              url: artist.imageUrl,
                              size: 120,
                              round: true,
                              icon: Icons.person_rounded)),
                    ),
                    for (final a in albums) SpotifyAlbumTile(album: a),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SpotifyAlbumTile extends StatelessWidget {
  const SpotifyAlbumTile({super.key, required this.album});
  final SpotifyAlbumSummary album;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
        leading: SpotifyArt(url: album.coverUrl, icon: Icons.album_rounded),
        title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            [album.artists, album.year ?? '']
                .where((s) => s.isNotEmpty)
                .join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: homeCardSubtitleStyle(context)),
        onTap: () => openSpotifyPage(SpotifyAlbumArgs(album)),
      );
}

class SpotifyArtistTile extends StatelessWidget {
  const SpotifyArtistTile({super.key, required this.artist});
  final SpotifyArtistSummary artist;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
        leading: SpotifyArt(
            url: artist.imageUrl, round: true, icon: Icons.person_rounded),
        title: Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => openSpotifyPage(SpotifyArtistArgs(artist)),
      );
}

class _SearchPage extends StatefulWidget {
  const _SearchPage();

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final _query = TextEditingController();
  final _tracks = <SpotifyTrackRef>[];
  final _albums = <SpotifyAlbumSummary>[];
  final _artists = <SpotifyArtistSummary>[];
  var _offset = 0;
  var _hasMore = false;
  var _loading = false;
  String? _error;
  String _searched = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run({bool more = false}) async {
    final q = more ? _searched : _query.text.trim();
    if (q.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _searched = q;
        _offset = 0;
        _tracks.clear();
        _albums.clear();
        _artists.clear();
      }
    });
    try {
      final page = await spotifyApi.search(q, offset: _offset);
      if (!mounted || q != _searched) return;
      setState(() {
        _tracks.addAll(page.tracks);
        _albums.addAll(page.albums);
        _artists.addAll(page.artists);
        _hasMore = page.hasMore;
        _offset += SpotifyApiService.searchPageSize;
      });
    } catch (e) {
      if (mounted) setState(() => _error = spotifyErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(HomeLayout.gutter, 18, 16, 4),
          child: Text(t, style: homeSectionTitleStyle(context)),
        );
    final from = 'spotifySearch'.tr;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiffPageHeader('spotifySearch'.tr),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                HomeLayout.gutter, 4, HomeLayout.gutter, 4),
            child: TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'spotifySearchHint'.tr,
                prefixIcon: const Icon(Icons.search_rounded),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onSubmitted: (_) => _run(),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 200),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: homeCardSubtitleStyle(context)),
                  ),
                if (_tracks.isNotEmpty) ...[
                  header('songs'.tr),
                  for (var i = 0; i < _tracks.length; i++)
                    SpotifyTrackRow(tracks: _tracks, index: i, from: from),
                ],
                if (_albums.isNotEmpty) ...[
                  header('spotifyAlbums'.tr),
                  for (final a in _albums) SpotifyAlbumTile(album: a),
                ],
                if (_artists.isNotEmpty) ...[
                  header('spotifyArtists'.tr),
                  for (final a in _artists) SpotifyArtistTile(artist: a),
                ],
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_hasMore)
                  Center(
                    child: TextButton(
                      onPressed: () => _run(more: true),
                      child: Text('spotifyLoadMore'.tr),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
