import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../screens/Settings/settings_screen_controller.dart';
import '/models/playling_from.dart';
import '/utils/media_item_video.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import '../player_controller.dart';
import '../player_media_nav.dart';
import 'albumart_lyrics.dart';
import 'backgroud_image.dart';
import 'cover_palette.dart';
import 'hero_art_morph.dart';
import 'long_form_player.dart' show openLongFormMenu;
import 'lyrics_switch.dart';
import 'lyrics_widget.dart';
import 'player_video_surface.dart';
import 'player_canvas_backdrop.dart';
import 'player_control.dart';
import 'track_swipe.dart' show upNextTrack;
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/riff_motion.dart';

/// Standard player widget
///
/// Album art / video surface, lyrics switch, and player controls.
class StandardPlayer extends StatelessWidget {
  const StandardPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final PlayerController playerController = Get.find<PlayerController>();

    return Obx(() {
      final isVideo = playerController.isCurrentSongVideo;
      final showVideo = isVideo &&
          AlbumArtNLyrics.videoPlaybackEnabledFor(
              playerController.currentSong.value);
      final canvasOn = Get.isRegistered<SettingsScreenController>() &&
          Get.find<SettingsScreenController>().playerCanvas.isTrue;

      final bg = Theme.of(context).colorScheme.surface;
      // Dark themes: the page takes the cover's colours. The light theme's
      // dark text needs its light page, so it keeps the black-tint look.
      final coverLook = Theme.of(context).brightness == Brightness.dark;
      // Portrait phone: the cover morphs into the mini player's art when
      // the player is minimised. Wide screens keep their own mini player.
      final heroArt = !context.isLandscape && !showVideo;
      final morph = heroArt && size.width <= _morphMaxWidth;
      final thumb =
          _miniArtRect(context, playerController.playerPanelMinHeight.value);
      final full = Rect.fromLTWH(0, 0, size.width, _heroArtHeight(size));
      final position = playerController.playerPanelPosition;

      return Stack(
        children: [
          // Page: fades out on the way down so the screen behind shows
          // through, like a sheet being lowered.
          _PanelFade(
            position: position,
            enabled: morph,
            opacity: HeroArtMorph.pageOpacity,
            // Own layer: the moving cover and the controls above don't
            // repaint the page, nor its drifting glow them.
            child: RepaintBoundary(
              child: showVideo
                  // Skip HQ album-art decode + blur under live video.
                  ? ColoredBox(color: bg)
                  : coverLook
                      ? _CoverPage(drift: canvasOn)
                      : _ClassicBackdrop(canvasOn: canvasOn),
            ),
          ),
          // Portrait: the cover fills the top of the screen and fades into
          // the page where the controls start.
          if (heroArt)
            morph
                ? ValueListenableBuilder<double>(
                    valueListenable: position,
                    builder: (context, p, child) => _MorphingArt(
                        progress: p, thumb: thumb, full: full, child: child!),
                    child: const BackgroudImage(),
                  )
                : _MorphingArt(
                    progress: 1,
                    thumb: full,
                    full: full,
                    child: const BackgroudImage()),
          _PanelFade(
            position: position,
            enabled: morph,
            opacity: HeroArtMorph.controlsOpacity,
            child: RepaintBoundary(
              child: Stack(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: RiffSpacing.xxl),
                    child: (context.isLandscape)
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: size.width * .45,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: 90.0, top: RiffSpacing.unit * 10),
                                  child: Center(
                                    child: AlbumArtNLyrics(
                                      playerArtImageSize: size.width * .29,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: size.width * .48,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                      left: 10.0,
                                      right: 10,
                                      bottom: RiffSpacing.unit * 20 +
                                          Get.mediaQuery.padding.bottom),
                                  child: const PlayerControlWidget(),
                                ),
                              )
                            ],
                          )
                        : Column(
                            children: [
                              SizedBox(
                                  height: Get.mediaQuery.padding.top +
                                      PlayerTopBar.height),
                              // The cover itself is the backdrop; this layer takes
                              // the taps and swipes and hosts lyrics / video.
                              Expanded(
                                child: _HeroArtRegion(
                                    isVideo: isVideo,
                                    showVideo: showVideo,
                                    coverLook: coverLook),
                              ),
                              const SizedBox(height: RiffSpacing.sm),
                              Padding(
                                padding: EdgeInsets.only(
                                    bottom: RiffSpacing.unit * 20 +
                                        Get.mediaQuery.padding.bottom),
                                child: Container(
                                  constraints:
                                      const BoxConstraints(maxWidth: 500),
                                  child: const PlayerControlWidget(),
                                ),
                              ),
                            ],
                          ),
                  ),
                  if (!(context.isLandscape && GetPlatform.isMobile))
                    const PlayerTopBar(),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  /// Wider screens have the desktop mini player, laid out differently.
  static const double _morphMaxWidth = 800;
}

/// Where the mini player draws its art, in the player panel's own
/// coordinates (the panel's top edge is the mini player's top edge):
/// mirrors MiniPlayer's card insets and row padding.
Rect _miniArtRect(BuildContext context, double miniPlayerHeight) {
  final bottom = MediaQuery.viewPaddingOf(context).bottom;
  final cardHeight = miniPlayerHeight - bottom - RiffSpacing.sm;
  const size = RiffComponentSizes.miniArt;
  return Rect.fromLTWH(RiffSpacing.md * 2, (cardHeight - size) / 2, size, size);
}

/// The dark theme's page in the cover's colours ([CoverBackdrop]). While a
/// new song's colours are worked out it keeps the last song's, then eases
/// straight to the new ones; the next song's are worked out ahead.
class _CoverPage extends StatefulWidget {
  const _CoverPage({required this.drift});
  final bool drift;

  @override
  State<_CoverPage> createState() => _CoverPageState();
}

class _CoverPageState extends State<_CoverPage> {
  final _player = Get.find<PlayerController>();
  late final Worker _songs;
  Timer? _warm;

  @override
  void initState() {
    super.initState();
    _songs = ever(_player.currentSong, (_) => _warmNext());
    _warmNext();
  }

  /// Once this song's colours have eased in, the next song's.
  void _warmNext() {
    _warm?.cancel();
    _warm = Timer(RiffDurations.colour, () {
      if (mounted) PlayerCoverColors.warm(upNextTrack(_player));
    });
  }

  @override
  void dispose() {
    _warm?.cancel();
    _songs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    return Obx(() => CoverBackdrop(
          palette: PlayerCoverColors.shown(_player.currentSong.value,
              CoverPalette(fill: bg, deep: bg, glow: bg)),
          drift: widget.drift,
        ));
  }
}

/// Fades [child] with the panel [position] through [opacity]; a plain
/// pass-through when [enabled] is false or the panel is fully open. Only
/// the layer's alpha changes per frame: nothing rebuilds or repaints.
class _PanelFade extends StatelessWidget {
  const _PanelFade({
    required this.position,
    required this.enabled,
    required this.opacity,
    required this.child,
  });
  final ValueListenable<double> position;
  final bool enabled;
  final double Function(double) opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return Positioned.fill(child: child);
    return Positioned.fill(
      // Opacity 0 skips painting but keeps the player mounted, so video,
      // lyrics and scroll state survive a minimise.
      child: FadeTransition(
        opacity: PanelPositionAnimation(position, opacity),
        child: child,
      ),
    );
  }
}

/// The cover at its place in the minimise / expand morph: a rounded card
/// between the mini player's art and the full-bleed top of the player.
class _MorphingArt extends StatelessWidget {
  const _MorphingArt({
    required this.progress,
    required this.thumb,
    required this.full,
    required this.child,
  });
  final double progress;
  final Rect thumb;
  final Rect full;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = HeroArtMorph.radius(progress, thumbRadius: thumb.width / 2);
    final fade = HeroArtMorph.fade(progress);
    return Positioned.fromRect(
      rect: HeroArtMorph.rect(progress, thumb: thumb, full: full),
      // Own layer: the cover resizing every frame of the morph doesn't
      // repaint the page and controls around it.
      child: RepaintBoundary(
        child: IgnorePointer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            clipBehavior: radius > 0 ? Clip.antiAlias : Clip.none,
            child: _HeroArtFade(fade: fade, child: child),
          ),
        ),
      ),
    );
  }
}

/// Now-playing header: collapse · where playback comes from · more.
/// Lyrics and the sleep timer live in the action bar under the transport.
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({super.key});

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final fg = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.only(
          top: Get.mediaQuery.padding.top + RiffSpacing.sm,
          left: RiffSpacing.sm,
          right: RiffSpacing.sm),
      child: SizedBox(
        height: height - RiffSpacing.sm,
        child: Row(
          children: [
            IconButton(
              tooltip: 'close'.tr,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
              onPressed: playerController.playerPanelController.close,
            ),
            Expanded(
              child: Obx(() {
                final from = playerController.playinfrom.value;
                final label = playingFromLabel(from);
                if (label == null) return const SizedBox.shrink();
                final header = Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label.type.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: fg.withOpacity(0.6)),
                    ),
                    if (label.name.isNotEmpty) ...[
                      const SizedBox(height: RiffSpacing.xxs),
                      Text(
                        label.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: fg),
                      ),
                    ],
                  ],
                );
                // Album, playlist or artist: tap to open it.
                if (!from.canOpen) return header;
                return Semantics(
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(RiffRadii.sm),
                    onTap: () => openPlayingFrom(playerController),
                    child: header,
                  ),
                );
              }),
            ),
            // Podcasts and audiobooks: the ⋮ with speed, sleep timer and
            // the rest. Music: balances the collapse button (song options
            // sit by the title).
            Obx(() => playerController.usesLongFormTransport
                ? IconButton(
                    tooltip: 'moreOptions'.tr,
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => openLongFormMenu(context),
                  )
                : const SizedBox(width: RiffSizes.touch)),
          ],
        ),
      ),
    );
  }
}

/// Height of the full-bleed cover at the top of the portrait player.
double _heroArtHeight(Size size) =>
    size.width > size.height * 0.58 ? size.width : size.height * 0.58;

/// The cover: sharp across the top, fading out towards the controls by
/// [fade] (1 when the player is open, 0 while it's a small card), with a
/// scrim at the top that keeps the "playing from" header readable on
/// bright covers.
class _HeroArtFade extends StatelessWidget {
  const _HeroArtFade({required this.fade, required this.child});
  final double fade;
  final Widget child;

  /// The mask's shader, kept while the cover's size and fade stay put (a
  /// repaint of the resting cover reuses it).
  static Shader? _mask;
  static (Size, double, Color)? _maskFor;

  static Shader _maskShader(Size size, double fade, Color opaque) {
    final key = (size, fade, opaque);
    if (_mask == null || _maskFor != key) {
      _maskFor = key;
      _mask = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [opaque, opaque, opaque.withOpacity(1 - fade)],
        stops: const [0, 0.62, 1],
      ).createShader(Offset.zero & size);
    }
    return _mask!;
  }

  @override
  Widget build(BuildContext context) {
    final riff = RiffColors.of(context);
    return ShaderMask(
      shaderCallback: (rect) => _maskShader(rect.size, fade, riff.onImage),
      blendMode: BlendMode.dstIn,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          // The scrim's strength scales its colours rather than an Opacity
          // layer over it (the same pixels, one layer less per frame).
          if (fade > 0)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    riff.scrim
                        .withOpacity(RiffPalette.playerHeaderScrim * fade),
                    riff.scrim
                        .withOpacity(RiffPalette.playerHeaderScrimMid * fade),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.22, 0.42],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The light theme's page (and the look before cover colours): black with
/// at most a 20% album-art tint at the top, optional ambient canvas.
class _ClassicBackdrop extends StatelessWidget {
  const _ClassicBackdrop({required this.canvasOn});
  final bool canvasOn;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: bg),
        const BackgroudImage(),
        // Lighter than BackdropFilter blur — the page colour over the art
        // lets at most 20% of it through at the top, none lower down.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                bg.withOpacity(1 - RiffPalette.playerTintOpacity),
                bg,
              ],
              stops: const [0, 0.6],
            ),
          ),
        ),
        if (canvasOn) const RepaintBoundary(child: PlayerCanvasBackdrop()),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 65 + Get.mediaQuery.padding.bottom + 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  bg,
                  bg,
                  bg.withOpacity(0.4),
                  bg.withOpacity(0),
                ],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                stops: const [0, 0.5, 0.8, 1],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Transparent layer over the cover: tap for lyrics (or play/pause on a
/// video), swipe to skip, long-press for the song menu. Hosts the lyrics
/// overlay, the video surface and the show-video button.
class _HeroArtRegion extends StatelessWidget {
  const _HeroArtRegion({
    required this.isVideo,
    required this.showVideo,
    required this.coverLook,
  });
  final bool isVideo;
  final bool showVideo;

  /// The page is in the cover's colours (dark themes, no video).
  final bool coverLook;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Obx(() {
      final song = playerController.currentSong.value;
      final lyricsOn = playerController.showLyricsflag.isTrue;
      if (song == null) return const SizedBox.shrink();
      void onTap() {
        if (showVideo) {
          playerController.playPause();
        } else {
          playerController.showLyrics();
        }
      }

      // Named for TalkBack; its tap shows the lyrics (a video's plays or
      // pauses), its swipes change the song.
      return Semantics(
          container: true,
          label: 'coverArt'.tr,
          onTapHint: showVideo ? null : 'showLyrics'.tr,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onLongPress: () {
              HapticFeedback.mediumImpact();
              openNowPlayingSheet(playerController);
            },
            onHorizontalDragEnd: (details) {
              if (lyricsOn) return;
              final v = details.primaryVelocity ?? 0;
              if (v < 0) {
                playerController.next();
              } else if (v > 0) {
                playerController.prev();
              }
            },
            child: LayoutBuilder(builder: (context, box) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (showVideo)
                    Center(
                      child: PlayerVideoSurface(
                        song: song,
                        width: box.maxWidth,
                        maxHeight: box.maxHeight,
                        onToggleVideo: () async {
                          await AlbumArtNLyrics.setVideoPlaybackEnabled(
                              song, false);
                          playerController.currentSong.refresh();
                        },
                      ),
                    ),
                  // The lyrics fade in over the cover, and out again.
                  Positioned.fill(
                    child: RiffSwitcher(
                      duration: RiffDurations.content,
                      child: lyricsOn
                          ? SizedBox.expand(
                              key: const ValueKey<String>('lyrics'),
                              child: _LyricsVeil(
                                coverLook: coverLook && !showVideo,
                                child: LyricsWidget(
                                    padding: EdgeInsets.symmetric(
                                        vertical: box.maxHeight / 4),
                                    onTap: onTap),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  if (!isVideo)
                    const Align(
                        alignment: Alignment.topCenter, child: LyricsSwitch()),
                  if (song.canShowPlayerVideo && !showVideo)
                    Positioned(
                      right: RiffSpacing.lg,
                      top: RiffSpacing.sm,
                      child: PlayerVideoEnableButton(
                        onShow: () async {
                          await AlbumArtNLyrics.setVideoPlaybackEnabled(
                              song, true);
                          playerController.currentSong.refresh();
                        },
                      ),
                    ),
                ],
              );
            }),
          ));
    });
  }
}

/// The lyrics' backing over the cover: the page colour dims it, so their
/// text reads in the page's text colours, darker still at the top and
/// bottom edges. The cover-coloured page's fill when [coverLook], else the
/// page colour.
class _LyricsVeil extends StatelessWidget {
  const _LyricsVeil({required this.coverLook, required this.child});
  final bool coverLook;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    return Obx(() {
      final song = Get.find<PlayerController>().currentSong.value;
      final page = coverLook
          ? PlayerCoverColors.shown(
                  song, CoverPalette(fill: bg, deep: bg, glow: bg))
              .fill
          : bg;
      // A card over the cover, rounded like the app's other cards.
      return ClipRRect(
          borderRadius: BorderRadius.circular(RiffRadii.lg),
          child: ColoredBox(
            color: page.withOpacity(0.78),
            child: Stack(
              children: [
                child,
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          page.withOpacity(0.9),
                          Colors.transparent,
                          Colors.transparent,
                          page.withOpacity(0.9),
                        ],
                        stops: const [0, 0.2, 0.8, 1],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ));
    });
  }
}

/// "Playing from" header split into its kind ("Playing from playlist") and
/// source name; null when there is nothing to show.
({String type, String name})? playingFromLabel(PlaylingFrom from) {
  final type = '${from.typeString}'.trim();
  final name = '${from.nameString}'.trim();
  if (type.isEmpty && name.isEmpty) return null;
  if (type.isEmpty) return (type: name, name: '');
  return (type: type, name: name);
}

/// Song options for the current track: radio, play next, add to playlist,
/// share, lyrics, sleep timer, album / artist …
void openNowPlayingSheet(PlayerController playerController,
    {VoidCallback? onLyrics}) {
  final sheetContext =
      playerController.homeScaffoldkey.currentContext ?? Get.context;
  final song = playerController.currentSong.value;
  if (sheetContext == null || song == null) return;
  showModalBottomSheet(
    useRootNavigator: true,
    constraints: const BoxConstraints(maxWidth: 500),
    isScrollControlled: true,
    context: sheetContext,
    builder: (context) => SongInfoBottomSheet(song,
        calledFromPlayer: true, showPlayerTools: true, onLyrics: onLyrics),
  ).whenComplete(() => Get.delete<SongInfoController>());
}
