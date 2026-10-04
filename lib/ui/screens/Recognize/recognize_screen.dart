import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '/services/song_recognition/shazam_client.dart';
import '/services/song_recognition/song_recognizer.dart';
import '/ui/navigator.dart';
import '/ui/screens/Search/search_play_top.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/riff_equalizer.dart';
import '/ui/widgets/snackbar.dart';
import '../Home/home_layout.dart';
import '../Home/home_metrics.dart';

/// "What's playing?": tap the button, Riff listens and names the song
/// (Shazam, the way Audire does it), then plays or searches it in Riff.
class RecognizeScreen extends StatefulWidget {
  const RecognizeScreen({super.key});

  @override
  State<RecognizeScreen> createState() => _RecognizeScreenState();
}

class _RecognizeScreenState extends State<RecognizeScreen> {
  late final SongRecognizer rec = Get.isRegistered<SongRecognizer>()
      ? Get.find<SongRecognizer>()
      : Get.put(SongRecognizer(), permanent: true);

  @override
  void initState() {
    super.initState();
    // Opening the screen is the "listen" tap.
    WidgetsBinding.instance.addPostFrameCallback((_) => rec.start());
  }

  @override
  void dispose() {
    rec.stop();
    super.dispose();
  }

  Future<void> _play(RecognizedSong s) async {
    HapticFeedback.lightImpact();
    final ok = await playTopSongResult(s.query);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          snackbar(context, 'operationFailed'.tr, size: SanckBarSize.MEDIUM));
    }
  }

  void _search(RecognizedSong s) =>
      Get.toNamed(ScreenNavigationSetup.searchResultScreen,
          id: ScreenNavigationSetup.id, arguments: s.query);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          RiffPageHeader('whatsPlaying'.tr),
          Expanded(
            child: Obx(() {
              final state = rec.state.value;
              final song = rec.result.value;
              final history = rec.history.toList();
              return ListView(
                padding: EdgeInsets.only(bottom: homeBottomPadding(context)),
                children: [
                  const SizedBox(height: RiffSpacing.xxl),
                  Center(
                    child: _ListenButton(
                      listening: state == RecognitionState.listening,
                      level: rec.level,
                      onTap: () => state == RecognitionState.listening
                          ? rec.stop()
                          : rec.start(),
                    ),
                  ),
                  const SizedBox(height: RiffSpacing.xl),
                  _StatusText(state: state, seconds: rec.seconds.value),
                  if (state == RecognitionState.noPermission)
                    Padding(
                      padding: const EdgeInsets.only(top: RiffSpacing.md),
                      child: Center(
                        child: OutlinedButton(
                          onPressed: openAppSettings,
                          child: Text('recognizeOpenSettings'.tr),
                        ),
                      ),
                    ),
                  if (state == RecognitionState.matched && song != null)
                    _ResultCard(
                      song: song,
                      onPlay: () => _play(song),
                      onSearch: () => _search(song),
                    ),
                  if (history.isNotEmpty) ...[
                    HomeSectionHeader('recognizeRecent'.tr),
                    for (final h in history)
                      _HistoryRow(
                        song: h,
                        onPlay: () => _play(h),
                        onSearch: () => _search(h),
                        onRemove: () => rec.removeFromHistory(h),
                      ),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: RiffSpacing.gutter,
                        vertical: RiffSpacing.xxl),
                    child: Text(
                      'recognizeCredit'.tr,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Big round accent button; while listening, rings pulse with the mic
/// level and an equalizer plays inside.
class _ListenButton extends StatelessWidget {
  const _ListenButton(
      {required this.listening, required this.level, required this.onTap});
  final bool listening;
  final RxDouble level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = RiffComponentSizes.recognizeButton;
    return Semantics(
      button: true,
      label: listening ? 'recognizeListening'.tr : 'recognizeTapToListen'.tr,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size * RiffComponentSizes.recognizeRingScale,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (listening)
              Obx(() {
                final l = level.value;
                return AnimatedContainer(
                  duration: RiffDurations.press,
                  width: size * (1 + RiffComponentSizes.recognizeRingGrow * l),
                  height: size * (1 + RiffComponentSizes.recognizeRingGrow * l),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary
                        .withOpacity(RiffPalette.recognizeRingOpacity),
                  ),
                );
              }),
            Material(
              color: scheme.primary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
                child: SizedBox.square(
                  dimension: size,
                  child: Center(
                    child: listening
                        ? RiffEqualizer(
                            animate: true,
                            color: scheme.onPrimary,
                            size: RiffComponentSizes.recognizeGlyph)
                        : Icon(Icons.mic_rounded,
                            size: RiffComponentSizes.recognizeGlyph,
                            color: scheme.onPrimary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.state, required this.seconds});
  final RecognitionState state;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, hint) = switch (state) {
      RecognitionState.listening => (
          'recognizeListening'.tr,
          'recognizeListeningHint'.tr
        ),
      RecognitionState.noMatch => ('recognizeNoMatch'.tr, ''),
      RecognitionState.error => (
          SongRecognizer.supported
              ? 'recognizeError'.tr
              : 'recognizeOnlyAndroid'.tr,
          ''
        ),
      RecognitionState.noPermission => ('recognizeNoMic'.tr, ''),
      RecognitionState.matched => ('', ''),
      RecognitionState.idle => ('recognizeTapToListen'.tr, ''),
    };
    if (title.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.gutter),
      child: Column(
        children: [
          Text(title,
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: RiffSpacing.xs),
            Text(hint,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.size, required this.radius});
  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Icon(Icons.music_note_rounded,
          size: size / 3, color: scheme.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: url == null
            ? fallback
            : Image.network(url!,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard(
      {required this.song, required this.onPlay, required this.onSearch});
  final RecognizedSong song;
  final VoidCallback onPlay;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [song.album, song.released]
        .where((e) => e != null && e.isNotEmpty)
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.gutter),
      child: Column(
        children: [
          _Cover(
              url: song.coverUrl,
              size: RiffComponentSizes.recognizeCover,
              radius: RiffRadii.sm),
          const SizedBox(height: RiffSpacing.lg),
          Text(song.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall),
          const SizedBox(height: RiffSpacing.xxs),
          Text(song.artist,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: RiffSpacing.xxs),
            Text(meta,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: RiffSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('play'.tr),
              ),
              const SizedBox(width: RiffSpacing.md),
              OutlinedButton.icon(
                onPressed: onSearch,
                icon: const Icon(Icons.search_rounded),
                label: Text('search'.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.song,
    required this.onPlay,
    required this.onSearch,
    required this.onRemove,
  });
  final RecognizedSong song;
  final VoidCallback onPlay;
  final VoidCallback onSearch;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onPlay,
      leading: _Cover(
          url: song.coverUrl,
          size: RiffComponentSizes.rowArt,
          radius: RiffRadii.xs),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'search'.tr,
            iconSize: RiffComponentSizes.trailingIcon,
            color: theme.colorScheme.onSurfaceVariant,
            icon: const Icon(Icons.search_rounded),
            onPressed: onSearch,
          ),
          IconButton(
            tooltip: 'recognizeRemove'.tr,
            iconSize: RiffComponentSizes.trailingIcon,
            color: theme.colorScheme.onSurfaceVariant,
            icon: const Icon(Icons.close_rounded),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
