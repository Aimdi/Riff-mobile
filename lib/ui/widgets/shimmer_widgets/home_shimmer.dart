import 'package:flutter/material.dart';

import '../../screens/Home/home_layout.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import 'basic_container.dart';

/// Home loading skeleton in the same shape as the real feed: title, quick
/// grid, Riff Wave card, then a shelf of covers.
class HomeShimmer extends StatelessWidget {
  const HomeShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return RiffSkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Box(width: 200, height: 30, radius: RiffRadii.sm),
                const SizedBox(height: 16),
                for (var row = 0; row < 3; row++) ...[
                  if (row > 0) const SizedBox(height: HomeLayout.tileGap),
                  const Row(
                    children: [
                      Expanded(child: _Box(height: HomeLayout.tileHeight)),
                      SizedBox(width: HomeLayout.tileGap),
                      Expanded(child: _Box(height: HomeLayout.tileHeight)),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const _Box(height: 118, radius: RiffSizes.waveRadius),
                const SizedBox(height: HomeLayout.sectionTop + 4),
                const _Box(width: 150, height: 22, radius: RiffRadii.xs),
                const SizedBox(height: HomeLayout.headerBottom + 4),
              ],
            ),
          ),
          // Shelf runs to the screen edge like the real one.
          SizedBox(
            height: HomeLayout.shelfCard + 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding:
                  const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
              itemCount: 4,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: HomeLayout.cardGap),
              itemBuilder: (_, __) => const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Box(
                      width: HomeLayout.shelfCard,
                      height: HomeLayout.shelfCard,
                      radius: RiffSizes.shelfRadius),
                  SizedBox(height: 10),
                  _Box(width: 100, height: 12, radius: RiffRadii.xs),
                  SizedBox(height: 6),
                  _Box(width: 70, height: 10, radius: RiffRadii.xs),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box(
      {this.width, required this.height, this.radius = RiffSizes.tileRadius});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
