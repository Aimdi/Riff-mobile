import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../utils/riff_tokens.dart';

/// One set of Home spacing / type values so every shelf lines up.
class HomeLayout {
  HomeLayout._();

  /// Horizontal page padding next to the side rail.
  static const double gutter = 12;

  /// Space above a section title.
  static const double sectionTop = 24;

  /// Space between a section title and its content.
  static const double headerBottom = 10;

  /// Gap between cards on a horizontal shelf.
  static const double cardGap = 12;

  /// Square art on song shelves (Jump back in, discovery rows).
  static const double shelfCard = 128;

  /// Daily-mix collage covers.
  static const double mixCard = 144;

  /// Quick-access grid tile.
  static const double tileHeight = 56;
  static const double tileGap = 8;
}

TextStyle homeSectionTitleStyle(BuildContext context) =>
    (Theme.of(context).textTheme.titleLarge ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w700,
      fontSize: 19,
      letterSpacing: -0.35,
      height: 1.2,
    );

TextStyle homeCardTitleStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.titleSmall ?? const TextStyle()).copyWith(
    color: theme.textTheme.titleMedium?.color,
    fontWeight: FontWeight.w600,
    fontSize: 13.5,
    height: 1.2,
    letterSpacing: -0.1,
  );
}

/// Muted secondary text that works on Pitch Black, light and album themes.
Color? homeMutedColor(BuildContext context) =>
    Theme.of(context).textTheme.titleSmall?.color;

TextStyle homeCardSubtitleStyle(BuildContext context) =>
    (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: homeMutedColor(context),
      fontWeight: FontWeight.w400,
      fontSize: 12,
      height: 1.25,
    );

/// Raised tile surface: a step above the page on dark themes, a white card
/// with a hairline on the light theme.
Color homeTileColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? Color.alphaBlend(Colors.white.withOpacity(0.06), theme.cardColor)
      : theme.cardColor;
}

BorderSide homeTileBorder(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? BorderSide.none
      : BorderSide(color: theme.dividerColor, width: 1);
}

/// Section title row shared by every Home shelf.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader(
    this.title, {
    super.key,
    this.badge,
    this.trailing,
    this.top = HomeLayout.sectionTop,
  });

  final String title;

  /// Short pill after the title (e.g. "Updated").
  final String? badge;
  final Widget? trailing;
  final double top;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        HomeLayout.gutter,
        top,
        trailing == null ? HomeLayout.gutter : 2,
        HomeLayout.headerBottom,
      ),
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: homeSectionTitleStyle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge!,
                        style: TextStyle(
                          color: accent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Accent "play all" button for a section header.
class HomeSectionPlayButton extends StatelessWidget {
  const HomeSectionPlayButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    // Sized to the 30dp header row so titles with and without a button
    // keep the same spacing.
    return IconButton(
      tooltip: 'playAll'.tr,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 30),
      icon: Icon(Icons.play_circle_fill_rounded, color: accent, size: 30),
      onPressed: onPressed,
    );
  }
}

/// Horizontal shelf of [HomeShelfCard]s with Home gutters and spacing.
class HomeShelf extends StatelessWidget {
  const HomeShelf({
    super.key,
    required this.cardSize,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
  });

  final double cardSize;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;

  /// Title + subtitle block under a card, grown with the system text size.
  static double textBlockHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return 8 + scaler.scale(13.5) * 1.2 + 2 + scaler.scale(12) * 1.25 + 6;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: cardSize + textBlockHeight(context),
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(width: HomeLayout.cardGap),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// Square art with a one-line title and muted subtitle underneath.
class HomeShelfCard extends StatelessWidget {
  const HomeShelfCard({
    super.key,
    required this.size,
    required this.art,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.onLongPress,
  });

  final double size;
  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: InkWell(
        borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
              child: SizedBox.square(dimension: size, child: art),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: homeCardTitleStyle(context),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: homeCardSubtitleStyle(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top of a pushed page: back button and a large title, with optional
/// subtitle and actions. Shared by Explore, Stats, Rewind, the podcast and
/// plugin screens so every sub-page opens the same way.
class RiffPageHeader extends StatelessWidget {
  const RiffPageHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.actions = const [],
    this.onBack,
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// Defaults to popping the nested (tab) navigator.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final fg = Theme.of(context).textTheme.titleMedium?.color;
    return Padding(
      padding: EdgeInsets.fromLTRB(2, top + 8, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'back'.tr,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: onBack ??
                () => Get.nestedKey(1)?.currentState?.maybePop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: fg)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: homeCardSubtitleStyle(context)),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
