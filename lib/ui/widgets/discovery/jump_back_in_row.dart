import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../../models/media_Item_builder.dart';
import '../../../services/discovery/discovery_types.dart';
import '../../player/player_controller.dart';
import '../../screens/Home/home_layout.dart';
import '../image_widget.dart';
import '../snackbar.dart';

/// Spotify-like "Jump back in" — recently played songs from Hive `LIBRP`.
class JumpBackInRow extends StatefulWidget {
  const JumpBackInRow({super.key});

  @override
  State<JumpBackInRow> createState() => _JumpBackInRowState();
}

class _JumpBackInRowState extends State<JumpBackInRow> {
  List<MediaItem> _recentFirst = const [];

  @override
  void initState() {
    super.initState();
    if (Hive.isBoxOpen('LIBRP')) {
      _recentFirst = _readRecentFirst(Hive.box('LIBRP'));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAndLoad());
    }
  }

  Future<void> _openAndLoad() async {
    try {
      final box = await Hive.openBox('LIBRP');
      if (!mounted) return;
      setState(() => _recentFirst = _readRecentFirst(box));
    } catch (_) {}
  }

  static List<MediaItem> _readRecentFirst(Box box) {
    if (box.isEmpty) return const [];
    final tracks = <MediaItem>[];
    for (final raw in box.values) {
      try {
        final item = MediaItemBuilder.fromJson(raw);
        if (item.id.isNotEmpty) tracks.add(item);
      } catch (_) {}
    }
    return tracks.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!Hive.isBoxOpen('LIBRP') && _recentFirst.isEmpty) {
      return const SizedBox.shrink();
    }
    final tracks = _recentFirst.isNotEmpty
        ? _recentFirst
        : (Hive.isBoxOpen('LIBRP')
            ? _readRecentFirst(Hive.box('LIBRP'))
            : const <MediaItem>[]);
    if (tracks.isEmpty) return const SizedBox.shrink();

    final visible = tracks.length > 10 ? tracks.sublist(0, 10) : tracks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader('jumpBackIn'.tr),
        HomeShelf(
          cardSize: HomeLayout.shelfCard,
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final song = visible[i];
            return HomeShelfCard(
              size: HomeLayout.shelfCard,
              art: ImageWidget(
                song: song,
                size: HomeLayout.shelfCard,
                borderRadius: 0,
              ),
              title: song.title,
              subtitle: song.artist ?? '',
              onTap: () async {
                final ok = await Get.find<PlayerController>()
                    .playPlayListSong(tracks, i, source: DiscoverySource.home);
                if (!ok) snackOperationFailed();
              },
              onLongPress: () {
                final player = Get.find<PlayerController>();
                showModalBottomSheet<void>(
                  context: context,
                  useRootNavigator: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(10)),
                  ),
                  builder: (ctx) => SafeArea(
                    child: Wrap(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.play_arrow_rounded),
                          title: Text('play'.tr),
                          onTap: () async {
                            Navigator.pop(ctx);
                            final ok = await player.playPlayListSong(tracks, i,
                                source: DiscoverySource.home);
                            if (!ok) snackOperationFailed();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.playlist_play),
                          title: Text('playNext'.tr),
                          onTap: () async {
                            Navigator.pop(ctx);
                            final ok = await player.playNext(song);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(snackbar(
                              context,
                              ok
                                  ? "${"playnextMsg".tr} ${song.title}"
                                  : "operationFailed".tr,
                              size: SanckBarSize.MEDIUM,
                            ));
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.sensors),
                          title: Text('startRadio'.tr),
                          onTap: () async {
                            Navigator.pop(ctx);
                            final ok = await player.startRadio(song);
                            if (!context.mounted || ok) return;
                            ScaffoldMessenger.of(context).showSnackBar(snackbar(
                              context,
                              "radioNotAvailable".tr,
                              size: SanckBarSize.MEDIUM,
                            ));
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
