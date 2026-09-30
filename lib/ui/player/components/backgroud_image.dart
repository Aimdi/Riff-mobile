import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/thumbnail.dart';
import '../../screens/Settings/settings_screen_controller.dart';
import '../../utils/theme_controller.dart';
import '../player_controller.dart';

class BackgroudImage extends StatelessWidget {
  const BackgroudImage({super.key, this.cacheHeight});

  final int? cacheHeight;

  @override
  Widget build(BuildContext context) {
    return GetX<PlayerController>(
      builder: (playerController) {
        final song = playerController.currentSong.value;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: KeyedSubtree(
            key: ValueKey<String>(song?.id ?? 'none'),
            child: SizedBox.expand(
              child: song == null
                  ? const SizedBox.shrink()
                  : (song.extras!['url'] ?? '').toString().contains('file')
                      ? _LocalArt(songId: song.id, cacheHeight: cacheHeight)
                      : _NetworkArt(
                          songId: song.id,
                          artUri: song.artUri?.toString() ?? '',
                          cacheHeight: cacheHeight,
                        ),
            ),
          ),
        );
      },
    );
  }
}

class _LocalArt extends StatefulWidget {
  const _LocalArt({required this.songId, this.cacheHeight});
  final String songId;
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
    if (oldWidget.songId != widget.songId) _resolve();
  }

  void _resolve() {
    _imgFile = File(
        "${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/${widget.songId}.png");
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

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeH = cacheHeight ??
        (MediaQuery.sizeOf(context).shortestSide * dpr).round().clamp(400, 1600);
    final artUrl = artUri.isEmpty ? artUri : Thumbnail(artUri).extraHigh;
    return CachedNetworkImage(
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
        return Image(
          image: imageProvider,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        );
      },
      imageUrl: artUrl,
      cacheKey: "${songId}_song_hq",
    );
  }
}
