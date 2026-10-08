import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/widgets/riff_header_bar.dart';
import '../Library/library.dart' show LibraryHeader;
import '../Search/components/search_pill.dart';
import 'explore_screen.dart';

/// The Discover rail tab, right under Home: search on top (a tap opens the
/// Search screen with its history and suggestions) and the Explore feed
/// (YouTube's genre chips and every YouTube Music shelf) below it.
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
          const Expanded(child: RiffScrollUnder(child: ExploreFeed())),
        ],
      ),
    );
  }
}
