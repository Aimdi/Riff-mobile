import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../screens/Settings/settings_screen_controller.dart';
import '../utils/riff_tokens.dart';
import 'generated_cover.dart';
import 'letter_art.dart';
import 'podcast_play.dart' show isPodcastCollection;
import 'riff_motion.dart';
import 'shimmer_widgets/basic_container.dart' show RiffSkeletonPulse;
import '/ui/theme/riff_tokens.dart' show RiffDurations;
import '/models/artist.dart';
import '/models/thumbnail.dart';
import '/services/cover_resolver.dart';
import '/services/playlist_covers.dart';
import '../../models/album.dart';
import '../../models/playlist.dart';

/// Whether [playlist] gets a generated cover when it has no art of its
/// own. Podcast shows and channels (also [Playlist]s) keep the letter tile.
bool playlistUsesGeneratedCover(Playlist playlist) =>
    !isPodcastCollection(kind: playlist.kind, id: playlist.playlistId);

/// CDNs (Apple artwork, some Google user-content) 404 a bare Dart UA.
const kCoverImageHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
  'Accept': 'image/webp,image/jpeg,image/png,image/*,*/*;q=0.8',
};

/// A network cover with Riff's timing: once loaded it fades in over
/// [RiffDurations.image] and its placeholder clears as fast (front-loaded,
/// so the cover shows through early), and the fallback shown when it
/// fails fades in rather than cutting in. Otherwise a [CachedNetworkImage]
/// with the same parameters.
class RiffNetworkImage extends StatelessWidget {
  const RiffNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.memCacheWidth,
    this.memCacheHeight,
    this.filterQuality = FilterQuality.low,
    this.httpHeaders,
    this.placeholder,
    this.progressIndicatorBuilder,
    this.errorWidget,
    this.imageBuilder,
    this.color,
    this.colorBlendMode,
    this.useOldImageOnUrlChange = false,
    this.errorFadesIn = true,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final FilterQuality filterQuality;
  final Map<String, String>? httpHeaders;
  final PlaceholderWidgetBuilder? placeholder;
  final ProgressIndicatorBuilder? progressIndicatorBuilder;
  final LoadingErrorWidgetBuilder? errorWidget;
  final ImageWidgetBuilder? imageBuilder;
  final Color? color;
  final BlendMode? colorBlendMode;

  /// Keeps the image shown while a new [imageUrl] loads, then crossfades
  /// to it (no placeholder in between).
  final bool useOldImageOnUrlChange;

  /// Whether [errorWidget] fades in. Off where it's another image trying a
  /// second URL behind the same placeholder (it fades its own fallback).
  final bool errorFadesIn;

  @override
  Widget build(BuildContext context) {
    final error = errorWidget;
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      filterQuality: filterQuality,
      httpHeaders: httpHeaders,
      placeholder: placeholder,
      progressIndicatorBuilder: progressIndicatorBuilder,
      imageBuilder: imageBuilder,
      color: color,
      colorBlendMode: colorBlendMode,
      useOldImageOnUrlChange: useOldImageOnUrlChange,
      fadeInDuration: RiffDurations.image,
      fadeInCurve: RiffDurations.enterCurve,
      fadeOutDuration: RiffDurations.image,
      fadeOutCurve: RiffDurations.enterCurve,
      errorWidget: error == null || !errorFadesIn
          ? error
          : (context, url, e) => RiffFadeIn(
                duration: RiffDurations.image,
                rise: 0,
                child: error(context, url, e),
              ),
    );
  }
}

class ImageWidget extends StatelessWidget {
  const ImageWidget({
    super.key,
    this.song,
    this.playlist,
    this.album,
    this.artist,
    required this.size,
    this.isPlayerArtImage = false,
    this.borderRadius,
    this.coverTitleRightInset = 0,
  });
  final MediaItem? song;
  final Playlist? playlist;
  final Album? album;
  final bool isPlayerArtImage;
  final Artist? artist;
  final double size;

  /// Override corner radius for square covers (artists stay circular).
  final double? borderRadius;

  /// A playlist's generated cover keeps this much room (dp) clear on the
  /// right of its title, for a button over the art's bottom-right corner.
  final double coverTitleRightInset;

  double get _radius =>
      borderRadius ??
      (isPlayerArtImage ? RiffTokens.radiusLg : RiffTokens.radiusSm);

  String get _rawUrl {
    if (song != null) return song!.artUri?.toString() ?? "";
    if (playlist != null) return playlist!.thumbnailUrl;
    if (album != null) return album!.thumbnailUrl;
    if (artist != null) return artist!.thumbnailUrl;
    return "";
  }

  String _scaled(String raw) {
    if (raw.isEmpty) return raw;
    final t = Thumbnail(raw);
    if (isPlayerArtImage || size >= 280) return t.extraHigh;
    if (size >= 100) return t.high;
    return t.medium;
  }

  /// Name the fallback art is drawn from.
  String get _title {
    if (song != null) return song!.title;
    if (playlist != null) return playlist!.title;
    if (album != null) return album!.title;
    if (artist != null) return artist!.name;
    return '';
  }

  /// No cover, or the cover failed: a playlist gets its generated cover
  /// (colour blobs, and its title when big enough); anything else a
  /// gradient with the title's first letter (never a generic music-note
  /// icon).
  Widget _placeholder(BuildContext context) {
    final pl = playlist;
    if (song == null && pl != null && playlistUsesGeneratedCover(pl)) {
      // The container around it already clips to [_radius].
      return GeneratedCover.playlist(pl,
          size: size, titleRightInset: coverTitleRightInset);
    }
    return LetterArt(
      title: _title,
      size: size,
      radius: _radius,
      circle: artist != null,
    );
  }

  /// [_placeholder] for a cover that failed to load: it fades in where the
  /// loading pulse was instead of cutting in.
  Widget _fallback(BuildContext context) => RiffFadeIn(
        duration: RiffDurations.image,
        rise: 0,
        child: _placeholder(context),
      );

  /// What this cover is of: a new URL for the same thing (a better cover
  /// found, the page's own art arriving) crossfades from the old image,
  /// while a different thing starts afresh.
  Key get _subjectKey => ValueKey(song?.id ??
      playlist?.playlistId ??
      album?.browseId ??
      artist?.browseId ??
      '');

  @override
  Widget build(BuildContext context) {
    final pl = playlist;
    if (song == null && pl != null) {
      // A photo of its own, when one was given, wins over any other art.
      return Obx(() {
        PlaylistCovers.rev.value;
        final photo = PlaylistCovers.pathFor(pl.playlistId);
        return photo == null ? _art(context) : _photo(context, photo);
      });
    }
    return _art(context);
  }

  /// A playlist's own photo; the cover it would have had when the file is
  /// gone.
  Widget _photo(BuildContext context, String path) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Container(
      height: size,
      width: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Image.file(
        File(path),
        height: size,
        width: size,
        cacheWidth: (size * dpr).round().clamp(64, 1600),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        frameBuilder: riffFadeInFrame,
        errorBuilder: (context, __, ___) => _art(context),
      ),
    );
  }

  Widget _art(BuildContext context) {
    // The shared "no playlist art" image counts as no art.
    final raw = _rawUrl == Playlist.thumbPlaceholderUrl ? '' : _rawUrl;
    final imageUrl = _scaled(raw);

    final bool offlineAvailable =
        song != null && (song?.extras?["url"] ?? "").contains("file");
    // A cover on the phone itself (a music file's album cover).
    final localCover = song?.artUri?.isScheme('file') == true
        ? song!.artUri!.toFilePath()
        : null;

    // Only constrain the longer edge so landscape video frames stay cropped
    // (BoxFit.cover) instead of stretched into a square.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeSide = (size * dpr).round().clamp(64, 1600);

    Widget network() => (imageUrl.isEmpty)
        ? _placeholder(context)
        // A song whose only art is a 16:9 video frame: show the frame,
        // then swap to the resolved square audio-track cover (cached).
        : (song != null &&
                Thumbnail.isVideoFrameUrl(raw) &&
                !song!.id.startsWith('podcast_') &&
                song!.extras?['isPodcast'] != true)
            ? _SongCoverImage(
                song: song!,
                size: size,
                decodeSide: decodeSide,
                placeholder: _placeholder(context),
                shimmer: _shimmer(context),
              )
            : RiffNetworkImage(
                key: _subjectKey,
                height: size,
                width: size,
                // One dimension only — setting both forces a square decode and
                // elongates 16:9 YouTube frames.
                memCacheWidth: decodeSide,
                filterQuality: FilterQuality.medium,
                imageUrl: imageUrl,
                httpHeaders: kCoverImageHeaders,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                useOldImageOnUrlChange: true,
                // The full-size URL failed: the original one (its loading
                // pulse looks the same, so nothing flashes), else the
                // fallback art (which fades in itself).
                errorFadesIn: false,
                errorWidget: (context, url, error) {
                  if (raw.isNotEmpty && raw != imageUrl) {
                    return CachedNetworkImage(
                      height: size,
                      width: size,
                      memCacheWidth: decodeSide,
                      imageUrl: raw,
                      httpHeaders: kCoverImageHeaders,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      fadeInDuration: RiffDurations.image,
                      fadeInCurve: RiffDurations.enterCurve,
                      fadeOutDuration: RiffDurations.image,
                      fadeOutCurve: RiffDurations.enterCurve,
                      errorWidget: (_, __, ___) => _fallback(context),
                      progressIndicatorBuilder: (_, __, ___) =>
                          _shimmer(context),
                    );
                  }
                  return _fallback(context);
                },
                progressIndicatorBuilder: ((_, __, ___) => _shimmer(context)),
              );

    return Container(
      height: size,
      width: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: artist != null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: artist != null ? null : BorderRadius.circular(_radius),
      ),
      child: localCover != null
          ? Image.file(
              File(localCover),
              height: size,
              width: size,
              cacheWidth: decodeSide,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              frameBuilder: riffFadeInFrame,
              errorBuilder: (_, __, ___) => _fallback(context),
            )
          : offlineAvailable
              ? Image.file(
                  File(
                      "${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/${song!.id}.png"),
                  height: size,
                  width: size,
                  cacheWidth: decodeSide,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  frameBuilder: riffFadeInFrame,
                  // Not saved (an episode or a book's chapter playing from the
                  // phone): its cover from the network.
                  errorBuilder: (_, __, ___) => network(),
                )
              : network(),
    );
  }

  /// While the cover loads: a skeleton box pulsing like the rest of the
  /// app's loading skeletons (§5.13), held still under Remove animations.
  Widget _shimmer(BuildContext context) {
    return RiffSkeletonPulse(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: artist != null ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: artist != null ? null : BorderRadius.circular(_radius),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
        ),
        child: SizedBox.square(dimension: size),
      ),
    );
  }
}

/// Shows a song's 16:9 video frame immediately, then crossfades to the
/// square audio-track cover once [CoverResolver] finds it (instant when
/// cached); the frame stays up while the cover loads.
class _SongCoverImage extends StatefulWidget {
  const _SongCoverImage({
    required this.song,
    required this.size,
    required this.decodeSide,
    required this.placeholder,
    required this.shimmer,
  });
  final MediaItem song;
  final double size;
  final int decodeSide;
  final Widget placeholder;
  final Widget shimmer;

  @override
  State<_SongCoverImage> createState() => _SongCoverImageState();
}

class _SongCoverImageState extends State<_SongCoverImage> {
  late String _url;

  String _scaled(String raw) {
    final t = Thumbnail(raw);
    if (widget.size >= 280) return t.extraHigh;
    if (widget.size >= 100) return t.high;
    return t.medium;
  }

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _SongCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reused elements (queue rows, mini player on track change) must not
    // keep showing the previous song's art.
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.song.artUri != widget.song.artUri ||
        oldWidget.size != widget.size) {
      _resolve();
    }
  }

  void _resolve() {
    _url = _scaled(widget.song.artUri?.toString() ?? '');
    final vid = widget.song.id;
    final cached = CoverResolver.cached(vid);
    if (cached != null && cached.isNotEmpty) {
      _url = _scaled(cached);
    } else if (cached == null) {
      CoverResolver.resolve(vid,
              title: widget.song.title, artist: widget.song.artist)
          .then((square) {
        // Drop results for a song this element no longer shows.
        if (square != null &&
            square.isNotEmpty &&
            mounted &&
            widget.song.id == vid) {
          setState(() => _url = _scaled(square));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RiffNetworkImage(
      // Another song starts afresh; its own better cover crossfades in.
      key: ValueKey(widget.song.id),
      height: widget.size,
      width: widget.size,
      memCacheWidth: widget.decodeSide,
      filterQuality: FilterQuality.medium,
      imageUrl: _url,
      httpHeaders: kCoverImageHeaders,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      useOldImageOnUrlChange: true,
      errorWidget: (_, __, ___) => widget.placeholder,
      progressIndicatorBuilder: (_, __, ___) => widget.shimmer,
    );
  }
}
