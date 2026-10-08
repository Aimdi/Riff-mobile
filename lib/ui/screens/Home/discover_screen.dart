import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/widgets/discovery/riff_wave_hero.dart';
import '/ui/widgets/riff_header_bar.dart';
import '../Library/library.dart' show LibraryHeader;
import '../Search/components/search_pill.dart';
import 'explore_screen.dart';
import 'home_station_chips.dart';

/// The Discover rail tab, right under Home: search on top (a tap opens the
/// Search screen with its history and suggestions), then a feed that
/// scrolls under it: Riff Wave with its station chips ([DiscoverWave]),
/// and the Explore feed (YouTube's genre chips and every YouTube Music
/// shelf).
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          top: context.isLandscape
              ? RiffSpacing.tabTopLandscape
              : RiffSpacing.tabTop),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LibraryHeader(title: 'discoverTab'.tr),
          const Padding(
            padding: EdgeInsets.only(
                left: RiffSpacing.gutter,
                top: RiffSpacing.xs,
                right: RiffSpacing.gutter,
                bottom: RiffSpacing.sm),
            child: SearchLauncherField(),
          ),
          const Expanded(
            child: RiffScrollUnder(
              child: ExploreFeed(leading: [DiscoverWave()]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Riff Wave at the top of Discover's feed: the station card and its
/// station chips, then a full-width hairline that sets them apart from
/// YouTube's genre chips and shelves. Scrolls with the feed.
class DiscoverWave extends StatelessWidget {
  const DiscoverWave({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiffWaveHero(),
        RiffStationChips(),
        Divider(height: RiffSpacing.lg),
      ],
    );
  }
}
