import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/services/discovery/discovery_types.dart';
import '/ui/navigator.dart';
import '/ui/player/player_controller.dart';
import '../../widgets/collection_play.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/letter_art.dart';
import '../../widgets/riff_equalizer.dart';
import '../../widgets/riff_motion.dart';
import '../../widgets/riff_sheet.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import 'home_feed_builder.dart';
import 'home_feed_data.dart';
import '/ui/theme/riff_tokens.dart';
import 'home_metrics.dart';
import '/ui/player/play_queue_order.dart' show playQueueFrom;

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

/// The looping speed dial starts this many pages in, so it can be swiped
/// either way from the first page (divisible by 1, 2 and 3 pages, so the
/// start is always page 0).
const speedDialLoopStart = 6000;

/// Speed dial page shown at PageView index [index] when it loops over
/// [pages] pages.
int speedDialPageAt(int index, int pages) => pages <= 0 ? 0 : index % pages;

/// Scale and opacity of a speed dial page [distance] pages away from the
/// centre of the screen while swiping (0 = settled in place).
({double scale, double opacity}) speedDialPageLook(double distance) {
  final d = distance.abs().clamp(0.0, 1.0);
  return (
    scale: 1 - RiffSizes.speedDialPageShrink * d,
    opacity: 1 - RiffSizes.speedDialPageFade * d,
  );
}

class _HomeSpeedDialState extends State<HomeSpeedDial> {
  // One page: a plain pager. Several: an endless one, so a swipe right on
  // the first page slides round to the last instead of doing nothing.
  final _single = PageController();
  final _loop = PageController(initialPage: speedDialLoopStart);
  int _current = 0;

  @override
  void dispose() {
    _single.dispose();
    _loop.dispose();
    super.dispose();
  }

  /// Where the pager is, in pages (fractional while swiping).
  double _position(PageController c) {
    if (c.hasClients && c.position.haveDimensions) return c.page ?? 0;
    return c.initialPage.toDouble();
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
    final shuffled = playQueueFrom(_songs, shuffle: true);
    if (shuffled.isEmpty) return;
    final ok = await Get.find<PlayerController>()
        .playPlayListSong(shuffled, 0, source: widget.source);
    if (!ok) snackOperationFailed();
  }

  void _songMenu(MediaItem song) {
    final player = Get.find<PlayerController>();
    HapticFeedback.mediumImpact();
    showCurrentSongSheet(
        song: song, context: player.homeScaffoldkey.currentContext);
  }

  void _pinMenu(BuildContext context, SpeedDialPin pin) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
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
            const SizedBox(height: RiffSpacing.sm),
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
    // From the pager itself, so the dot stays right when the number of
    // pages changes under it.
    final current = pages > 1 && _loop.hasClients
        ? speedDialPageAt(_position(_loop).round(), pages)
        : _current.clamp(0, pages - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RiffSectionHeader('speedDial'.tr),
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: pages > 1 ? _loop : _single,
            itemCount: pages > 1 ? null : 1,
            onPageChanged: (i) {
              HapticFeedback.selectionClick();
              setState(() => _current = speedDialPageAt(i, pages));
            },
            itemBuilder: (context, index) {
              final p = speedDialPageAt(index, pages);
              final start = p * HomeSpeedDial.perPage;
              final slice = slots.sublist(start,
                  (start + HomeSpeedDial.perPage).clamp(0, slots.length));
              final controller = pages > 1 ? _loop : _single;
              final page = Padding(
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
                          title: v.title,
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
                          title: v.title,
                          circle: v.type == 'artist',
                          art: _PinArt(pin: v, size: tile),
                          onTap: () => _playPin(v),
                          onLongPress: () => _pinMenu(context, v),
                        ),
                  ],
                ),
              );
              // Depth while swiping: the page leaving shrinks and fades a
              // little, the one arriving grows into place.
              return AnimatedBuilder(
                animation: controller,
                builder: (context, child) {
                  final look = speedDialPageLook(_position(controller) - index);
                  return Opacity(
                    opacity: look.opacity,
                    child: Transform.scale(scale: look.scale, child: child),
                  );
                },
                child: page,
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
                  AnimatedContainer(
                    duration: RiffDurations.select,
                    curve: RiffDurations.selectCurve,
                    width: i == current ? RiffSizes.dotActive : RiffSizes.dot,
                    height: RiffSizes.dot,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(RiffRadii.pill),
                      color: i == current
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
    if (pin.type == 'playlist') {
      // The same cover the playlist shows everywhere else: a photo of its
      // own, its art, or the generated cover.
      return ImageWidget(
        playlist: Playlist(
            title: pin.title, playlistId: pin.id, thumbnailUrl: pin.art),
        size: size,
        borderRadius: 0,
      );
    }
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
    required this.title,
    required this.art,
    required this.onTap,
    required this.onLongPress,
    this.songId,
    this.circle = false,
  });
  final double size;
  final String label;

  /// Written on the cover, bottom left (centred on an artist's circle),
  /// so a tile says what it plays, as YouTube Music's do.
  final String title;
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
        child: RiffPressScale(
            child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              fit: StackFit.expand,
              children: [
                art,
                if (title.isNotEmpty)
                  _TileTitle(
                      title: title,
                      circle: circle,
                      compact: size < RiffSizes.compactDialTile),
                if (songId != null && Get.isRegistered<PlayerController>())
                  Obx(() {
                    final player = Get.find<PlayerController>();
                    final current = player.currentSong.value?.id == songId;
                    final playing =
                        player.buttonState.value == PlayButtonState.playing;
                    // The now-playing veil fades over the tile as its song
                    // starts, and away as another does.
                    return RiffSwitcher(
                      child: !current
                          ? const SizedBox.shrink(key: ValueKey(false))
                          : ColoredBox(
                              key: const ValueKey(true),
                              color:
                                  RiffColors.of(context).scrim.withOpacity(0.4),
                              child: Center(
                                child: RiffEqualizer(
                                    animate: playing,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    size: size * 0.3),
                              ),
                            ),
                    );
                  }),
              ],
            ),
          ),
        )),
      ),
    );
  }
}

/// A Speed dial tile's title on a dark wash rising from the bottom of
/// its cover.
class _TileTitle extends StatelessWidget {
  const _TileTitle(
      {required this.title, required this.circle, required this.compact});
  final String title;
  final bool circle;

  /// A small tile (small phones): the smaller label style.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final riff = RiffColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [RiffPalette.tileTitleScrimStart, 1],
          colors: [
            riff.scrim.withOpacity(0),
            riff.scrim.withOpacity(RiffPalette.tileTitleScrim),
          ],
        ),
      ),
      child: Align(
        alignment: circle ? Alignment.bottomCenter : Alignment.bottomLeft,
        child: Padding(
          padding: EdgeInsets.only(
              left: circle ? RiffSpacing.lg : RiffSpacing.sm,
              right: circle ? RiffSpacing.lg : RiffSpacing.sm,
              bottom: circle ? RiffSpacing.md : RiffSpacing.sm),
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: circle ? TextAlign.center : TextAlign.start,
            style: (compact
                    ? Theme.of(context).textTheme.labelSmall
                    : Theme.of(context).textTheme.labelMedium)
                ?.copyWith(color: riff.onImage),
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
        child: RiffPressScale(
            child: Material(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(RiffSizes.tileRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Icon(Icons.casino_rounded,
                size: size * 0.38, color: scheme.onSecondaryContainer),
          ),
        )),
      ),
    );
  }
}
