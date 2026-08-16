import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../../models/media_Item_builder.dart';
import '../../player/player_controller.dart';
import '../../utils/riff_tokens.dart';
import '../../utils/theme_controller.dart';
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
    const cardSize = 112.0;
    final title = 'jumpBackIn'.tr;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? RiffSurfaces.textMuted
        : Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.only(left: 12, top: 8, bottom: 10, right: 12),
          child: Text(
            title == 'jumpBackIn' ? 'Jump back in' : title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
                  letterSpacing: -0.35,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(
          height: 156,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 12, right: 12),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final song = visible[i];
              return Padding(
                padding:
                    EdgeInsets.only(right: i == visible.length - 1 ? 0 : 12),
                child: SizedBox(
                  width: cardSize,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
                    onTap: () async {
                      final ok = await Get.find<PlayerController>()
                          .playPlayListSong(tracks, i);
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
                                  final ok =
                                      await player.playPlayListSong(tracks, i);
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      snackbar(
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      snackbar(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(RiffTokens.radiusSm),
                          child: ImageWidget(song: song, size: cardSize),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.color,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    height: 1.15,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w400,
                                    fontSize: 12,
                                    color: muted,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}
