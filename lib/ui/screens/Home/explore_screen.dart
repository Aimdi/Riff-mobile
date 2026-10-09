import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/widgets/empty_play_hint.dart';
import '../../widgets/shimmer_widgets/home_shimmer.dart';
import 'home_feed_builder.dart';
import 'home_feed_data.dart';
import 'home_layout.dart';
import 'home_metrics.dart';
import 'home_screen_controller.dart';
import 'home_shelves.dart';

/// "Explore more": every YouTube Music shelf (Home shows four), plus
/// YouTube's genre chips, which filter this page.
class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key, this.focusTitle});

  /// When set, scroll that shelf into view after first frame.
  final String? focusTitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: Column(
        children: [
          RiffPageHeader('explore'.tr, onBack: () => Get.back(id: 1)),
          Expanded(child: ExploreFeed(focusTitle: focusTitle)),
        ],
      ),
    );
  }
}

/// The Explore page's content: YouTube's genre chips and every YouTube
/// Music shelf they filter. Shown by [ExploreScreen] and the Discover tab.
class ExploreFeed extends StatefulWidget {
  const ExploreFeed({super.key, this.focusTitle, this.leading = const []});

  /// When set, scroll that shelf into view after first frame.
  final String? focusTitle;

  /// Shown above the genre chips and scrolling with the feed (the Discover
  /// tab puts Riff Wave here).
  final List<Widget> leading;

  @override
  State<ExploreFeed> createState() => _ExploreFeedState();
}

class _ExploreFeedState extends State<ExploreFeed> {
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
    final ctx = _keys[focus]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  List<HomeShelfData> _shelves(List raw) {
    final shelves = [
      for (final s in raw)
        if (youTubeShelf(s) case final shelf?) shelf,
    ];
    return [
      for (final s in shelves)
        if (s.items.isNotEmpty) s.copyWith(title: homeSentenceCase(s.title)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeScreenController>();
    return LayoutBuilder(builder: (context, c) {
      final metrics = HomeMetrics(c.maxWidth);
      return Obx(() {
        final chips = home.homeChips.toList();
        final selected = home.selectedChip.value;
        final loading = home.chipLoading.value;
        final error = home.chipError.value;
        final shelves = _shelves(selected != null
            ? home.chipContent.toList()
            : [...home.middleContent, ...home.fixedContent]);
        return ListView(
          controller: _scroll,
          padding: EdgeInsets.only(bottom: homeBottomPadding(context)),
          children: [
            ...widget.leading,
            if (chips.isNotEmpty)
              SizedBox(
                height: RiffSizes.chipRow,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: RiffSpacing.gutter),
                  itemCount: chips.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final chip = chips[i];
                    return Center(
                      child: FilterChip(
                        label: Text(chip.title),
                        selected: chip == selected,
                        onSelected: (_) => home.selectChip(chip),
                      ),
                    );
                  },
                ),
              ),
            if (selected != null && loading)
              const HomeShimmer()
            else if (selected != null && error)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: FilledButton(
                    onPressed: () {
                      home.selectChip(null);
                      home.selectChip(selected);
                    },
                    child: Text('retry'.tr),
                  ),
                ),
              )
            else if (shelves.isEmpty)
              SizedBox(
                height: 320,
                child: EmptyPlayHint(message: 'discoverEmptyDes'.tr),
              )
            else
              for (final s in shelves)
                KeyedSubtree(
                  key: _keys.putIfAbsent(s.title, GlobalKey.new),
                  child: RiffShelf(
                    shelf: s,
                    metrics: metrics,
                    controller: home.scrollControllerFor(
                        'explore_${selected?.title ?? ''}_${s.title}'),
                  ),
                ),
          ],
        );
      });
    });
  }
}
