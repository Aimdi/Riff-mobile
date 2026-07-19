import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';

import '../screens/Settings/settings_screen_controller.dart';
import '/models/artist.dart';
import '/models/thumbnail.dart';
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

  bool get _isPodcast =>
      playlist != null &&
      (playlist!.kind == 'podcast' ||
          playlist!.playlistId.startsWith('MPSP') ||
          (playlist!.description?.toLowerCase().contains('podcast') ?? false));

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

  Widget _placeholder(BuildContext context) {
    final isCircle = artist != null;
    IconData icon;
    if (song != null) {
      icon = Icons.music_note;
    } else if (artist != null) {
      icon = Icons.person;
    } else if (_isPodcast) {
      icon = Icons.folder;
    } else if (playlist != null) {
      icon = Icons.queue_music;
    } else {
      icon = Icons.album;
    }

    // Prefer asset when available, else Material icon (folder for podcasts).
    final assetName = song != null
        ? "song"
        : artist != null
            ? "artist"
            : album != null
                ? "album"
                : null;

    return Container(
      height: size,
      width: size,
      padding: EdgeInsets.all(size * 0.18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withOpacity(0.85),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(8),
      ),
      child: assetName != null && !_isPodcast
          ? Image.asset(
              "assets/icons/$assetName.png",
              color: Colors.white.withOpacity(0.9),
              colorBlendMode: BlendMode.srcATop,
            )
          : Icon(icon, color: Colors.white, size: size * 0.45),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raw = _rawUrl;
    // Re-upscale at display time so cached/history items that stored a low-res
    // URL (often the 60px YTM stub) still render sharply.
    final imageUrl = _scaled(raw);

    /// only valid for offline songs
    final bool offlineAvailable =
        song != null && (song?.extras?["url"] ?? "").contains("file");

    // Decode at device pixels so large art isn't soft on high-DPI screens.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeSide = (size * dpr).round().clamp(64, 1600);

    return Container(
      height: size,
      width: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: artist != null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: artist != null ? null : BorderRadius.circular(5),
      ),
      child: offlineAvailable
          ? Image.file(
              File(
                  "${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/${song!.id}.png"),
              height: size,
              width: size,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => _placeholder(context),
            )
          : (imageUrl.isEmpty)
              ? _placeholder(context)
              : CachedNetworkImage(
                  height: size,
                  width: size,
                  memCacheHeight: decodeSide,
                  memCacheWidth: decodeSide,
                  filterQuality: FilterQuality.high,
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) {
                    // Retry once with the raw (unscaled) URL — quality rewrites
                    // can break signed CDN params.
                    if (raw.isNotEmpty && raw != imageUrl) {
                      return CachedNetworkImage(
                        height: size,
                        width: size,
                        memCacheHeight: decodeSide,
                        memCacheWidth: decodeSide,
                        imageUrl: raw,
                        fit: BoxFit.cover,
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
