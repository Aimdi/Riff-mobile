import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/discovery/discovery_types.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/riff_tokens.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import 'home_layout.dart';

/// Speed dial: pages of a 3×3 cover grid with a play glyph on each, and
/// dots under them. Tap plays, long-press opens the song menu.
class HomeSpeedDial extends StatefulWidget {
  const HomeSpeedDial({
    super.key,
    required this.title,
    required this.songs,
    this.source = DiscoverySource.home,
  });

  final String title;
  final List<MediaItem> songs;
  final DiscoverySource source;

  static const columns = 3;
  static const rows = 3;
  static const maxPages = 3;
  static const perPage = columns * rows;

  @override
  State<HomeSpeedDial> createState() => _HomeSpeedDialState();
}

class _HomeSpeedDialState extends State<HomeSpeedDial> {
  final _page = PageController();
  int _current = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _play(int i) async {
    final ok = await Get.find<PlayerController>()
        .playPlayListSong(widget.songs, i, source: widget.source);
    if (!ok) snackOperationFailed();
  }

  void _menu(MediaItem song) {
    final player = Get.find<PlayerController>();
    showCurrentSongSheet(
        song: song, context: player.homeScaffoldkey.currentContext);
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.songs
        .take(HomeSpeedDial.perPage * HomeSpeedDial.maxPages)
        .toList();
    if (songs.isEmpty) return const SizedBox.shrink();
    final pages = (songs.length / HomeSpeedDial.perPage).ceil();
    final accent = Theme.of(context).colorScheme.secondary;
    final muted = homeMutedColor(context) ?? Colors.grey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(widget.title),
        LayoutBuilder(builder: (context, constraints) {
          const gap = HomeLayout.tileGap;
          final inner = constraints.maxWidth - HomeLayout.gutter * 2;
          final tile =
              (inner - gap * (HomeSpeedDial.columns - 1)) / HomeSpeedDial.columns;
          final lastPageRows = ((songs.length - (pages - 1) * HomeSpeedDial.perPage) /
                  HomeSpeedDial.columns)
              .ceil();
          final rowsShown = pages > 1 ? HomeSpeedDial.rows : lastPageRows;
          final height = tile * rowsShown + gap * (rowsShown - 1);
          return SizedBox(
            height: height,
            child: PageView.builder(
              controller: _page,
              itemCount: pages,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, p) {
                final start = p * HomeSpeedDial.perPage;
                final slice = songs.sublist(
                    start, (start + HomeSpeedDial.perPage).clamp(0, songs.length));
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < slice.length; i++)
                        _DialTile(
                          song: slice[i],
                          size: tile,
                          onTap: () => _play(start + i),
                          onLongPress: () => _menu(slice[i]),
                        ),
                    ],
                  ),
                );
              },
            ),
          );
        }),
        if (pages > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _current ? 18 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _current ? accent : muted.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DialTile extends StatelessWidget {
  const _DialTile(
      {required this.song,
      required this.size,
      required this.onTap,
      required this.onLongPress});
  final MediaItem song;
  final double size;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Material(
        color: homeTileColor(context),
        borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ImageWidget(song: song, size: size, borderRadius: 0),
              Center(
                child: Container(
                  width: size * 0.36,
                  height: size * 0.36,
                  decoration: const BoxDecoration(
                    color: Color(0x80000000),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: size * 0.22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
