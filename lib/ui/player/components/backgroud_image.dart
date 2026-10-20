import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/thumbnail.dart';
import '../../screens/Settings/settings_screen_controller.dart';
import '../../utils/theme_controller.dart';
import '../player_controller.dart';
import 'track_crossfade.dart';
import 'track_swipe.dart' show upNextTrack;
import '/ui/widgets/image_widget.dart' show RiffNetworkImage;

/// The playing song's cover, filling its box. A new song's cover fades in
/// over the last one once it's decoded ([TrackCrossfade]), and the next
/// song's is decoded ahead so a skip to it changes at once.
class BackgroudImage extends StatelessWidget {
  const BackgroudImage({super.key, this.cacheHeight});

  final int? cacheHeight;

  @override
  Widget build(BuildContext context) {
    return GetX<PlayerController>(
      builder: (playerController) {
        final song = playerController.currentSong.value;
        final decodeH = _NetworkArt.decodeHeight(context, cacheHeight);
        return TrackCrossfade(
          trackKey: song?.id ?? 'none',
          precache: song == null
              ? null
              : (context) => _precache(context, song, decodeH),
          onSettled: () {
            final next = upNextTrack(playerController);
            if (next != null && next.id != song?.id) {
              _precache(context, next, decodeH);
            }
          },
          child: SizedBox.expand(
            child: song == null
                ? const SizedBox.shrink()
                // A cover on the phone itself (a music file's album cover).
                : song.artUri?.isScheme('file') == true
                    ? _LocalArt(
                        songId: song.id,
                        path: song.artUri!.toFilePath(),
                        cacheHeight: cacheHeight,
                      )
                    : _isDownloaded(song)
                        ? _LocalArt(songId: song.id, cacheHeight: cacheHeight)
                        : _NetworkArt(
                            songId: song.id,
                            artUri: song.artUri?.toString() ?? '',
                            cacheHeight: cacheHeight,
                          ),
          ),
        );
      },
    );
  }

  static bool _isDownloaded(MediaItem song) =>
      (song.extras?['url'] ?? '').toString().contains('file');

  /// Decodes [song]'s cover as it's shown here, so it paints at once; null
  /// when there's nothing to decode.
  Future<void>? _precache(BuildContext context, MediaItem song, int decodeH) {
    final ImageProvider? image;
    if (song.artUri?.isScheme('file') == true) {
      image = ResizeImage.resizeIfNeeded(
          null, cacheHeight, FileImage(File(song.artUri!.toFilePath())));
    } else if (_isDownloaded(song)) {
      image = Get.isRegistered<SettingsScreenController>()
          ? ResizeImage.resizeIfNeeded(
              null, cacheHeight, FileImage(_LocalArt.thumbnail(song.id)))
          : null;
    } else {
      image =
          _NetworkArt.provider(song.id, song.artUri?.toString() ?? '', decodeH);
    }
    if (image == null) return null;
    return precacheImage(image, context, onError: (_, __) {});
  }
}

class _LocalArt extends StatefulWidget {
  const _LocalArt({required this.songId, this.path, this.cacheHeight});
  final String songId;

  /// A download's saved cover.
  static File thumbnail(String songId) => File(
      "${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/$songId.png");

  /// The cover's file; a download's saved thumbnail when not given.
  final String? path;
  final int? cacheHeight;

  @override
  State<_LocalArt> createState() => _LocalArtState();
}

class _LocalArtState extends State<_LocalArt> {
  late File _imgFile;
  // Cached so rebuilds don't restart the existence check (which painted a
  // blank frame every time).
  late Future<bool> _exists;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _LocalArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId || oldWidget.path != widget.path) {
      _resolve();
    }
  }

  void _resolve() {
    _imgFile = widget.path != null
        ? File(widget.path!)
        : _LocalArt.thumbnail(widget.songId);
    _exists = _imgFile.exists();
  }

  @override
  Widget build(BuildContext context) {
    final imgFile = _imgFile;
    final cacheHeight = widget.cacheHeight;
    return FutureBuilder<bool>(
      future: _exists,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData &&
            snapshot.data == true) {
          // setTheme dedupes per song id, so calling it from build is cheap.
          if (Get.find<SettingsScreenController>().themeModetype.value ==
              ThemeType.dynamic) {
            Get.find<ThemeController>()
                .setTheme(FileImage(imgFile), widget.songId);
          }
          return Image.file(
            imgFile,
            cacheHeight: cacheHeight,
            fit: BoxFit.cover,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _NetworkArt extends StatelessWidget {
  const _NetworkArt({
    required this.songId,
    required this.artUri,
    this.cacheHeight,
  });
  final String songId;
  final String artUri;
  final int? cacheHeight;

  static int decodeHeight(BuildContext context, int? cacheHeight) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return cacheHeight ??
        (MediaQuery.sizeOf(context).shortestSide * dpr)
            .round()
            .clamp(400, 1600);
  }

  static String _url(String artUri) =>
      artUri.isEmpty ? artUri : Thumbnail(artUri).extraHigh;

  static String _cacheKey(String songId) => "${songId}_song_hq";

  /// The image [CachedNetworkImage] below decodes (same cache entry).
  static ImageProvider? provider(String songId, String artUri, int decodeH) {
    final url = _url(artUri);
    if (url.isEmpty) return null;
    return ResizeImage.resizeIfNeeded(null, decodeH,
        CachedNetworkImageProvider(url, cacheKey: _cacheKey(songId)));
  }

  @override
  Widget build(BuildContext context) {
    final decodeH = decodeHeight(context, cacheHeight);
    final artUrl = _url(artUri);
    final playerController = Get.find<PlayerController>();
    return RiffNetworkImage(
      memCacheHeight: decodeH,
      filterQuality: FilterQuality.high,
      imageBuilder: (context, imageProvider) {
        if (Get.find<SettingsScreenController>().themeModetype.value ==
            ThemeType.dynamic) {
          Future.delayed(
            const Duration(milliseconds: 50),
            () => Get.find<ThemeController>().setTheme(imageProvider, songId),
          );
        }
        // Cheaper sampling while the player panel moves (the cover is
        // being resized every frame there); full quality once it's open.
        return Obx(() => Image(
              image: imageProvider,
              fit: BoxFit.cover,
              filterQuality: playerController.isPlayerPanelOpen.isTrue
                  ? FilterQuality.high
                  : FilterQuality.medium,
            ));
      },
      imageUrl: artUrl,
      cacheKey: _cacheKey(songId),
    );
  }
}
