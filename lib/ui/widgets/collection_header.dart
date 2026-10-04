import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/downloader.dart';
import '../screens/Home/home_layout.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import 'loader.dart';

/// "12 songs · 48 min" style meta for an album / playlist header.
String collectionMetaLine(List<MediaItem> songs,
    {List<String?> lead = const []}) {
  final total =
      songs.fold<int>(0, (sum, s) => sum + (s.duration?.inSeconds ?? 0));
  final count = songs.isEmpty
      ? ''
      : songs.length == 1
          ? 'songCountOne'.tr
          : 'songCount'.trParams({'count': '${songs.length}'});
  return [...lead, count, collectionLength(total)]
      .map((e) => (e ?? '').trim())
      .where((e) => e.isNotEmpty)
      .join(' · ');
}

/// "48 min" / "1 hr 35 min"; empty when unknown.
String collectionLength(int seconds) {
  if (seconds <= 0) return '';
  final mins = (seconds / 60).round();
  if (mins < 60) return '$mins min';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '$h hr' : '$h hr $m min';
}

/// Cover, title (wraps, never cut), subtitle and meta for album / playlist
/// pages. Sized by its content so large text never overflows.
class CollectionHeader extends StatelessWidget {
  const CollectionHeader({
    super.key,
    required this.cover,
    required this.title,
    this.subtitle = '',
    this.meta = '',
    this.onCoverTap,
    this.onSubtitleTap,
    this.extra,
  });

  final Widget cover;
  final String title;
  final String subtitle;
  final String meta;
  final VoidCallback? onCoverTap;
  final VoidCallback? onSubtitleTap;

  /// Under the text (e.g. a podcast Subscribe pill).
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter,
          right: HomeLayout.gutter,
          bottom: RiffSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: onCoverTap,
            // Flat artwork, no shadow (§2.1).
            child: ClipRRect(
              borderRadius: BorderRadius.circular(RiffRadii.sm),
              child: SizedBox.square(
                  dimension: RiffComponentSizes.collectionArt, child: cover),
            ),
          ),
          const SizedBox(width: RiffSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: scheme.onSurface),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: RiffSpacing.xs),
                  GestureDetector(
                    onTap: onSubtitleTap,
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: RiffSpacing.xxs),
                  Text(
                    meta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                if (extra != null) ...[
                  const SizedBox(height: RiffSpacing.sm),
                  extra!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry of the ⋮ menu on album / playlist pages.
class CollectionMenuItem {
  const CollectionMenuItem(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Secondary actions (left, small) then shuffle and a big accent Play.
class CollectionActionRow extends StatelessWidget {
  const CollectionActionRow({
    super.key,
    required this.onPlay,
    this.onShuffle,
    this.leading = const [],
    this.menu = const [],
  });

  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final List<Widget> leading;
  final List<CollectionMenuItem> menu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter - RiffSpacing.sm,
          top: RiffSpacing.xxs,
          right: HomeLayout.gutter,
          bottom: RiffSpacing.xs),
      child: Row(
        children: [
          ...leading,
          if (menu.isNotEmpty)
            PopupMenuButton<int>(
              tooltip: 'more'.tr,
              icon: Icon(Icons.more_vert_rounded,
                  size: RiffComponentSizes.headerIcon, color: scheme.onSurface),
              onSelected: (i) => menu[i].onTap(),
              itemBuilder: (_) => [
                for (var i = 0; i < menu.length; i++)
                  PopupMenuItem(
                    value: i,
                    child: Row(children: [
                      Icon(menu[i].icon, size: RiffComponentSizes.trailingIcon),
                      const SizedBox(width: RiffSpacing.md),
                      Flexible(child: Text(menu[i].label)),
                    ]),
                  ),
              ],
            ),
          const Spacer(),
          if (onShuffle != null)
            IconButton(
              tooltip: 'shuffle'.tr,
              icon: Icon(Icons.shuffle_rounded,
                  size: RiffComponentSizes.headerIcon, color: scheme.onSurface),
              onPressed: onShuffle,
            ),
          const SizedBox(width: RiffSpacing.xs),
          // Primary action (§5.5): accent fill, onAccent glyph, no elevation.
          Material(
            color: scheme.primary,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPlay,
              child: Tooltip(
                message: 'play'.tr,
                child: SizedBox.square(
                  dimension: RiffComponentSizes.collectionPlay,
                  child: Icon(Icons.play_arrow_rounded,
                      size: RiffComponentSizes.collectionPlayIcon,
                      color: scheme.onPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Save to library toggle: an outlined plus, or an accent check once saved.
class CollectionSaveButton extends StatelessWidget {
  const CollectionSaveButton(
      {super.key, required this.saved, required this.onPressed});
  final bool saved;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: saved ? 'removeFromLibrary'.tr : 'addToLibrary'.tr,
      onPressed: onPressed,
      icon: Icon(
        saved ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
        size: RiffComponentSizes.headerIcon,
        // Toggled-on = accent (§2.5); off = plain icon colour.
        color: saved
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

/// Download-all with queued / in-progress / done states.
class CollectionDownloadButton extends StatelessWidget {
  const CollectionDownloadButton({
    super.key,
    required this.id,
    required this.songs,
    required this.isDownloaded,
    required this.tooltip,
  });

  final String id;
  final List<MediaItem> Function() songs;
  final bool isDownloaded;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GetX<Downloader>(builder: (d) {
      final queued = d.playlistQueue.containsKey(id);
      final active = queued && d.currentPlaylistId.toString() == id;
      Widget icon;
      if (isDownloaded) {
        icon = Icon(Icons.download_done_rounded,
            size: RiffComponentSizes.headerIcon, color: scheme.primary);
      } else if (active) {
        icon = Stack(alignment: Alignment.center, children: [
          Text(
            '${d.playlistDownloadingProgress.value}/${songs().length}',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurface),
          ),
          const LoadingIndicator(dimension: 28),
        ]);
      } else if (queued) {
        icon = const Stack(alignment: Alignment.center, children: [
          Icon(Icons.hourglass_bottom_rounded, size: 18),
          LoadingIndicator(dimension: 28),
        ]);
      } else {
        icon = Icon(Icons.download_for_offline_outlined,
            size: RiffComponentSizes.headerIcon, color: scheme.onSurface);
      }
      return IconButton(
        tooltip: tooltip,
        onPressed: isDownloaded ? null : () => d.downloadPlaylist(id, songs()),
        icon: icon,
      );
    });
  }
}

/// Back button for album / playlist pages, with the title fading in once the
/// header has scrolled away.
class CollectionTopBar extends StatelessWidget {
  const CollectionTopBar({
    super.key,
    required this.title,
    required this.showTitle,
    this.trailing,
  });

  final String title;
  final bool showTitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 4, left: 4, right: 4),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: Material(
                color: showTitle
                    ? Colors.transparent
                    : RiffColors.of(context).scrim.withOpacity(0.3),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  tooltip: 'back'.tr,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: showTitle
                          ? Theme.of(context).textTheme.titleMedium?.color
                          : RiffColors.of(context).onImage),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: AnimatedOpacity(
                opacity: showTitle ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
