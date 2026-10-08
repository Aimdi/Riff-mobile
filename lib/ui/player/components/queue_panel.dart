import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/services/discovery/discovery_service.dart';
import '/services/discovery/discovery_types.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/widgets/riff_sheet.dart';
import '/ui/widgets/shimmer_widgets/song_list_shimmer.dart';
import '/ui/widgets/snackbar.dart';
import '/ui/widgets/song_list_tile.dart';
import '/ui/widgets/up_next_queue.dart';

/// What the player's swipe-up panel shows: the queue, or songs similar to
/// the one playing (YouTube Music's Up next / Related). The tabs sit at
/// the top; [queueFooter] (loop, shuffle, save, clear) only shows with the
/// queue.
class QueuePanel extends StatefulWidget {
  const QueuePanel({
    super.key,
    required this.queueFooter,
    this.onReorderStart,
    this.onReorderEnd,
  });

  final Widget queueFooter;
  final void Function(int)? onReorderStart;
  final void Function(int)? onReorderEnd;

  /// Height of the tab strip, status bar included.
  static double headerExtent(BuildContext context) =>
      MediaQuery.paddingOf(context).top +
      RiffSpacing.sm * 2 +
      RiffSizes.chipHeight;

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  bool _similar = false;

  void _select(bool similar) {
    if (similar == _similar) return;
    HapticFeedback.selectionClick();
    setState(() => _similar = similar);
  }

  @override
  Widget build(BuildContext context) {
    final top = QueuePanel.headerExtent(context);
    return Stack(
      children: [
        if (_similar)
          SimilarSongsPanelList(
            scrollController: Get.find<PlayerController>().scrollController,
            topPadding: top,
          )
        else
          UpNextQueue(
            topPadding: top,
            onReorderEnd: widget.onReorderEnd,
            onReorderStart: widget.onReorderStart,
          ),
        Align(
          alignment: Alignment.topCenter,
          child: _QueueTabs(similar: _similar, onSelect: _select),
        ),
        if (!_similar) widget.queueFooter,
      ],
    );
  }
}

class _QueueTabs extends StatelessWidget {
  const _QueueTabs({required this.similar, required this.onSelect});
  final bool similar;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: QueuePanel.headerExtent(context),
      padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + RiffSpacing.sm,
          left: RiffSpacing.lg,
          right: RiffSpacing.lg,
          bottom: RiffSpacing.sm),
      decoration: BoxDecoration(
        // Opaque, so rows scroll under the tabs.
        color: theme.bottomSheetTheme.backgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0),
        ),
      ),
      child: Row(
        children: [
          RiffChoiceChip(
            label: 'upNext'.tr,
            selected: !similar,
            onTap: () => onSelect(false),
          ),
          const SizedBox(width: RiffSpacing.sm),
          RiffChoiceChip(
            icon: Icons.graphic_eq_rounded,
            label: 'similarSongs'.tr,
            selected: similar,
            onTap: () => onSelect(true),
          ),
        ],
      ),
    );
  }
}

/// Songs similar to the one playing. Tapping one plays it with the rest of
/// the list as the queue; the list then stays put instead of reloading for
/// the song just picked. A new song from anywhere else reloads it.
class SimilarSongsPanelList extends StatefulWidget {
  const SimilarSongsPanelList({
    super.key,
    this.scrollController,
    required this.topPadding,
  });

  final ScrollController? scrollController;
  final double topPadding;

  @override
  State<SimilarSongsPanelList> createState() => _SimilarSongsPanelListState();
}

class _SimilarSongsPanelListState extends State<SimilarSongsPanelList> {
  String? _seedId;
  String? _pickedId;
  List<MediaItem> _songs = [];
  bool _loading = false;

  Future<void> _load(MediaItem seed) async {
    setState(() {
      _loading = true;
      _seedId = seed.id;
      _pickedId = null;
    });
    var songs = <MediaItem>[];
    try {
      if (Get.isRegistered<DiscoveryService>()) {
        songs = await Get.find<DiscoveryService>()
            .similarSongs(seed, limit: 25, unheardOnly: false)
            .timeout(const Duration(seconds: 16), onTimeout: () => []);
      }
    } catch (_) {
      songs = [];
    }
    if (!mounted) return;
    setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  Future<void> _play(int i) async {
    HapticFeedback.selectionClick();
    final list = List<MediaItem>.from(_songs);
    list[i] = DiscoveryService.withSource(list[i], DiscoverySource.similar);
    _pickedId = list[i].id;
    final ok = await Get.find<PlayerController>().playPlayListSong(list, i);
    if (!ok) snackOperationFailed();
  }

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerController>();
    final bottom = MediaQuery.paddingOf(context).bottom + RiffSpacing.lg;
    return ColoredBox(
      color: Theme.of(context).bottomSheetTheme.backgroundColor ??
          Theme.of(context).colorScheme.surface,
      child: Obx(() {
        final current = player.currentSong.value;
        if (current != null &&
            current.id != _seedId &&
            current.id != _pickedId &&
            !_loading) {
          // Never start network work during build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_loading) _load(current);
          });
        }
        if (_loading || (_seedId == null && current != null)) {
          return SongListShimmer(itemCount: 8, topPadding: widget.topPadding);
        }
        if (_songs.isEmpty) {
          return ListView(
            controller: widget.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
                top: widget.topPadding + RiffSpacing.x3l,
                left: RiffSpacing.lg,
                right: RiffSpacing.lg),
            children: [
              Text(
                'noSimilarSongs'.tr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          );
        }
        return ListView.builder(
          controller: widget.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: widget.topPadding, bottom: bottom),
          itemCount: _songs.length,
          itemBuilder: (context, i) => SongListTile(
            song: _songs[i],
            onTap: () => _play(i),
          ),
        );
      }),
    );
  }
}
