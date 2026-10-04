import '../Home/home_layout.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/services/podcast_service.dart';
import '/ui/widgets/podcast_play.dart';
import '/ui/widgets/shimmer_widgets/song_list_shimmer.dart';
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
      body: Column(children: [
        RiffPageHeader(widget.name),
        Expanded(
          child: _loading
              ? const SongListShimmer(itemCount: 8, topPadding: 8)
              : _podcasts.isEmpty
                  ? Center(child: Text('noResults'.tr))
                  : GridView.builder(
                      padding: const EdgeInsets.only(
                          left: RiffSpacing.md,
                          top: RiffSpacing.md,
                          right: RiffSpacing.md,
                          bottom: RiffSpacing.unit * 10),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.78,
                        crossAxisSpacing: RiffSpacing.md,
                        mainAxisSpacing: RiffSpacing.md,
                      ),
                      itemCount: _podcasts.length,
                      itemBuilder: (context, i) {
                        final p = _podcasts[i];
                        final art =
                            Thumbnail((p['artwork'] ?? '').toString()).high;
                        // §5.3 card: no background, art radius 8,
                        // titleMedium / bodyMedium, gap 8.
                        return InkWell(
                          borderRadius: BorderRadius.circular(RiffRadii.sm),
                          onTap: () async {
                            if (shouldPlayPodcastShowOnTap()) {
                              final ok = await playPodcastShow(p);
                              if (ok) return;
                            }
                            Get.to(() => PodcastEpisodesScreen(podcast: p));
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(RiffRadii.sm),
                                  child: CachedNetworkImage(
                                    imageUrl: art,
                                    width: double.infinity,
                                    memCacheWidth:
                                        ((MediaQuery.sizeOf(context).width -
                                                    30) /
                                                2 *
                                                MediaQuery.devicePixelRatioOf(
                                                    context))
                                            .round(),
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color:
                                          theme.colorScheme.surfaceContainerLow,
                                      child: Icon(Icons.podcasts,
                                          size:
                                              RiffComponentSizes.emptyStateIcon,
                                          color: theme
                                              .colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: RiffSpacing.sm),
                              Text((p['title'] ?? '').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium),
                              if ((p['author'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                                Text((p['author'] ?? '').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme
                                            .colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
