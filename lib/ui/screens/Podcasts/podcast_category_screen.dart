import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/podcast_service.dart';
import 'podcasts_screen.dart';

/// Browse the top podcasts in an Apple Podcasts category (genre). Tapping a
/// card opens that podcast's episode list.
class PodcastCategoryScreen extends StatefulWidget {
  const PodcastCategoryScreen(
      {super.key, required this.genreId, required this.name});
  final String genreId;
  final String name;

  @override
  State<PodcastCategoryScreen> createState() => _PodcastCategoryScreenState();
}

class _PodcastCategoryScreenState extends State<PodcastCategoryScreen> {
  List<Map<String, dynamic>> _podcasts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await PodcastService.topByGenre(widget.genreId);
    if (mounted) {
      setState(() {
        _podcasts = res;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name, maxLines: 1)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _podcasts.isEmpty
              ? Center(child: Text('noResults'.tr))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 40),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.78,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _podcasts.length,
                  itemBuilder: (context, i) {
                    final p = _podcasts[i];
                    final art = Thumbnail((p['artwork'] ?? '').toString()).high;
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () =>
                          Get.to(() => PodcastEpisodesScreen(podcast: p)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: art,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: theme.colorScheme.secondary
                                      .withOpacity(0.3),
                                  child: const Icon(Icons.podcasts, size: 48),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text((p['title'] ?? '').toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall),
                          if ((p['author'] ?? '').toString().trim().isNotEmpty)
                            Text((p['author'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
