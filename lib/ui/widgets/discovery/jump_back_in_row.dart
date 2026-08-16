import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../../models/media_Item_builder.dart';
import '../../player/player_controller.dart';
import '../../screens/Home/home_greeting.dart';
import '../../utils/riff_tokens.dart';
import '../image_widget.dart';

/// Spotify-like Home recents — 2-column art + title tiles from Hive `LIBRP`.
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

    final count = jumpBackInGridCount(tracks.length);
    final visible = tracks.sublist(0, count);
    final theme = Theme.of(context);
    final fill = homeTileFill(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final tileW = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < visible.length; i++)
                SizedBox(
                  width: tileW,
                  height: 56,
                  child: Material(
                    color: fill,
                    borderRadius: BorderRadius.circular(RiffTokens.radiusTile),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        Get.find<PlayerController>()
                            .playPlayListSong(tracks, i);
                      },
                      child: Row(
                        children: [
                          ImageWidget(
                            song: visible[i],
                            size: 56,
                            borderRadius: 0,
                          ),
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                visible[i].title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.textTheme.titleMedium?.color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  height: 1.2,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
