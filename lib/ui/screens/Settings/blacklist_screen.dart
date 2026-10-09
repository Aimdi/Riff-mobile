import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/ban_service.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '../Home/home_layout.dart';

/// Settings › Never play: everything kept out of mixes, Riff Wave, radio,
/// autoplay and recommendations (artists, albums and playlists, songs),
/// with a remove button on each. Playing something on purpose still works.
class BlacklistScreen extends StatefulWidget {
  const BlacklistScreen({super.key});

  @override
  State<BlacklistScreen> createState() => _BlacklistScreenState();
}

class _BlacklistScreenState extends State<BlacklistScreen> {
  /// Called after the (awaited) unban: the screen may be gone by then.
  void _removed(String label, Future<void> Function() undo) {
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('blacklistRemoved'.trParams({'name': label})),
        action: SnackBarAction(
          label: 'undo'.tr,
          onPressed: () async {
            await undo();
            if (mounted) setState(() {});
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final artists = BanService.allArtists
      ..sort((a, b) =>
          '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
    final collections = BanService.allCollections;
    final songs = BanService.all;
    final empty = artists.isEmpty && collections.isEmpty && songs.isEmpty;

    Widget header(String title, int count) => Padding(
          padding: const EdgeInsets.only(
              left: HomeLayout.gutter,
              top: RiffSpacing.xl,
              right: RiffSpacing.lg,
              bottom: RiffSpacing.xs),
          child: Text('$title · $count', style: homeSectionTitleStyle(context)),
        );

    Widget row({
      required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onRemove,
    }) =>
        ListTile(
          contentPadding: const EdgeInsets.only(
              left: HomeLayout.gutter, right: RiffSpacing.xs),
          // Full-width hairline inside the row's bottom edge (§5.2).
          shape: Border(
              bottom:
                  BorderSide(color: Theme.of(context).dividerColor, width: 0)),
          leading: Icon(icon, color: homeMutedColor(context)),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: subtitle == null || subtitle.isEmpty
              ? null
              : Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: homeCardSubtitleStyle(context)),
          trailing: IconButton(
            tooltip: 'blacklistRemove'.tr,
            icon: Icon(Icons.remove_circle_outline_rounded,
                size: RiffComponentSizes.trailingIcon,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            onPressed: onRemove,
          ),
        );

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiffPageHeader('blacklistTitle'.tr, subtitle: 'blacklistDes'.tr),
          Expanded(
            child: empty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(RiffSpacing.x3l),
                      child: Text('blacklistEmpty'.tr,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: homeMutedColor(context))),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: RiffSpacing.listEnd),
                    children: [
                      if (artists.isNotEmpty) ...[
                        header('blacklistArtists'.tr, artists.length),
                        for (final a in artists)
                          row(
                            icon: Icons.person_off_outlined,
                            title: '${a['name']}',
                            onRemove: () async {
                              final name = '${a['name']}';
                              await BanService.unbanArtist('${a['key']}');
                              _removed(
                                  name,
                                  () =>
                                      BanService.banArtist(name).then((_) {}));
                            },
                          ),
                      ],
                      if (collections.isNotEmpty) ...[
                        header('blacklistCollections'.tr, collections.length),
                        for (final c in collections)
                          row(
                            icon: c['type'] == 'album'
                                ? Icons.album_outlined
                                : Icons.playlist_remove_rounded,
                            title: '${c['title']}',
                            subtitle: c['type'] == 'album'
                                ? 'album'.tr
                                : 'playlist'.tr,
                            onRemove: () async {
                              await BanService.unbanCollection('${c['id']}');
                              _removed(
                                  '${c['title']}',
                                  () => BanService.banCollection('${c['id']}',
                                          '${c['title']}', '${c['type']}')
                                      .then((_) {}));
                            },
                          ),
                      ],
                      if (songs.isNotEmpty) ...[
                        header('blacklistSongs'.tr, songs.length),
                        for (final s in songs)
                          row(
                            icon: Icons.music_off_outlined,
                            title: '${s['title']}',
                            subtitle: '${s['artist']}',
                            onRemove: () async {
                              await BanService.unban('${s['id']}');
                              _removed(
                                  '${s['title']}',
                                  () => BanService.banRaw('${s['id']}',
                                      '${s['title']}', '${s['artist']}'));
                            },
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
