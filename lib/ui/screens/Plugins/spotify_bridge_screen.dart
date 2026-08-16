import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

import '/models/media_Item_builder.dart';
import '/models/playlist.dart';
import '/models/playling_from.dart';
import '/services/spotify_api_service.dart';
import '/services/spotify_auth_service.dart';
import '/services/spotify_import_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Library/library_controller.dart';
import '/ui/screens/Settings/spotify_login_screen.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/snackbar.dart';

/// Spotify bridge: sign in with your own Spotify app, browse your playlists,
/// and import one into Riff — the tracks are matched and played from Riff's
/// existing free sources.
///
/// The client id is entered here rather than shipped in the APK: one embedded
/// id would put every install under a single Spotify app, which is capped at
/// 25 manually-added users in development mode.
class SpotifyBridgeScreen extends StatefulWidget {
  const SpotifyBridgeScreen({super.key});

  @override
  State<SpotifyBridgeScreen> createState() => _SpotifyBridgeScreenState();
}

class _SpotifyBridgeScreenState extends State<SpotifyBridgeScreen> {
  final _clientIdController = TextEditingController();
  final _connected = false.obs;
  final _loading = false.obs;
  final _status = ''.obs;
  final _progress = 0.0.obs;
  final _playlists = <SpotifyPlaylistSummary>[].obs;

  @override
  void initState() {
    super.initState();
    _clientIdController.text = SpotifyAuthService.clientId ?? '';
    _connected.value = SpotifyAuthService.isConnected;
    if (_connected.value) _loadPlaylists();
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    super.dispose();
  }

  SpotifyApiService get _api => SpotifyApiService(auth: SpotifyAuthService());

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
      _connected.value = true;
      _status.value = '';
      await _loadPlaylists();
    }
  }

  Future<void> _signOut() async {
    await SpotifyAuthService.disconnect();
    _connected.value = false;
    _playlists.clear();
    _status.value = '';
  }

  Future<void> _loadPlaylists() async {
    _loading.value = true;
    _status.value = 'spotifyLoadingLibrary'.tr;
    try {
      final list = await _api.fetchPlaylists();
      _playlists.assignAll(list);
      // An empty list after a successful call is a real, if unusual, state —
      // distinguish it from a failure so the user is not left guessing.
      _status.value = list.isEmpty ? 'spotifyNoPlaylists'.tr : '';
    } catch (e) {
      _status.value = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context,
          'operationFailed'.tr,
          size: SanckBarSize.MEDIUM,
        ));
      }
    } finally {
      _loading.value = false;
    }
  }

  Future<List<MediaItem>> _resolvePlaylist(
      SpotifyPlaylistSummary summary) async {
    if (!Get.isRegistered<SpotifyImportService>()) {
      Get.put(SpotifyImportService(), permanent: false);
    }
    final importer = Get.find<SpotifyImportService>();
    final collection = await _api.fetchPlaylistAsImport(summary);
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
    return items;
  }

  Future<void> _play(SpotifyPlaylistSummary summary) async {
    if (_loading.value) return;
    _loading.value = true;
    _progress.value = 0.05;
    _status.value = 'spotifyImportFetching'.tr;
    try {
      final items = await _resolvePlaylist(summary);
      if (!Get.isRegistered<PlayerController>()) return;
      await Get.find<PlayerController>().playPlayListSong(
        items,
        0,
        playfrom: PlaylingFrom(
          type: PlaylingFromType.PLAYLIST,
          name: summary.name,
        ),
      );
      _progress.value = 1.0;
      _status.value = '${'play'.tr} · ${items.length} ${'songs'.tr}';
    } catch (e) {
      _status.value = e.toString().replaceFirst('Exception: ', '');
      _progress.value = 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context,
          'operationFailed'.tr,
          size: SanckBarSize.MEDIUM,
        ));
      }
    } finally {
      _loading.value = false;
    }
  }

  Future<void> _import(SpotifyPlaylistSummary summary) async {
    if (_loading.value) return;
    _loading.value = true;
    _progress.value = 0.05;
    _status.value = 'spotifyImportFetching'.tr;
    try {
      final items = await _resolvePlaylist(summary);

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
      for (var i = 0; i < items.length; i++) {
        await songsBox.put(i, MediaItemBuilder.toJson(items[i]));
      }
      await songsBox.close();
      await plBox.close();

      Get.find<LibraryPlaylistsController>().refreshLib();

      _progress.value = 1.0;
      _status.value =
          '${'spotifyImportDone'.tr} (${items.length}/${summary.trackCount})';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context,
          '${playlist.title}: ${items.length} ${'songs'.tr}',
          size: SanckBarSize.MEDIUM,
        ));
      }
    } catch (e) {
      _status.value = e.toString().replaceFirst('Exception: ', '');
      _progress.value = 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context,
          'operationFailed'.tr,
          size: SanckBarSize.MEDIUM,
        ));
      }
    } finally {
      _loading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Get.find<ThemeController>().accentColor.value;

    return Scaffold(
      backgroundColor: theme.canvasColor,
      appBar: AppBar(title: Text('spotifyBridge'.tr)),
      body: Obx(() {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text('spotifyBridgeDes'.tr, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),

            // --- client id ---
            TextField(
              controller: _clientIdController,
              enabled: !_loading.value,
              decoration: InputDecoration(
                labelText: 'spotifyClientId'.tr,
                hintText: '32-character id from developer.spotify.com',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixIcon: IconButton(
                  tooltip: 'save'.tr,
                  icon: const Icon(Icons.check),
                  onPressed: _loading.value ? null : _saveClientId,
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

            // --- sign in / out ---
            if (!_connected.value)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: accent),
                onPressed: _loading.value ? null : _signIn,
                icon: const Icon(Icons.login),
                label: Text('spotifySignIn'.tr),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text('spotifyConnected'.tr,
                        style: theme.textTheme.titleSmall),
                  ),
                  TextButton(
                    onPressed: _loading.value ? null : _signOut,
                    child: Text('spotifySignOut'.tr),
                  ),
                  IconButton(
                    tooltip: 'refresh'.tr,
                    icon: const Icon(Icons.refresh),
                    onPressed: _loading.value ? null : _loadPlaylists,
                  ),
                ],
              ),

            if (_loading.value || _progress.value > 0) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _progress.value <= 0 || _progress.value >= 1
                    ? null
                    : _progress.value,
                minHeight: 4,
              ),
            ],
            if (_status.value.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_status.value, style: theme.textTheme.bodySmall),
            ],

            // --- playlists ---
            if (_playlists.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('spotifyYourPlaylists'.tr,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._playlists.map((p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: _loading.value ? null : () => _play(p),
                    leading: p.coverUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(p.coverUrl!,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.queue_music)),
                          )
                        : const Icon(Icons.queue_music),
                    title: Text(p.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${p.trackCount} ${'songs'.tr}'),
                    trailing: IconButton(
                      tooltip: 'import'.tr,
                      icon: const Icon(Icons.cloud_download),
                      onPressed: _loading.value ? null : () => _import(p),
                    ),
                  )),
            ],
          ],
        );
      }),
    );
  }
}
