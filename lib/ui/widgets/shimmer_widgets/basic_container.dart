import 'package:flutter/material.dart';

class BasicShimmerContainer extends StatelessWidget {
  const BasicShimmerContainer(this.size, {super.key, this.radius = 10});
  final Size size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          // Inside a Shimmer only the alpha shows; 0.54 as before.
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHigh
              .withOpacity(0.54)),
      height: size.height,
      width: size.width,
    );
  }
}
