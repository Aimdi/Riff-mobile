import 'package:flutter/material.dart';

import '/ui/theme/riff_tokens.dart';
import 'basic_container.dart';

class SongListShimmer extends StatelessWidget {
  const SongListShimmer({super.key, this.itemCount = 10, this.topPadding = 0});
  final int itemCount;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return RiffSkeletonPulse(
      child: ListView.builder(
          itemCount: itemCount,
          padding: EdgeInsets.only(top: topPadding, left: 0),
          itemBuilder: (_, index) {
            return _listTile();
          }),
    );
  }

  /// Row thumbnails and text lines use the row's thumbnail radius (§4.3).
  Widget _listTile() {
    return const ListTile(
      leading: BasicShimmerContainer(Size(50, 50), radius: RiffRadii.xs),
      title: BasicShimmerContainer(Size(90, 20), radius: RiffRadii.xs),
      subtitle: BasicShimmerContainer(Size(40, 15), radius: RiffRadii.xs),
      trailing: BasicShimmerContainer(Size(50, 20), radius: RiffRadii.xs),
    );
  }
}
