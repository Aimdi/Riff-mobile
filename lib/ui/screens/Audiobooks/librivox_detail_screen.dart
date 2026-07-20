import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/librivox_service.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';

/// One LibriVox audiobook: cover + description + chapter list. Tap a chapter
/// (or Play) to stream it straight from archive.org.
class LibriVoxDetailScreen extends StatelessWidget {
  const LibriVoxDetailScreen({super.key, required this.book});
  final LvAudiobook book;

  List<MediaItem> _items() {
    return List.generate(book.chapters.length, (i) {
      final c = book.chapters[i];
      return MediaItem(
        id: 'librivox_${book.id}_$i',
        title: c.title,
        artist: book.author.isNotEmpty ? book.author : book.title,
        album: book.title,
        duration: c.durationSec > 0 ? Duration(seconds: c.durationSec) : null,
        artUri: book.cover.isNotEmpty ? Uri.tryParse(book.cover) : null,
        extras: {'url': c.url, 'isAudiobook': true},
      );
    });
  }

  void _playFrom(int index) {
    Get.find<PlayerController>().playPlayListSong(_items(), index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(book.title, maxLines: 1)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 200),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: book.cover,
                    width: 108,
                    height: 108,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.menu_book, size: 72),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(book.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (book.author.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(book.author,
                              style: Theme.of(context).textTheme.bodyMedium),
                        ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => _playFrom(0),
                        icon: const Icon(Icons.play_arrow),
                        label: Text('play'.tr),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (book.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(book.description,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          const Divider(height: 1),
          ...List.generate(book.chapters.length, (i) {
            final c = book.chapters[i];
            final dur = PodcastService.formatDuration(c.durationSec);
            return ListTile(
              leading: const Icon(Icons.play_circle_outline, size: 30),
              title: Text(c.title, maxLines: 2),
              subtitle: dur.isEmpty ? null : Text(dur),
              onTap: () => _playFrom(i),
            );
          }),
        ],
      ),
    );
  }
}
