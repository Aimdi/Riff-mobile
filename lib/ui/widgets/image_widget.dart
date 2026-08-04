import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';

import '../screens/Settings/settings_screen_controller.dart';
import '/models/artist.dart';
import '/models/thumbnail.dart';
import '/services/cover_resolver.dart';
import '../../models/album.dart';
import '../../models/playlist.dart';

class ImageWidget extends StatelessWidget {
  const ImageWidget({
    super.key,
    this.song,
    this.playlist,
    this.album,
    this.artist,
    required this.size,
    this.isPlayerArtImage = false,
  });
  final MediaItem? song;
  final Playlist? playlist;
  final Album? album;
  final bool isPlayerArtImage;
  final Artist? artist;
  final double size;

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

  /// Asset used when the network image fails.
  String get _fallbackAsset {
    if (song != null) return "assets/icons/song.png";
    if (artist != null) return "assets/icons/artist.png";
    // Playlists and podcasts share the album placeholder (square cover art).
    return "assets/icons/album.png";
  }

  Widget _placeholder(BuildContext context) {
    final isCircle = artist != null;
    return Container(
      height: size,
      width: size,
      padding: EdgeInsets.all(size * 0.18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withOpacity(0.85),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(10),
      ),
      child: Image.asset(
        _fallbackAsset,
        color: Colors.white.withOpacity(0.9),
        colorBlendMode: BlendMode.srcATop,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raw = _rawUrl;
    final imageUrl = _scaled(raw);

    final bool offlineAvailable =
        song != null && (song?.extras?["url"] ?? "").contains("file");

    // Only constrain the longer edge so landscape video frames stay cropped
    // (BoxFit.cover) instead of stretched into a square.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeSide = (size * dpr).round().clamp(64, 1600);

    return Container(
      height: size,
      width: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: artist != null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: artist != null ? null : BorderRadius.circular(10),
      ),
      child: offlineAvailable
          ? Image.file(
              File(
                  "${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/${song!.id}.png"),
              height: size,
              width: size,
              cacheWidth: decodeSide,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => _placeholder(context),
            )
          : (imageUrl.isEmpty)
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
                  : CachedNetworkImage(
                  height: size,
                  width: size,
                  // One dimension only — setting both forces a square decode and
                  // elongates 16:9 YouTube frames.
                  memCacheWidth: decodeSide,
                  filterQuality: FilterQuality.medium,
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorWidget: (context, url, error) {
                    if (raw.isNotEmpty && raw != imageUrl) {
                      return CachedNetworkImage(
                        height: size,
                        width: size,
                        memCacheWidth: decodeSide,
                        imageUrl: raw,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        errorWidget: (_, __, ___) => _placeholder(context),
                        progressIndicatorBuilder: (_, __, ___) =>
                            _shimmer(context),
                      );
                    }
                    return _placeholder(context);
                  },
                  progressIndicatorBuilder: ((_, __, ___) => _shimmer(context)),
                ),
    );
  }

  Widget _shimmer(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[500]!,
      highlightColor: Colors.grey[300]!,
      enabled: true,
      direction: ShimmerDirection.ltr,
      child: Container(
        decoration: BoxDecoration(
          shape: artist != null ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: artist != null ? null : BorderRadius.circular(10),
          color: Colors.white54,
        ),
      ),
    );
  }
}

/// Shows a song's 16:9 video frame immediately, then swaps to the square
/// audio-track cover once [CoverResolver] finds it (instant when cached).
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
    _url = _scaled(widget.song.artUri?.toString() ?? '');
    final vid = widget.song.id;
    final cached = CoverResolver.cached(vid);
    if (cached != null && cached.isNotEmpty) {
      _url = _scaled(cached);
    } else if (cached == null) {
      CoverResolver.resolve(vid,
              title: widget.song.title, artist: widget.song.artist)
          .then((square) {
        if (square != null && square.isNotEmpty && mounted) {
          setState(() => _url = _scaled(square));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      height: widget.size,
      width: widget.size,
      memCacheWidth: widget.decodeSide,
      filterQuality: FilterQuality.medium,
      imageUrl: _url,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorWidget: (_, __, ___) => widget.placeholder,
      progressIndicatorBuilder: (_, __, ___) => widget.shimmer,
    );
  }
}
