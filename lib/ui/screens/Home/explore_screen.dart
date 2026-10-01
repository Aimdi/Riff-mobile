import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/widgets/content_list_widget.dart';
import '/ui/widgets/empty_play_hint.dart';
import 'home_layout.dart';
import 'home_screen_controller.dart';

/// Full-page browse destination for Home's former editorial carousels
/// (Throwback, Charts, Hits, …). Opened from the Explore chip row.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, this.focusTitle});

  /// When set, scroll that shelf into view after first frame.
  final String? focusTitle;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    final focus = (widget.focusTitle ?? '').trim();
    if (focus.isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToFocus(focus));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToFocus(String focus) {
    final key = _keys[focus];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeScreenController>();
    final shelves = <dynamic>[
      ...home.middleContent,
      ...home.fixedContent,
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: Column(
        children: [
          RiffPageHeader('explore'.tr, onBack: () => Get.back(id: 1)),
          Expanded(
            child: shelves.isEmpty
                ? EmptyPlayHint(message: 'discoverEmptyDes'.tr)
                : ListView.builder(
                    controller: _scroll,
                    padding:
                        const EdgeInsets.only(left: 12, right: 12, bottom: 200),
                    itemCount: shelves.length,
                    itemBuilder: (context, index) {
                      final content = shelves[index];
                      final title = '${content.title}';
                      final key = _keys.putIfAbsent(title, GlobalKey.new);
                      final listKey = 'explore_$title';
                      return Padding(
                        key: key,
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ContentListWidget(
                          content: content,
                          scrollController: home.scrollControllerFor(listKey),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
