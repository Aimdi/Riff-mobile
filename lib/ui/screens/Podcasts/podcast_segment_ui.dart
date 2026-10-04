import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/theme/riff_theme.dart';
import '/services/podcast_bookmarks.dart';
import '/services/podcast_segments.dart';
import '/ui/navigator.dart';
import '/ui/player/player_controller.dart';
import '../../widgets/riff_sheet.dart';
import '../../widgets/snackbar.dart';
import '../Home/home_layout.dart';
import 'podcast_bookmarks_ui.dart';

/// "Skip sponsor", "Skip intro"… for the pill in the podcast player.
String podcastSkipPillLabel(PlayerController pc) {
  final s = pc.activePodcastSegment.value;
  if (s == null) return 'skipAd'.tr;
  return 'skipSegment'.trParams({'category': s.category.labelKey.tr});
}

/// The Skip-ad pill (Phase 7): 36 dp accent pill with an onAccent skip
/// glyph and a 13/700 label. When [visible] turns on it fades in and slides
/// up 8 dp over 200 ms; while off it takes no room.
class PodcastSkipPill extends StatelessWidget {
  const PodcastSkipPill({
    super.key,
    required this.visible,
    required this.label,
    required this.onPressed,
    this.padding = EdgeInsets.zero,
  });

  final bool visible;
  final String label;
  final VoidCallback onPressed;

  /// Space around the pill while it shows (the callers' existing gaps).
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style =
        RiffTextStyles.of(context).pillLabel.copyWith(color: scheme.onPrimary);
    return AnimatedSwitcher(
      duration: RiffDurations.select,
      switchInCurve: RiffDurations.selectCurve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0,
                RiffComponentSizes.skipPillSlide / RiffComponentSizes.skipPill),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: !visible
          ? const SizedBox(key: ValueKey('skipPillOff'), width: double.infinity)
          : Padding(
              key: const ValueKey('skipPillOn'),
              padding: padding,
              child: Center(
                child: FilledButton.icon(
                  key: const Key('skipAdPill'),
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    minimumSize: const Size(0, RiffComponentSizes.skipPill),
                    fixedSize:
                        const Size.fromHeight(RiffComponentSizes.skipPill),
                    padding:
                        const EdgeInsets.symmetric(horizontal: RiffSpacing.md),
                    shape: const StadiumBorder(),
                    textStyle: style,
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  icon: const Icon(Icons.fast_forward_rounded,
                      size: RiffComponentSizes.skipPillIcon),
                  label: Text(label, style: style),
                ),
              ),
            ),
    );
  }
}

String _clock(double sec) => formatSegmentLength(sec);

/// Overflow button in the podcast player's top bar (music keeps the empty
/// slot): bookmarks, this episode's segments and marking new ones.
class PodcastPlayerMenuButton extends StatelessWidget {
  const PodcastPlayerMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'moreOptions'.tr,
      icon: const Icon(Icons.more_vert_rounded),
      onPressed: () => showPodcastSegmentsSheet(context),
    );
  }
}

Future<void> showPodcastSegmentsSheet(BuildContext context) {
  final pc = Get.find<PlayerController>();
  return showModalBottomSheet<void>(
    context: pc.homeScaffoldkey.currentContext ?? context,
    useRootNavigator: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 520),
    shape: riffSheetShape,
    builder: (sheet) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.8),
        child: Obx(() {
          PodcastSegmentStore.rev.value;
          final segments = pc.podcastSegments.toList();
          final item = pc.currentSong.value;
          final manual = item == null
              ? const <PodcastSegment>[]
              : PodcastSegmentStore.manual(item.id);
          final pending = pc.manualSegmentStart.value;
          PodcastBookmarkStore.rev.value;
          final bookmarks = item == null
              ? 0
              : PodcastBookmarkStore.forEpisode(item.id).length;
          return ListView(
            shrinkWrap: true,
            children: [
              const RiffSheetHandle(),
              RiffSheetTile(
                icon: Icons.bookmark_add_outlined,
                title: 'bookmarkThisMoment'.tr,
                onTap: () {
                  Navigator.of(sheet).pop();
                  bookmarkCurrentMoment(context);
                },
              ),
              RiffSheetTile(
                icon: Icons.bookmarks_outlined,
                title: 'episodeBookmarks'.tr,
                trailing: bookmarks > 0 ? Text('$bookmarks') : null,
                onTap: () {
                  Navigator.of(sheet).pop();
                  showEpisodeBookmarksSheet(context);
                },
              ),
              const RiffSheetDivider(),
              RiffSheetTitle('segmentsTitle'.tr,
                  subtitle: 'segmentsSubtitle'.tr),
              if (pc.canMarkSegments)
                pending == null
                    ? RiffSheetTile(
                        icon: Icons.flag_outlined,
                        title: 'markSegmentStart'.tr,
                        subtitle: 'markSegmentStartDes'.tr,
                        onTap: pc.markSegmentStart,
                      )
                    : RiffSheetTile(
                        icon: Icons.outlined_flag_rounded,
                        title: 'markSegmentEnd'.tr,
                        subtitle: 'markSegmentFrom'
                            .trParams({'time': _clock(pending)}),
                        onTap: () async {
                          final cat = await _pickCategory(sheet);
                          if (cat == null) return;
                          final ok = await pc.markSegmentEnd(cat);
                          if (!sheet.mounted) return;
                          ScaffoldMessenger.of(sheet).showSnackBar(snackbar(
                              sheet,
                              ok ? 'segmentMarked'.tr : 'segmentTooShort'.tr,
                              size: SanckBarSize.BIG));
                        },
                      ),
              if (pending != null)
                RiffSheetTile(
                  icon: Icons.close_rounded,
                  title: 'cancel'.tr,
                  onTap: () => pc.manualSegmentStart.value = null,
                ),
              const RiffSheetDivider(),
              if (segments.isEmpty && manual.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(
                      left: RiffSpacing.xl,
                      top: RiffSpacing.sm,
                      right: RiffSpacing.xl,
                      bottom: RiffSpacing.md),
                  child: Text('noSegments'.tr,
                      style: homeCardSubtitleStyle(context)),
                ),
              for (final s in segments)
                _SegmentRow(
                  segment: s,
                  onTap: () {
                    Navigator.of(sheet).pop();
                    pc.seek(Duration(milliseconds: (s.start * 1000).round()));
                  },
                ),
              for (final m in manual)
                if (!segments.any((s) => s.id == m.id))
                  _SegmentRow(segment: m, ignored: true),
              if (manual.isNotEmpty) ...[
                const RiffSheetDivider(),
                for (final m in manual)
                  RiffSheetTile(
                    icon: Icons.delete_outline_rounded,
                    title: 'removeMarkedSegment'.trParams({
                      'range': '${_clock(m.start)}–${_clock(m.end)}',
                    }),
                    onTap: () =>
                        PodcastSegmentStore.removeManual(item!.id, m.id),
                  ),
              ],
              const RiffSheetDivider(),
              RiffSheetTile(
                icon: Icons.tune_rounded,
                title: 'segmentSkippingSettings'.tr,
                onTap: () {
                  Navigator.of(sheet).pop();
                  pc.playerPanelController.close();
                  Get.toNamed(ScreenNavigationSetup.podcastSettingsScreen,
                      id: ScreenNavigationSetup.id);
                },
              ),
              const SizedBox(height: 8),
            ],
          );
        }),
      ),
    ),
  );
}

Future<SegmentCategory?> _pickCategory(BuildContext context) {
  return showModalBottomSheet<SegmentCategory>(
    context: context,
    useRootNavigator: true,
    constraints: const BoxConstraints(maxWidth: 520),
    shape: riffSheetShape,
    builder: (sheet) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RiffSheetHandle(),
            RiffSheetTitle('segmentWhatIsIt'.tr),
            for (final c in SegmentCategory.values)
              ListTile(
                leading: _Dot(color: c.color),
                title: Text(c.labelKey.tr),
                onTap: () => Navigator.of(sheet).pop(c),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 12});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({required this.segment, this.onTap, this.ignored = false});
  final PodcastSegment segment;
  final VoidCallback? onTap;
  final bool ignored;

  @override
  Widget build(BuildContext context) {
    final s = segment;
    final what =
        ignored ? 'segAction_ignore'.tr : 'segAction_${s.action.name}'.tr;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: _Dot(color: s.category.color),
      title: Text(s.category.labelKey.tr),
      subtitle: Text(
        '${_clock(s.start)}–${_clock(s.end)} · $what · '
        '${'segSource_${s.source.name}'.tr}',
        style: homeCardSubtitleStyle(context),
      ),
      onTap: onTap,
    );
  }
}

/// Podcast settings › Segment skipping: one action per category, with the
/// colour each one has on the seek bar, and the time saved so far.
class PodcastSegmentSettings extends StatelessWidget {
  const PodcastSegmentSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      PodcastSegmentStore.rev.value;
      final actions = PodcastSegmentStore.actions;
      final saved = PodcastSegmentStore.timeSaved;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('segmentSkippingTitle'.tr,
              style: homeSectionTitleStyle(context)),
          const SizedBox(height: 4),
          Text('segmentSkippingIntro'.tr,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: homeMutedColor(context))),
          if (saved > Duration.zero) ...[
            const SizedBox(height: 6),
            Text(
              'segmentTimeSaved'.trParams({
                'time': formatSegmentLength(saved.inMilliseconds / 1000),
              }),
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.secondary),
            ),
          ],
          for (final c in SegmentCategory.values) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _Dot(color: c.color, size: 14),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(c.labelKey.tr,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2, bottom: 8),
              child: Text('${c.labelKey}Des'.tr,
                  style: homeCardSubtitleStyle(context)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in SegmentAction.values)
                    RiffChoiceChip(
                      label: 'segAction_${a.name}'.tr,
                      selected: actions[c] == a,
                      onTap: () => PodcastSegmentStore.setAction(c, a),
                    ),
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}
