import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/spotify_connect.dart';
import '/services/spotify_connect_models.dart';
import '/services/spotify_import_service.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '../Home/home_layout.dart';
import 'spotify_widgets.dart';

IconData spotifyDeviceIcon(String type) => switch (type.toLowerCase()) {
      'smartphone' => Icons.smartphone_rounded,
      'computer' => Icons.computer_rounded,
      'tablet' => Icons.tablet_rounded,
      'tv' => Icons.tv_rounded,
      'automobile' => Icons.directions_car_rounded,
      _ => Icons.speaker_rounded,
    };

void _snack(BuildContext context, String text, {SnackBarAction? action}) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(text),
        action: action));

/// Open the Spotify app on this phone (so it shows up as a device).
Future<void> openSpotifyApp() =>
    launchUrl(Uri.parse('spotify:'), mode: LaunchMode.externalApplication);

/// Pick a device to play on.
Future<SpotifyDevice?> pickSpotifyDevice(
    BuildContext context, List<SpotifyDevice> devices) {
  return showModalBottomSheet<SpotifyDevice>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => SafeArea(
      // Sheet rows per RIFF_UI_RESTYLE.md §5.10.
      child: ListTileTheme.merge(
        titleTextStyle: Theme.of(ctx).textTheme.bodyLarge,
        iconColor: Theme.of(ctx).colorScheme.onSurface,
        child: IconTheme.merge(
          data: const IconThemeData(size: RiffComponentSizes.headerIcon),
          child: Wrap(children: [
            ListTile(
                title: Text('spotifyPickDevice'.tr,
                    style: Theme.of(ctx).textTheme.titleLarge)),
            for (final d in devices)
              ListTile(
                enabled: !d.isRestricted,
                leading: Icon(spotifyDeviceIcon(d.type)),
                title: Text(d.name),
                subtitle: d.isActive ? Text('spotifyDeviceActive'.tr) : null,
                trailing: d.id == SpotifyConnect.preferredDeviceId
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(ctx).pop(d),
              ),
          ]),
        ),
      ),
    ),
  );
}

/// Play [tracks] (or a playlist/album, [contextUri]) from [start] on one of
/// the user's Spotify devices. Uses the device picked last time when it's
/// there; otherwise asks.
Future<void> playOnSpotifyDevice(BuildContext context,
    {List<SpotifyTrackRef> tracks = const [],
    String? contextUri,
    int start = 0,
    bool choose = false}) async {
  if (!SpotifyConnect.enabled || !SpotifyConnect.hasAccess) {
    _snack(context, 'spotifyConnectOff'.tr);
    return;
  }
  try {
    final devices = await SpotifyConnect.api.fetchDevices();
    if (!context.mounted) return;
    if (devices.where((d) => !d.isRestricted).isEmpty) {
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('spotifyNoDevices'.tr),
          content: Text('spotifyNoDevicesDes'.tr),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('cancel'.tr)),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('spotifyOpenApp'.tr)),
          ],
        ),
      );
      if (open == true) await openSpotifyApp();
      return;
    }
    final preferred = choose
        ? null
        : devices.firstWhereOrNull(
            (d) => d.id == SpotifyConnect.preferredDeviceId && !d.isRestricted);
    final device = preferred ?? await pickSpotifyDevice(context, devices);
    if (device == null || !context.mounted) return;
    await SpotifyConnect.playTracks(device.id,
        tracks: tracks, contextUri: contextUri, start: start);
    if (!context.mounted) return;
    _snack(
      context,
      'spotifyPlayingOn'.trParams({'name': device.name}),
      action: SnackBarAction(
        label: 'spotifyChangeDevice'.tr,
        onPressed: () => playOnSpotifyDevice(context,
            tracks: tracks, contextUri: contextUri, start: start, choose: true),
      ),
    );
  } catch (e) {
    if (context.mounted) _snack(context, spotifyErrorText(e));
  }
}

/// Remote for what Spotify plays: now playing, controls, volume, devices.
class SpotifyConnectPanel extends StatefulWidget {
  const SpotifyConnectPanel({super.key});

  @override
  State<SpotifyConnectPanel> createState() => _SpotifyConnectPanelState();
}

class _SpotifyConnectPanelState extends State<SpotifyConnectPanel> {
  double? _dragVolume;

  @override
  void initState() {
    super.initState();
    SpotifyConnect.watch();
  }

  @override
  void dispose() {
    SpotifyConnect.unwatch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = SpotifyConnect.api;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiffPageHeader('spotifyConnect'.tr, actions: [
            IconButton(
              tooltip: 'spotifyOpenApp'.tr,
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: openSpotifyApp,
            ),
          ]),
          Expanded(
            child: Obx(() {
              final s = SpotifyConnect.state.value;
              final err = SpotifyConnect.lastError.value;
              final devices = SpotifyConnect.devices.toList();
              final t = s?.track;
              final dur = t?.durationMs ?? 0;
              return RefreshIndicator(
                onRefresh: SpotifyConnect.refresh,
                child: ListView(
                  padding: const EdgeInsets.only(
                      left: HomeLayout.gutter,
                      top: RiffSpacing.sm,
                      right: HomeLayout.gutter,
                      bottom: RiffSpacing.listEnd),
                  children: [
                    if (err != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(spotifyErrorText(err),
                            style: TextStyle(color: theme.colorScheme.error)),
                      ),
                    if (t == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('spotifyNothingPlaying'.tr,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(color: homeMutedColor(context))),
                      )
                    else ...[
                      Center(child: SpotifyArt(url: t.artUrl, size: 220)),
                      const SizedBox(height: 16),
                      Text(t.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(t.artists,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: homeMutedColor(context))),
                      if (dur > 0)
                        Slider(
                          value: (s!.progressMs / dur).clamp(0.0, 1.0),
                          onChanged: (_) {},
                          onChangeEnd: (v) => SpotifyConnect.command((id) =>
                              api.seek((v * dur).round(), deviceId: id)),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            iconSize: 36,
                            tooltip: 'previous'.tr,
                            icon: const Icon(Icons.skip_previous_rounded),
                            onPressed: () => SpotifyConnect.command(
                                (id) => api.previous(deviceId: id)),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filled(
                            iconSize: 44,
                            icon: Icon(s!.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded),
                            onPressed: () => SpotifyConnect.command((id) =>
                                s.isPlaying
                                    ? api.pause(deviceId: id)
                                    : api.play(deviceId: id)),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            iconSize: 36,
                            tooltip: 'next'.tr,
                            icon: const Icon(Icons.skip_next_rounded),
                            onPressed: () => SpotifyConnect.command(
                                (id) => api.next(deviceId: id)),
                          ),
                        ],
                      ),
                      if (s.device?.volumePercent != null)
                        Row(children: [
                          const Icon(Icons.volume_down_rounded),
                          Expanded(
                            child: Slider(
                              value: _dragVolume ??
                                  s.device!.volumePercent!.toDouble(),
                              max: 100,
                              onChanged: (v) => setState(() => _dragVolume = v),
                              onChangeEnd: (v) async {
                                await SpotifyConnect.command((id) =>
                                    api.setVolume(v.round(), deviceId: id));
                                if (mounted) {
                                  setState(() => _dragVolume = null);
                                }
                              },
                            ),
                          ),
                          const Icon(Icons.volume_up_rounded),
                        ]),
                    ],
                    const SizedBox(height: 16),
                    Text('spotifyDevices'.tr,
                        style: homeSectionTitleStyle(context)),
                    if (devices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('spotifyNoDevicesDes'.tr,
                            style: homeCardSubtitleStyle(context)),
                      ),
                    for (final d in devices)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        enabled: !d.isRestricted,
                        leading: Icon(spotifyDeviceIcon(d.type),
                            color: d.isActive
                                ? theme.colorScheme.secondary
                                : null),
                        title: Text(d.name),
                        subtitle:
                            d.isActive ? Text('spotifyDeviceActive'.tr) : null,
                        onTap: d.isActive
                            ? null
                            : () async {
                                await SpotifyConnect.rememberDevice(d.id);
                                await SpotifyConnect.command(
                                    (_) => api.transferPlayback(d.id));
                              },
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
