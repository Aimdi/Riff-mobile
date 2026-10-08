import '../Home/home_layout.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

import '/models/media_Item_builder.dart';
import '/models/playlist.dart';
import '/services/spotify_api_service.dart';
import '/services/spotify_home.dart';
import '/services/spotify_auth_service.dart';
import '/services/spotify_import_service.dart';
import '/services/spotify_connect.dart';
import '/services/spotify_like_sync.dart';
import '/ui/widgets/add_to_playlist.dart' show addSongsToLikedSongs;
import '/ui/screens/Library/library_controller.dart';
import '/ui/screens/Settings/spotify_login_screen.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/snackbar.dart';
import 'spotify_pages.dart';
import 'spotify_widgets.dart';

/// Sections of the signed-in hub.
enum SpotifySection {
  liked('spotifyLiked'),
  playlists('spotifyPlaylists'),
  albums('spotifyAlbums'),
  artists('spotifyArtists'),
  topTracks('spotifyTopTracks'),
  topArtists('spotifyTopArtists'),
  recent('spotifyRecent');

  const SpotifySection(this.labelKey);
  final String labelKey;
}

const _recentScope = 'user-read-recently-played';

/// Spotify: sign in with your own Spotify app, then browse your library
/// (Liked Songs, playlists, albums, artists, top and recent plays) and
/// search Spotify. Everything plays through Riff's own player: each track is
/// matched to YouTube Music, and you can change the match.
///
/// The client id is entered here rather than shipped in the APK: one
/// embedded id would put every install under a single Spotify app, which is
/// capped at a handful of users in Development Mode.
class SpotifyBridgeScreen extends StatefulWidget {
  const SpotifyBridgeScreen({super.key});

  @override
  State<SpotifyBridgeScreen> createState() => _SpotifyBridgeScreenState();
}

class _SpotifyBridgeScreenState extends State<SpotifyBridgeScreen> {
  final _clientIdController = TextEditingController();
  var _connected = SpotifyAuthService.isConnected;
  var _section = SpotifySection.liked;
  late Future<SpotifyUser?> _me = _loadMe();
  final _busy = false.obs;
  final _status = ''.obs;
  final _progress = 0.0.obs;

  @override
  void initState() {
    super.initState();
    _clientIdController.text = SpotifyAuthService.clientId ?? '';
    // Send any like changes still waiting.
    if (_connected) {
      SpotifyLikeSync.flushSoon(delay: const Duration(seconds: 2));
    }
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    super.dispose();
  }

  Future<SpotifyUser?> _loadMe() async {
    if (!_connected) return null;
    try {
      return await spotifyApi.fetchMe();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveClientId() async {
    await SpotifyAuthService.setClientId(_clientIdController.text);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context, 'spotifyClientIdSaved'.tr,
          size: SanckBarSize.MEDIUM));
    }
  }

  Future<void> _signIn() async {
    if (!SpotifyAuthService.isConfigured) {
      _status.value = 'spotifyNoClientId'.tr;
      return;
    }
    final ok = await Get.to(() => const SpotifyLoginScreen());
    if (ok == true) {
      await SpotifyApiService.clearCache();
      // A new (or the same) account: Home's Spotify shelves start over.
      await SpotifyHome.clear();
      SpotifyHome.refresh(force: true);
      setState(() {
        _connected = true;
        _status.value = '';
        _me = _loadMe();
      });
    }
  }

  Future<void> _signOut() async {
    await SpotifyAuthService.disconnect();
    await SpotifyLikeSync.forgetAccount();
    await SpotifyConnect.forgetAccount();
    await SpotifyApiService.clearCache();
    await SpotifyHome.clear();
    setState(() {
      _connected = false;
      _status.value = '';
    });
  }

  Future<void> _import(SpotifyPlaylistSummary summary) async {
    if (_busy.value) return;
    _busy.value = true;
    _progress.value = 0.05;
    _status.value = 'spotifyImportFetching'.tr;
    try {
      if (!Get.isRegistered<SpotifyImportService>()) {
        Get.put(SpotifyImportService(), permanent: false);
      }
      final importer = Get.find<SpotifyImportService>();
      final collection = await spotifyApi.fetchPlaylistAsImport(summary);
      if (collection.tracks.isEmpty) {
        throw StateError('spotifyImportNoMatches'.tr);
      }
      _progress.value = 0.15;
      final items = await importer.resolveTracksToYtm(
        collection.tracks,
        onProgress: (done, total) {
          _progress.value = 0.15 + 0.75 * (done / total);
          _status.value = '${'spotifyImportResolving'.tr} $done / $total';
        },
      );
      if (items.isEmpty) throw StateError('spotifyImportNoMatches'.tr);

      _status.value = 'spotifyImportSaving'.tr;
      _progress.value = 0.95;

      final playlistId = 'LIBSP${DateTime.now().millisecondsSinceEpoch}';
      final playlist = Playlist(
        title: '${summary.name} (Spotify)',
        playlistId: playlistId,
        thumbnailUrl: summary.coverUrl ??
            items.first.artUri?.toString() ??
            Playlist.thumbPlaceholderUrl,
        description: 'importedFromSpotify'.tr,
        isCloudPlaylist: false,
      );

      final plBox = await Hive.openBox('LibraryPlaylists');
      await plBox.put(playlistId, playlist.toJson());
      final songsBox = await Hive.openBox(playlistId);
      await songsBox.putAll({
        for (var i = 0; i < items.length; i++)
          i: MediaItemBuilder.toJson(items[i]),
      });
      // Both boxes stay open: Hive shares one instance with the library,
      // discovery and the add-to-playlist sheet.

      if (Get.isRegistered<LibraryPlaylistsController>()) {
        Get.find<LibraryPlaylistsController>().refreshLib();
      }

      _progress.value = 1.0;
      _status.value =
          '${'spotifyImportDone'.tr} (${items.length}/${collection.tracks.length})';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context,
          '${playlist.title}: ${items.length} ${'songs'.tr}',
          size: SanckBarSize.MEDIUM,
        ));
      }
    } catch (e) {
      _status.value = e is StateError ? e.message : spotifyErrorText(e);
      _progress.value = 0;
    } finally {
      _busy.value = false;
    }
  }

  /// Turn on a feature that needs more Spotify permissions than the current
  /// sign-in has: explain, sign in again, and turn it back off when the
  /// permissions still aren't there.
  Future<void> _enableWithScopes({
    required Future<void> Function(bool on) setEnabled,
    required bool Function() hasAccess,
    required String title,
    required String message,
  }) async {
    await setEnabled(true);
    if (hasAccess() || !mounted) return;
    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('cancel'.tr)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('spotifySignIn'.tr)),
        ],
      ),
    );
    if (again == true) await _signIn();
    if (!hasAccess()) await setEnabled(false);
    if (mounted) setState(() {});
  }

  Future<void> _setLikeSync(bool on) async {
    if (!on) {
      await SpotifyLikeSync.setEnabled(false);
      return;
    }
    await _enableWithScopes(
      setEnabled: SpotifyLikeSync.setEnabled,
      hasAccess: () => SpotifyLikeSync.hasWriteAccess,
      title: 'spotifyLikeSync'.tr,
      message: 'spotifyLikeSyncSignIn'.tr,
    );
    if (SpotifyLikeSync.enabled) {
      SpotifyLikeSync.flushSoon(delay: const Duration(seconds: 2));
    }
  }

  Future<void> _setConnect(bool on) async {
    if (!on) {
      await SpotifyConnect.setEnabled(false);
      if (mounted) setState(() {});
      return;
    }
    await _enableWithScopes(
      setEnabled: SpotifyConnect.setEnabled,
      hasAccess: () => SpotifyConnect.hasAccess,
      title: 'spotifyConnect'.tr,
      message: 'spotifyConnectSignIn'.tr,
    );
  }

  Future<void> _importLikes() async {
    if (_busy.value) return;
    _busy.value = true;
    _progress.value = 0.05;
    _status.value = 'spotifyImportFetching'.tr;
    try {
      final (added, total) = await SpotifyLikeSync.importLikesToFavorites(
        addSongsToLikedSongs,
        onProgress: (done, total) {
          _progress.value = done / total;
          _status.value = '${'spotifyImportResolving'.tr} $done / $total';
        },
      );
      _status.value = 'spotifyImportLikesDone'
          .trParams({'added': '$added', 'total': '$total'});
    } catch (e) {
      _status.value = spotifyErrorText(e);
    } finally {
      _busy.value = false;
      _progress.value = 0;
    }
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          // Sheet rows per RIFF_UI_RESTYLE.md §5.10.
          child: ListTileTheme.merge(
            titleTextStyle: Theme.of(ctx).textTheme.bodyLarge,
            iconColor: Theme.of(ctx).colorScheme.onSurface,
            child: IconTheme.merge(
              data: const IconThemeData(size: RiffComponentSizes.headerIcon),
              child: Wrap(children: [
                SwitchListTile(
                  secondary: const Icon(Icons.favorite_border_rounded),
                  title: Text('spotifyLikeSync'.tr),
                  subtitle: Text('spotifyLikeSyncDes'.tr,
                      style: homeCardSubtitleStyle(ctx)),
                  value: SpotifyLikeSync.enabled,
                  onChanged: (v) async {
                    Navigator.of(ctx).pop();
                    await _setLikeSync(v);
                  },
                ),
                Obx(() {
                  final n = SpotifyLikeSync.pending.value;
                  final err = SpotifyLikeSync.lastError.value;
                  if (!SpotifyLikeSync.enabled || (n == 0 && err.isEmpty)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(
                        left: RiffSpacing.unit * 18,
                        right: RiffSpacing.lg,
                        bottom: RiffSpacing.sm),
                    child: Text(
                        [
                          if (n > 0)
                            'spotifyLikeSyncPending'.trParams({'n': '$n'}),
                          if (err.isNotEmpty)
                            spotifyErrorKey(SpotifyErrorKind.values.firstWhere(
                                    (k) => k.name == err,
                                    orElse: () => SpotifyErrorKind.server))
                                .trParams({'s': '0', 'm': '10'}),
                        ].join('\n'),
                        style: homeCardSubtitleStyle(ctx)),
                  );
                }),
                SwitchListTile(
                  secondary: const Icon(Icons.speaker_group_rounded),
                  title: Text('spotifyConnect'.tr),
                  subtitle: Text('spotifyConnectDes'.tr,
                      style: homeCardSubtitleStyle(ctx)),
                  value: SpotifyConnect.enabled,
                  onChanged: (v) async {
                    Navigator.of(ctx).pop();
                    await _setConnect(v);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_add_check_rounded),
                  title: Text('spotifyImportLikes'.tr),
                  subtitle: Text('spotifyImportLikesDes'.tr,
                      style: homeCardSubtitleStyle(ctx)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _importLikes();
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiffPageHeader('spotifyBridge'.tr, actions: [
            if (_connected) ...[
              if (SpotifyConnect.enabled)
                IconButton(
                  tooltip: 'spotifyConnect'.tr,
                  icon: const Icon(Icons.speaker_group_rounded),
                  onPressed: () => openSpotifyPage(const SpotifyConnectArgs()),
                ),
              IconButton(
                tooltip: 'spotifyRadio'.tr,
                icon: const Icon(Icons.radio_rounded),
                onPressed: () => startSpotifyRadio(context),
              ),
              IconButton(
                tooltip: 'spotifySearch'.tr,
                icon: const Icon(Icons.search_rounded),
                onPressed: () => openSpotifyPage(const SpotifySearchArgs()),
              ),
              IconButton(
                tooltip: 'spotifySettings'.tr,
                icon: const Icon(Icons.tune_rounded),
                onPressed: _showSettings,
              ),
            ],
          ]),
          Expanded(
            child: Obx(() {
              // Spotify ending the session sends us back to sign-in.
              SpotifyAuthService.sessionExpired.value;
              return _connected && SpotifyAuthService.isConnected
                  ? _hub(context)
                  : _setup(context);
            }),
          ),
        ],
      ),
    );
  }

  // ── Signed out: set up and sign in ─────────────────────────────────

  Widget _setup(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Get.find<ThemeController>().accentColor.value;
    return Obx(() => ListView(
          padding: const EdgeInsets.only(
              left: RiffSpacing.lg,
              top: RiffSpacing.sm,
              right: RiffSpacing.lg,
              bottom: RiffSpacing.x3l),
          children: [
            if (SpotifyAuthService.sessionExpired.value)
              _Banner(
                  icon: Icons.lock_clock_outlined,
                  text: 'spotifySessionEnded'.tr),
            Text('spotifyBridgeDes'.tr, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _clientIdController,
              decoration: InputDecoration(
                labelText: 'spotifyClientId'.tr,
                hintText: '32-character id from developer.spotify.com',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixIcon: IconButton(
                  tooltip: 'save'.tr,
                  icon: const Icon(Icons.check),
                  onPressed: _saveClientId,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text('spotifyOpenDashboard'.tr),
                onPressed: () => launchUrl(
                  Uri.parse('https://developer.spotify.com/dashboard'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
            // The dashboard matches this literally; a mismatch is the most
            // common reason sign-in fails with an opaque error.
            SelectableText(
              '${'spotifyRedirectUri'.tr}: ${SpotifyAuthService.redirectUri}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: accent),
              onPressed: _signIn,
              icon: const Icon(Icons.login),
              label: Text('spotifySignIn'.tr),
            ),
            if (_status.value.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_status.value, style: theme.textTheme.bodySmall),
            ],
          ],
        ));
  }

  // ── Signed in: the library ─────────────────────────────────────────

  Widget _hub(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: HomeLayout.gutter, right: RiffSpacing.xs),
          child: Row(children: [
            Expanded(
              child: FutureBuilder<SpotifyUser?>(
                future: _me,
                builder: (context, snap) => Text(
                  snap.data == null
                      ? 'spotifyConnected'.tr
                      : 'spotifySignedInAs'.trParams({'name': snap.data!.name}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: homeCardSubtitleStyle(context),
                ),
              ),
            ),
            TextButton(onPressed: _signOut, child: Text('spotifySignOut'.tr)),
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
            children: [
              for (final s in SpotifySection.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s.labelKey.tr),
                    selected: s == _section,
                    onSelected: (_) => setState(() => _section = s),
                  ),
                ),
            ],
          ),
        ),
        Obx(() => _busy.value || _status.value.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(
                    left: HomeLayout.gutter,
                    top: RiffSpacing.sm,
                    right: HomeLayout.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_busy.value)
                      LinearProgressIndicator(
                          value: _progress.value <= 0 || _progress.value >= 1
                              ? null
                              : _progress.value,
                          minHeight: 3),
                    if (_status.value.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_status.value,
                            style: homeCardSubtitleStyle(context)),
                      ),
                  ],
                ),
              )
            : const SizedBox.shrink()),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey(_section),
            child: _sectionBody(context, _section),
          ),
        ),
      ],
    );
  }

  Widget _tracks(Future<List<SpotifyTrackRef>> Function({bool force}) load,
          String from) =>
      SpotifyAsync<List<SpotifyTrackRef>>(
        load: load,
        isEmpty: (l) => l.isEmpty,
        builder: (context, tracks, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 200),
            itemCount: tracks.length + 1,
            itemBuilder: (context, i) => i == 0
                ? SpotifyPlayBar(tracks: tracks, from: from)
                : SpotifyTrackRow(tracks: tracks, index: i - 1, from: from),
          ),
        ),
      );

  Widget _list<T>(Future<List<T>> Function({bool force}) load,
          Widget Function(T item) tile) =>
      SpotifyAsync<List<T>>(
        load: load,
        isEmpty: (l) => l.isEmpty,
        builder: (context, items, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 200),
            itemCount: items.length,
            itemBuilder: (context, i) => tile(items[i]),
          ),
        ),
      );

  Widget _sectionBody(BuildContext context, SpotifySection s) {
    switch (s) {
      case SpotifySection.liked:
        return _tracks(spotifyApi.fetchLikedSongs, s.labelKey.tr);
      case SpotifySection.topTracks:
        return _tracks(spotifyApi.fetchTopTracks, s.labelKey.tr);
      case SpotifySection.recent:
        if (SpotifyAuthService.lacksScope(_recentScope)) {
          return _Banner(
            icon: Icons.history_rounded,
            text: 'spotifyNeedsReconsent'.tr,
            action:
                TextButton(onPressed: _signIn, child: Text('spotifySignIn'.tr)),
          );
        }
        return _tracks(spotifyApi.fetchRecentlyPlayed, s.labelKey.tr);
      case SpotifySection.albums:
        return _list<SpotifyAlbumSummary>(
            spotifyApi.fetchSavedAlbums, (a) => SpotifyAlbumTile(album: a));
      case SpotifySection.artists:
        return _list<SpotifyArtistSummary>(spotifyApi.fetchFollowedArtists,
            (a) => SpotifyArtistTile(artist: a));
      case SpotifySection.topArtists:
        return _list<SpotifyArtistSummary>(
            spotifyApi.fetchTopArtists, (a) => SpotifyArtistTile(artist: a));
      case SpotifySection.playlists:
        return SpotifyAsync<(List<SpotifyPlaylistSummary>, SpotifyUser?)>(
          load: ({bool force = false}) async => (
            await spotifyApi.fetchPlaylists(force: force),
            await _me,
          ),
          isEmpty: (r) => r.$1.isEmpty,
          emptyText: 'spotifyNoPlaylists'.tr,
          builder: (context, r, reload) => RefreshIndicator(
            onRefresh: reload,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 200),
              itemCount: r.$1.length,
              itemBuilder: (context, i) => _playlistTile(r.$1[i], r.$2),
            ),
          ),
        );
    }
  }

  Widget _playlistTile(SpotifyPlaylistSummary p, SpotifyUser? me) {
    final readable = p.readableBy(me?.id);
    final sub = [
      if (p.trackCount > 0) '${p.trackCount} ${'songs'.tr}',
      if (!readable && (p.ownerName ?? '').isNotEmpty)
        'spotifyByOwner'.trParams({'name': p.ownerName!}),
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.only(left: HomeLayout.gutter, right: 4),
      leading: SpotifyArt(
          url: p.coverUrl, icon: Icons.queue_music_rounded, playlist: p),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: homeCardSubtitleStyle(context)),
      onTap: () => openSpotifyPage(SpotifyPlaylistArgs(p, readable: readable)),
      trailing: readable
          ? Obx(() => IconButton(
                tooltip: 'import'.tr,
                icon: const Icon(Icons.download_for_offline_outlined),
                onPressed: _busy.value ? null : () => _import(p),
              ))
          : Icon(Icons.lock_outline_rounded,
              size: 18, color: homeMutedColor(context)),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(
            horizontal: HomeLayout.gutter, vertical: RiffSpacing.sm),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: homeTileColor(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          if (action != null) action!,
        ]),
      );
}
