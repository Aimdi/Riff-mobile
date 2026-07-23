import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/widgets/content_list_widget.dart';
import 'home_screen_controller.dart';

/// Full-page browse destination for Home's former editorial carousels
/// (Throwback, Charts, Hits, …). Opened from the Explore chip row.
class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key, this.focusTitle});

  /// When set, scroll that shelf into view after first frame.
  final String? focusTitle;

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeScreenController>();
    final shelves = <dynamic>[
      ...home.middleContent,
      ...home.fixedContent,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('explore'.tr),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(id: 1),
        ),
      ),
      body: shelves.isEmpty
          ? Center(child: Text('discoverEmptyDes'.tr))
          : ListView.builder(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 200),
              itemCount: shelves.length,
              itemBuilder: (context, index) {
                final content = shelves[index];
                final key = 'explore_${content.title}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ContentListWidget(
                    content: content,
                    scrollController: home.scrollControllerFor(key),
                  ),
                );
              },
            ),
    );
  }
}
