import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/spotify_api_service.dart';
import '/services/spotify_auth_service.dart';
import '/services/spotify_import_service.dart';
import '/services/spotify_match.dart';
import '/services/spotify_match_store.dart';
import '/services/spotify_playback.dart';
import '/services/spotify_radio.dart';
import '../Home/home_layout.dart';

/// Localisation key of the message for a failed Spotify call.
String spotifyErrorKey(SpotifyErrorKind kind) => switch (kind) {
      SpotifyErrorKind.signedOut => 'spotifyErrSignedOut',
      SpotifyErrorKind.forbidden => 'spotifyErrForbidden',
      SpotifyErrorKind.notFound => 'spotifyErrNotFound',
      SpotifyErrorKind.rateLimited => 'spotifyErrRateLimited',
      SpotifyErrorKind.quotaExceeded => 'spotifyErrQuota',
      SpotifyErrorKind.server => 'spotifyErrServer',
      SpotifyErrorKind.network => 'spotifyErrNetwork',
    };

/// The message for [error] (any error; Spotify ones say what to do).
String spotifyErrorText(Object error) {
  if (error is! SpotifyApiException) return 'operationFailed'.tr;
  final wait = error.retryAfter;
  return spotifyErrorKey(error.kind).trParams({
    's': '${wait?.inSeconds ?? 0}',
    'm': '${((wait?.inSeconds ?? 0) / 60).ceil()}',
  });
}

String formatTrackLength(int? ms) {
  if (ms == null || ms <= 0) return '';
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Cover art (square, or round for artists).
class SpotifyArt extends StatelessWidget {
  const SpotifyArt(
      {super.key,
      this.url,
      this.size = 48,
      this.round = false,
      this.icon = Icons.music_note_rounded});
  final String? url;
  final double size;
  final bool round;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: homeTileColor(context),
      child: Icon(icon, size: size * 0.45, color: homeMutedColor(context)),
    );
    final img = url == null || url!.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => placeholder,
          );
    return round
        ? ClipOval(child: img)
        : ClipRRect(borderRadius: BorderRadius.circular(6), child: img);
  }
}

/// Loads [load] and shows a spinner, the error (with Retry) or [builder].
/// Retry and pull-to-refresh load again past the cache.
class SpotifyAsync<T> extends StatefulWidget {
  const SpotifyAsync({
    super.key,
    required this.load,
    required this.builder,
    this.isEmpty,
    this.emptyText,
  });

  final Future<T> Function({bool force}) load;
  final Widget Function(
      BuildContext context, T data, Future<void> Function() reload) builder;
  final bool Function(T data)? isEmpty;
  final String? emptyText;

  @override
  State<SpotifyAsync<T>> createState() => _SpotifyAsyncState<T>();
}

class _SpotifyAsyncState<T> extends State<SpotifyAsync<T>> {
  late Future<T> _future = widget.load(force: false);

  Future<void> _reload() async {
    final f = widget.load(force: true);
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return _Message(
            icon: Icons.cloud_off_rounded,
            text: spotifyErrorText(snap.error!),
            action: TextButton(onPressed: _reload, child: Text('retry'.tr)),
          );
        }
        final data = snap.data as T;
        if (widget.isEmpty?.call(data) ?? false) {
          return _Message(
            icon: Icons.inbox_outlined,
            text: widget.emptyText ?? 'spotifyEmpty'.tr,
            action: TextButton(onPressed: _reload, child: Text('refresh'.tr)),
          );
        }
        return widget.builder(context, data, _reload);
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          children: [
            Icon(icon, size: 36, color: homeMutedColor(context)),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: homeCardSubtitleStyle(context).copyWith(fontSize: 14)),
            if (action != null) ...[const SizedBox(height: 6), action!],
          ],
        ),
      );
}

/// Play the tracks; tells the listener when none could be found.
Future<void> playSpotifyTracks(
    BuildContext context, List<SpotifyTrackRef> tracks,
    {int start = 0, bool shuffle = false, required String from}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await SpotifyPlayback.play(tracks,
      start: start, shuffle: shuffle, from: from);
  if (result == SpotifyPlayResult.nothingMatched ||
      result == SpotifyPlayResult.failed) {
    messenger?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(result == SpotifyPlayResult.nothingMatched
          ? 'spotifyNothingMatched'.tr
          : 'operationFailed'.tr),
    ));
  }
}

/// Play and Shuffle for a list, with a hint while songs are being found.
class SpotifyPlayBar extends StatelessWidget {
  const SpotifyPlayBar({super.key, required this.tracks, required this.from});
  final List<SpotifyTrackRef> tracks;
  final String from;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(HomeLayout.gutter, 4, HomeLayout.gutter, 4),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: tracks.isEmpty
                ? null
                : () => playSpotifyTracks(context, tracks, from: from),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text('play'.tr),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: tracks.isEmpty
                ? null
                : () => playSpotifyTracks(context, tracks,
                    start: 0, shuffle: true, from: from),
            icon: const Icon(Icons.shuffle_rounded),
            label: Text('shuffle'.tr),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Obx(() {
              final n = SpotifyPlayback.pending.value;
              return n == 0
                  ? Text('${tracks.length} ${'songs'.tr}',
                      textAlign: TextAlign.end,
                      style: homeCardSubtitleStyle(context))
                  : Text('spotifyMatching'.trParams({'n': '$n'}),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: homeCardSubtitleStyle(context));
            }),
          ),
        ],
      ),
    );
  }
}

/// One Spotify track. Tap plays the list from here; the menu changes which
/// YouTube Music recording it plays as.
class SpotifyTrackRow extends StatefulWidget {
  const SpotifyTrackRow(
      {super.key,
      required this.tracks,
      required this.index,
      required this.from});
  final List<SpotifyTrackRef> tracks;
  final int index;
  final String from;

  @override
  State<SpotifyTrackRow> createState() => _SpotifyTrackRowState();
}

class _SpotifyTrackRowState extends State<SpotifyTrackRow> {
  SpotifyTrackRef get t => widget.tracks[widget.index];

  Future<void> _menu() async {
    final match = SpotifyMatchStore.get(t.id);
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.play_arrow_rounded),
            title: Text('play'.tr),
            onTap: () => Navigator.of(ctx).pop('play'),
          ),
          ListTile(
            leading: const Icon(Icons.radio_rounded),
            title: Text('spotifyRadioFromSong'.tr),
            onTap: () => Navigator.of(ctx).pop('radio'),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz_rounded),
            title: Text('spotifyChangeMatch'.tr),
            onTap: () => Navigator.of(ctx).pop('change'),
          ),
          if (match != null)
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: Text('spotifyForgetMatch'.tr),
              onTap: () => Navigator.of(ctx).pop('forget'),
            ),
        ]),
      ),
    );
    if (!mounted) return;
    switch (picked) {
      case 'play':
        await playSpotifyTracks(context, widget.tracks,
            start: widget.index, from: widget.from);
      case 'radio':
        await startSpotifyRadio(context, seed: t);
      case 'change':
        await showSpotifyChangeMatch(context, t);
      case 'forget':
        await SpotifyMatchStore.remove(t.id);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final match = SpotifyMatchStore.get(t.id);
    final sub = [t.artists, if ((t.album ?? '').isNotEmpty) t.album!]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.only(left: HomeLayout.gutter, right: 4),
      leading: SpotifyArt(url: t.artUrl, size: 48),
      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: homeCardSubtitleStyle(context)),
      onTap: () => playSpotifyTracks(context, widget.tracks,
          start: widget.index, from: widget.from),
      onLongPress: _menu,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (match != null)
            Tooltip(
              message: match.manual
                  ? 'spotifyMatchPicked'.tr
                  : 'spotifyMatchFound'.tr,
              child: Icon(
                  match.manual
                      ? Icons.push_pin_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 16,
                  color: homeMutedColor(context)),
            ),
          const SizedBox(width: 6),
          Text(formatTrackLength(t.durationMs),
              style: homeCardSubtitleStyle(context)),
          IconButton(
            tooltip: 'spotifyChangeMatch'.tr,
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: _menu,
          ),
        ],
      ),
    );
  }
}

/// Pick which YouTube Music recording [track] plays as. The choice is
/// kept for good.
Future<void> showSpotifyChangeMatch(
    BuildContext context, SpotifyTrackRef track) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) => _ChangeMatchSheet(track: track),
  );
  if (saved == true && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('spotifyMatchSaved'.tr)));
  }
}

class _ChangeMatchSheet extends StatefulWidget {
  const _ChangeMatchSheet({required this.track});
  final SpotifyTrackRef track;

  @override
  State<_ChangeMatchSheet> createState() => _ChangeMatchSheetState();
}

class _ChangeMatchSheetState extends State<_ChangeMatchSheet> {
  late final _query = TextEditingController(text: widget.track.searchQuery);
  late Future<List<ScoredCandidate<MediaItem>>> _future = _search(null);

  Future<List<ScoredCandidate<MediaItem>>> _search(String? q) {
    if (!Get.isRegistered<SpotifyImportService>()) {
      Get.put(SpotifyImportService());
    }
    return Get.find<SpotifyImportService>().rankCandidates(widget.track,
        query: q == null || q.trim().isEmpty ? null : q.trim());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = SpotifyMatchStore.get(widget.track.id)?.videoId;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          children: [
            ListTile(
              leading: SpotifyArt(url: widget.track.artUrl),
              title: Text(widget.track.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  [
                    widget.track.artists,
                    formatTrackLength(widget.track.durationMs)
                  ].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onSubmitted: (q) => setState(() => _future = _search(q)),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<ScoredCandidate<MediaItem>>>(
                future: _future,
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list = snap.data ?? const [];
                  if (snap.hasError || list.isEmpty) {
                    return Center(child: Text('spotifyNoCandidates'.tr));
                  }
                  return ListView.builder(
                    controller: scroll,
                    itemCount: list.length,
                    itemBuilder: (ctx, i) {
                      final c = list[i];
                      final m = c.item;
                      return ListTile(
                        leading: SpotifyArt(url: m.artUri?.toString()),
                        title: Text(m.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            [
                              m.artist ?? '',
                              formatTrackLength(m.duration?.inMilliseconds),
                            ].where((s) => s.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        trailing: m.id == current
                            ? const Icon(Icons.check_rounded)
                            : Text('${(c.score * 100).round()}%',
                                style: homeCardSubtitleStyle(ctx)),
                        onTap: () async {
                          await SpotifyMatchStore.putManual(widget.track.id, m);
                          if (ctx.mounted) Navigator.of(ctx).pop(true);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Play a Spotify radio built from the user's top tracks, recent plays and
/// Liked Songs (from [seed]'s artist and its genres when given).
Future<void> startSpotifyRadio(BuildContext context,
    {SpotifyTrackRef? seed}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('spotifyRadioBuilding'.tr)));
  final api = SpotifyApiService(auth: SpotifyAuthService());
  Future<List<T>> orEmpty<T>(Future<List<T>> f) async {
    try {
      return await f;
    } catch (_) {
      return <T>[];
    }
  }

  try {
    final top = await api.fetchTopTracks();
    final results = await Future.wait([
      orEmpty(api.fetchRecentlyPlayed()),
      orEmpty(api.fetchLikedSongs()),
    ]);
    final artists = [
      ...await orEmpty(api.fetchTopArtists()),
      ...await orEmpty(api.fetchFollowedArtists()),
    ];
    final radio = buildSpotifyRadio(
      top: top,
      recent: results[0],
      liked: results[1],
      seed: seed,
      genresByArtist: {
        for (final a in artists) a.name.toLowerCase(): a.genres.toSet()
      },
    );
    if (!context.mounted) return;
    if (radio.isEmpty) {
      messenger?.showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('spotifyRadioEmpty'.tr)));
      return;
    }
    await playSpotifyTracks(context, radio,
        from: seed == null
            ? 'spotifyRadio'.tr
            : 'spotifyRadioOf'.trParams({'name': seed.title}));
  } catch (e) {
    messenger?.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(spotifyErrorText(e))));
  }
}
