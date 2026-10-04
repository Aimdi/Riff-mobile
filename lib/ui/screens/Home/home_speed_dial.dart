import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/discovery/discovery_types.dart';
import '/ui/navigator.dart';
import '/ui/player/player_controller.dart';
import '../../widgets/collection_play.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/letter_art.dart';
import '../../widgets/riff_equalizer.dart';
import '../../widgets/riff_sheet.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import 'home_feed_builder.dart';
import 'home_feed_data.dart';
import '/ui/theme/riff_tokens.dart';
import 'home_metrics.dart';

/// Speed dial: pages of a 3×3 cover grid, no labels and no play glyphs.
/// Tap plays in place (pinned artists open), long-press opens the menu.
/// The last tile of the first page is the dice: everything, shuffled.
/// Dots sit 8dp under the grid, inside this section, only when there is
/// more than one page.
class HomeSpeedDial extends StatefulWidget {
  const HomeSpeedDial({
    super.key,
    required this.items,
    required this.metrics,
    this.source = DiscoverySource.home,
  });

  final List<HomeItem> items;
  final HomeMetrics metrics;
  final DiscoverySource source;

  static const columns = 3;
  static const rows = 3;
  static const perPage = columns * rows;

  /// Dice marker in the slot list.
  static const dice = Object();

  /// Tiles in page order: the dice takes the ninth slot once there is a
  /// full page; at most three pages.
  static List<Object> slots(List<Object> values) {
    final out = <Object>[...values];
    if (out.length >= perPage) out.insert(perPage - 1, dice);
    return out.take(perPage * speedDialPageCount(out.length)).toList();
  }

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

  List<MediaItem> get _songs => [
        for (final i in widget.items)
          if (i.value is MediaItem) i.value as MediaItem
      ];

  Future<void> _playSong(MediaItem song) async {
    final songs = _songs;
    final at = songs.indexWhere((s) => s.id == song.id);
    final player = Get.find<PlayerController>();
    if (player.currentSong.value?.id == song.id) {
      player.playPause();
      return;
    }
    final ok = await player.playPlayListSong(songs, at < 0 ? 0 : at,
        source: widget.source);
    if (!ok) snackOperationFailed();
  }

  Future<void> _playPin(SpeedDialPin pin) async {
    if (pin.type == 'artist') {
      Get.toNamed(ScreenNavigationSetup.artistScreen,
          id: ScreenNavigationSetup.id, arguments: [true, pin.id]);
      return;
    }
    final ok = await playCollection(
        isAlbum: pin.type == 'album', id: pin.id, title: pin.title);
    if (!ok) snackOperationFailed();
  }

  Future<void> _shuffle() async {
    final shuffled = List<MediaItem>.of(_songs)..shuffle();
    if (shuffled.isEmpty) return;
    final ok = await Get.find<PlayerController>()
        .playPlayListSong(shuffled, 0, source: widget.source);
    if (!ok) snackOperationFailed();
  }

  void _songMenu(MediaItem song) {
    final player = Get.find<PlayerController>();
    showCurrentSongSheet(
        song: song, context: player.homeScaffoldkey.currentContext);
  }

  void _pinMenu(BuildContext context, SpeedDialPin pin) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      shape: riffSheetShape,
      builder: (sheet) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RiffSheetHandle(),
            RiffSheetTitle(pin.title),
            RiffSheetTile(
              icon: Icons.push_pin_outlined,
              title: 'unpinFromSpeedDial'.tr,
              onTap: () {
                Navigator.of(sheet).pop();
                SpeedDialPins.unpin(pin.key);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slots =
        HomeSpeedDial.slots([for (final i in widget.items) i.value as Object]);
    if (slots.isEmpty) return const SizedBox.shrink();
    final pages = speedDialPageCount(slots.length);
    final tile = widget.metrics.speedTile;
    const gap = RiffSpacing.gridGap;
    final rowsShown = pages > 1
        ? HomeSpeedDial.rows
        : (slots.length / HomeSpeedDial.columns).ceil();
    final height = tile * rowsShown + gap * (rowsShown - 1);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RiffSectionHeader('speedDial'.tr),
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _page,
            itemCount: pages,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, p) {
              final start = p * HomeSpeedDial.perPage;
              final slice = slots.sublist(start,
                  (start + HomeSpeedDial.perPage).clamp(0, slots.length));
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: RiffSpacing.gutter),
                child: Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final v in slice)
                      if (identical(v, HomeSpeedDial.dice))
                        _DiceTile(size: tile, onTap: _shuffle)
                      else if (v is MediaItem)
                        _DialTile(
                          size: tile,
                          label:
                              '${v.title}${v.artist?.isNotEmpty == true ? ', ${v.artist}' : ''}',
                          songId: v.id,
                          art:
                              ImageWidget(song: v, size: tile, borderRadius: 0),
                          onTap: () => _playSong(v),
                          onLongPress: () => _songMenu(v),
                        )
                      else if (v is SpeedDialPin)
                        _DialTile(
                          size: tile,
                          label: v.title,
                          circle: v.type == 'artist',
                          art: _PinArt(pin: v, size: tile),
                          onTap: () => _playPin(v),
                          onLongPress: () => _pinMenu(context, v),
                        ),
                  ],
                ),
              );
            },
          ),
        ),
        if (pages > 1)
          Padding(
            padding: const EdgeInsets.only(top: RiffSizes.dotsTop),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages; i++)
                  Container(
                    width: RiffSizes.dot,
                    height: RiffSizes.dot,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _current
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withOpacity(0.28),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PinArt extends StatelessWidget {
  const _PinArt({required this.pin, required this.size});
  final SpeedDialPin pin;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (pin.art.isEmpty) {
      return LetterArt(
          title: pin.title, size: size, circle: pin.type == 'artist');
    }
    return ImageWidget(
      song: MediaItem(
          id: pin.key, title: pin.title, artUri: Uri.tryParse(pin.art)),
      size: size,
      borderRadius: 0,
    );
  }
}

class _DialTile extends StatelessWidget {
  const _DialTile({
    required this.size,
    required this.label,
    required this.art,
    required this.onTap,
    required this.onLongPress,
    this.songId,
    this.circle = false,
  });
  final double size;
  final String label;
  final Widget art;
  final String? songId;
  final bool circle;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final shape = circle
        ? const CircleBorder()
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RiffSizes.tileRadius));
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              fit: StackFit.expand,
              children: [
                art,
                if (songId != null && Get.isRegistered<PlayerController>())
                  Obx(() {
                    final player = Get.find<PlayerController>();
                    final current = player.currentSong.value?.id == songId;
                    final playing =
                        player.buttonState.value == PlayButtonState.playing;
                    if (!current) return const SizedBox.shrink();
                    return ColoredBox(
                      color: RiffColors.of(context).scrim.withOpacity(0.4),
                      child: Center(
                        child:
                            RiffEqualizer(animate: playing, size: size * 0.3),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Last tile of the first page: plays the dial shuffled.
class _DiceTile extends StatelessWidget {
  const _DiceTile({required this.size, required this.onTap});
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'shuffle'.tr,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Material(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(RiffSizes.tileRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Icon(Icons.casino_rounded,
                size: size * 0.38, color: scheme.onSecondaryContainer),
          ),
        ),
      ),
    );
  }
}
