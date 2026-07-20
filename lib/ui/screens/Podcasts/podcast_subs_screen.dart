import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/widgets/content_list_widget_item.dart';
import 'podcasts_library_controller.dart';

/// Subscriptions ("Abonnements"): a grid of every podcast you follow. Tap a
/// cover to open the show. Mirrors AntennaPod's Subscriptions screen; the data
/// is the same library the Podcasts tab already keeps.
class PodcastSubsScreen extends StatelessWidget {
  const PodcastSubsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LibraryPodcastsController>();
    return Scaffold(
      appBar: AppBar(title: Text("subscriptions".tr)),
      body: Obx(() {
        final subs = controller.libraryPodcasts;
        if (subs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "noPodcastsBookmarked".tr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }
        return LayoutBuilder(builder: (context, constraints) {
          const itemWidth = 130.0;
          const itemHeight = 180.0;
          final columns =
              (constraints.maxWidth / itemWidth).floor().clamp(2, 6);
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 200),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: itemWidth / itemHeight,
            ),
            itemCount: subs.length,
            itemBuilder: (context, index) => Center(
              child: ContentListItem(
                content: subs[index],
                isLibraryItem: true,
              ),
            ),
          );
        });
      }),
    );
  }
}
