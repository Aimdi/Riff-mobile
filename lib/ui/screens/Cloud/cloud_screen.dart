import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/cloud_music_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/snackbar.dart';
import 'cloud_collection_screen.dart';
import 'cloud_play.dart';

/// Cloud: stream your own library from a self-hosted Subsonic-compatible
/// server (Navidrome, OpenSubsonic, Airsonic, Gonic, Ampache…) — the
/// Resonus-inspired counterpart to the Audiobookshelf tab.
class CloudScreen extends StatelessWidget {
  const CloudScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cloud = Get.find<CloudMusicService>();
    final topPadding = context.isLandscape ? 50.0 : 90.0;

    return Padding(
      padding: EdgeInsets.only(top: topPadding, left: 5, right: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('cloud'.tr, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(() => cloud.isConnected.value
                ? const _CloudLibraryView()
                : const CloudLoginForm()),
          ),
        ],
      ),
    );
  }
}

class CloudLoginForm extends StatefulWidget {
  const CloudLoginForm({super.key});

  @override
  State<CloudLoginForm> createState() => _CloudLoginFormState();
}

class _CloudLoginFormState extends State<CloudLoginForm> {
  final _host = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_host.text.trim().isEmpty || _user.text.trim().isEmpty) return;
    try {
      await Get.find<CloudMusicService>().login(
        serverUrl: _host.text.trim(),
        user: _user.text.trim(),
        password: _pass.text,
      );
    } catch (_) {
      // statusMessage already set by the service
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = Get.find<CloudMusicService>();
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(right: 10, bottom: 200, top: 8),
      children: [
        Text('cloudConnectTitle'.tr, style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('cloudConnectDes'.tr, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _host,
          decoration: InputDecoration(
            labelText: 'cloudServerUrl'.tr,
            hintText: 'https://music.example.com',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _user,
          decoration: InputDecoration(
            labelText: 'username'.tr,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _pass,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'password'.tr,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        Obx(() => ElevatedButton.icon(
              onPressed: cloud.isLoading.value ? null : _submit,
              icon: cloud.isLoading.value
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_outlined),
              label: Text('cloudConnect'.tr),
            )),
        Obx(() {
          final msg = cloud.statusMessage.value;
          if (msg.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(msg, style: TextStyle(color: theme.colorScheme.error)),
          );
        }),
        const SizedBox(height: 20),
        Text(
          'cloudServersHint'.tr,
          style:
              theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _CloudLibraryView extends StatefulWidget {
  const _CloudLibraryView();

  @override
  State<_CloudLibraryView> createState() => _CloudLibraryViewState();
}

class _CloudLibraryViewState extends State<_CloudLibraryView> {
  // 0 = Albums, 1 = Playlists, 2 = Songs
  int _mode = 0;
  final _search = TextEditingController();
  CloudSearchResult? _searchResult;
  bool _searchLoading = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _searchResult = null);
      return;
    }
    setState(() => _searchLoading = true);
    try {
      final res = await Get.find<CloudMusicService>().search(q);
      if (mounted) setState(() => _searchResult = res);
    } catch (_) {
      if (mounted) setState(() => _searchResult = CloudSearchResult());
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _searchResult = null);
  }

  @override
  Widget build(BuildContext context) {
    final cloud = Get.find<CloudMusicService>();
    final theme = Theme.of(context);

    return Column(
      children: [
        // Connection strip
        Obx(() => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.cloud_done, size: 22),
              title: Text(
                cloud.host.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              subtitle: Text(
                cloud.username.value,
                style: theme.textTheme.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'retry'.tr,
                    icon: const Icon(Icons.refresh, size: 22),
                    onPressed: () => cloud.refreshLibrary(),
                  ),
                  TextButton(
                    onPressed: () => cloud.logout(),
                    child: Text('disconnect'.tr),
                  ),
                ],
              ),
            )),
        // Server search
        Padding(
          padding: const EdgeInsets.only(bottom: 4, right: 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'search'.tr,
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: _clearSearch,
              ),
            ),
            onSubmitted: _runSearch,
          ),
        ),
        // Albums / Playlists / Songs bar (Audiobooks-style)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.only(left: 2, right: 8),
            child: Row(
              children: [
                _cloudTab(icon: Icons.album_outlined, label: 'albums'.tr, mode: 0),
                const SizedBox(width: 16),
                _cloudTab(
                    icon: Icons.library_music_outlined,
                    label: 'playlists'.tr,
                    mode: 1),
                const SizedBox(width: 16),
                _cloudTab(
                    icon: Icons.music_note_outlined,
                    label: 'songs'.tr,
                    mode: 2),
              ],
            ),
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
        const SizedBox(height: 8),
        Expanded(
          child: _searchLoading
              ? const Center(child: CircularProgressIndicator())
              : _searchResult != null
                  ? _SearchResultsView(result: _searchResult!)
                  : _mode == 0
                      ? const _AlbumsView()
                      : _mode == 1
                          ? const _PlaylistsView()
                          : const _SongsView(),
        ),
      ],
    );
  }

  Widget _cloudTab(
      {required IconData icon, required String label, required int mode}) {
    final theme = Theme.of(context);
    final active = _mode == mode && _searchResult == null;
    final color = active
        ? theme.colorScheme.secondary
        : theme.textTheme.bodyMedium?.color?.withOpacity(0.75);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        _clearSearch();
        setState(() => _mode = mode);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumsView extends StatelessWidget {
  const _AlbumsView();

  @override
  Widget build(BuildContext context) {
    final cloud = Get.find<CloudMusicService>();
    return Obx(() {
      if (cloud.albums.isEmpty) {
        return _EmptyState(
            icon: Icons.album_outlined, text: 'cloudNoAlbums'.tr);
      }
      final showMore = cloud.albumsHaveMore.value;
      return GridView.builder(
        padding: const EdgeInsets.only(bottom: 200, right: 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.78,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: cloud.albums.length + (showMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == cloud.albums.length) {
            return Center(
              child: TextButton.icon(
                icon: const Icon(Icons.expand_more),
                label: Text('cloudLoadMore'.tr),
                onPressed: () => cloud.fetchAlbums(loadMore: true),
              ),
            );
          }
          return _AlbumCard(album: cloud.albums[i]);
        },
      );
    });
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, this.width});
  final CloudAlbum album;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final cloud = Get.find<CloudMusicService>();
    final theme = Theme.of(context);
    final cover = cloud.coverUrl(album.coverArt);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final ok = await playCloudCollection(
          cloud: cloud,
          id: album.id,
          isPlaylist: false,
          title: album.name,
        );
        if (ok) return;
        Get.to(
          () => CloudCollectionScreen(
              collectionId: album.id, isPlaylist: false, title: album.name),
          transition: Transition.rightToLeft,
        );
      },
      onLongPress: () => Get.to(
        () => CloudCollectionScreen(
            collectionId: album.id, isPlaylist: false, title: album.name),
        transition: Transition.rightToLeft,
      ),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _CloudCover(
                    url: cover,
                    icon: Icons.album,
                    iconSize: 48,
                    width: double.infinity),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            if (album.artist != null)
              Text(
                album.artist!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistsView extends StatelessWidget {
  const _PlaylistsView();

  @override
  Widget build(BuildContext context) {
    final cloud = Get.find<CloudMusicService>();
    final theme = Theme.of(context);
    return Obx(() {
      if (cloud.playlists.isEmpty) {
        return _EmptyState(
            icon: Icons.library_music_outlined, text: 'cloudNoPlaylists'.tr);
      }
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 200, right: 8),
        itemCount: cloud.playlists.length,
        itemBuilder: (context, i) {
          final p = cloud.playlists[i];
          final count = p.songCount;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _CloudCover(
                  url: cloud.coverUrl(p.coverArt, size: 160),
                  icon: Icons.library_music,
                  iconSize: 24,
                  width: 52,
                  height: 52),
            ),
            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: count != null
                ? Text('$count ${'items'.tr}', style: theme.textTheme.bodySmall)
                : null,
            onTap: () async {
              final ok = await playCloudCollection(
                cloud: cloud,
                id: p.id,
                isPlaylist: true,
                title: p.name,
              );
              if (ok) return;
              Get.to(
                () => CloudCollectionScreen(
                    collectionId: p.id, isPlaylist: true, title: p.name),
                transition: Transition.rightToLeft,
              );
            },
            onLongPress: () => Get.to(
              () => CloudCollectionScreen(
                  collectionId: p.id, isPlaylist: true, title: p.name),
              transition: Transition.rightToLeft,
            ),
          );
        },
      );
    });
  }
}

class _SongsView extends StatelessWidget {
  const _SongsView();

  @override
  Widget build(BuildContext context) {
    final cloud = Get.find<CloudMusicService>();
    final theme = Theme.of(context);
    return Obx(() {
      if (cloud.songs.isEmpty) {
        return _EmptyState(
            icon: Icons.music_note_outlined, text: 'cloudNoSongs'.tr);
      }
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 200, right: 8),
        itemCount: cloud.songs.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            // Random slice of the library — re-roll on demand.
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('cloudRandomMix'.tr,
                        style: theme.textTheme.titleSmall),
                  ),
                  IconButton(
                    tooltip: 'playAll'.tr,
                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                    onPressed: () => playCloudSongsOrNotify(
                      cloud.toMediaItems(cloud.songs.toList()),
                      shuffle: false,
                    ),
                  ),
                  IconButton(
                    tooltip: 'shuffle'.tr,
                    icon: const Icon(Icons.casino_outlined, size: 20),
                    onPressed: () => fetchAndPlayCloudRandomMix(cloud),
                  ),
                ],
              ),
            );
          }
          final list = cloud.songs.toList();
          return CloudSongTile(songs: list, index: i - 1);
        },
      );
    });
  }
}

class _SearchResultsView extends StatelessWidget {
  const _SearchResultsView({required this.result});
  final CloudSearchResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (result.songs.isEmpty && result.albums.isEmpty) {
      return Center(child: Text('noResults'.tr));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 200, right: 8),
      children: [
        if (result.albums.isNotEmpty) ...[
          Text('albums'.tr, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: result.albums.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) =>
                  _AlbumCard(album: result.albums[i], width: 130),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (result.songs.isNotEmpty) ...[
          Text('songs'.tr, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          ...List.generate(
            result.songs.length,
            (i) => CloudSongTile(songs: result.songs, index: i),
          ),
        ],
      ],
    );
  }
}

/// One tappable song row: tap plays [songs] starting at [index]; the
/// trailing button appends the song to the current queue.
class CloudSongTile extends StatelessWidget {
  const CloudSongTile({super.key, required this.songs, required this.index});
  final List<CloudSong> songs;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cloud = Get.find<CloudMusicService>();
    final theme = Theme.of(context);
    final song = songs[index];
    final subtitleParts = [
      if (song.artist != null && song.artist!.isNotEmpty) song.artist!,
      if (song.album != null && song.album!.isNotEmpty) song.album!,
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _CloudCover(
            url: cloud.coverUrl(song.coverArt, size: 160),
            icon: Icons.music_note,
            iconSize: 22,
            width: 48,
            height: 48),
      ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(
              subtitleParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
      trailing: IconButton(
        tooltip: 'enqueueSong'.tr,
        icon: const Icon(Icons.playlist_add, size: 22),
        onPressed: () async {
          final ok = await Get.find<PlayerController>()
              .enqueueSong(cloud.toMediaItem(song));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(snackbar(
            context,
            ok ? 'songEnqueueAlert'.tr : 'operationFailed'.tr,
            size: SanckBarSize.MEDIUM,
          ));
        },
      ),
      onTap: () => Get.find<PlayerController>()
          .playPlayListSong(cloud.toMediaItems(songs), index),
    );
  }
}

/// Cover image with a music placeholder for items without art.
class _CloudCover extends StatelessWidget {
  const _CloudCover(
      {required this.url,
      required this.icon,
      required this.iconSize,
      this.width,
      this.height});
  final String url;
  final IconData icon;
  final double iconSize;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget placeholder() => Container(
          width: width,
          height: height,
          color: theme.primaryColorLight,
          child: Icon(icon, size: iconSize),
        );
    if (url.isEmpty) return placeholder();
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => placeholder(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall?.color;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: dim?.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: dim?.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }
}
