import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/music_service.dart';
import '/services/recognition_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import 'snackbar.dart';

/// Audire/Shazam-style "identify the song playing around you" button. Tap to
/// listen; long-press to set/edit the audD API token.
class RecognitionButton extends StatelessWidget {
  const RecognitionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      width: 60,
      child: FittedBox(
        child: FloatingActionButton(
          heroTag: 'recognizeFab',
          focusElevation: 0,
          elevation: 0,
          tooltip: 'identifySong'.tr,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14))),
          onPressed: () => runSongRecognition(context),
          child: const Icon(Icons.graphic_eq),
        ),
      ),
    );
  }
}

/// Runs the full recognition flow: listen → audD → find on YouTube Music → play.
Future<void> runSongRecognition(BuildContext context) async {
  final settings = Get.find<SettingsScreenController>();
  if (settings.auddApiToken.value.trim().isEmpty) {
    showAuddTokenDialog(context);
    return;
  }
  if (RecognitionService.isBusy) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ListeningDialog(),
  );

  final result = await RecognitionService.identify();

  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop(); // dismiss listening dialog
  }
  if (!context.mounted) return;

  switch (result.status) {
    case RecogStatus.success:
      await _findAndPlay(context, result);
      break;
    case RecogStatus.noMatch:
      _snack(context, 'couldNotIdentify'.tr);
      break;
    case RecogStatus.noPermission:
      _snack(context, 'micPermissionNeeded'.tr);
      break;
    case RecogStatus.noToken:
      showAuddTokenDialog(context);
      break;
    case RecogStatus.error:
      _snack(context, 'recognitionFailed'.tr);
      break;
  }
}

Future<void> _findAndPlay(BuildContext context, RecogResult r) async {
  try {
    final res =
        await Get.find<MusicServices>().search(r.label, filter: 'songs', limit: 1);
    MediaItem? song;
    for (final value in res.values) {
      if (value is List) {
        for (final item in value) {
          if (item is MediaItem) {
            song = item;
            break;
          }
        }
      }
      if (song != null) break;
    }
    if (!context.mounted) return;
    if (song != null) {
      Get.find<PlayerController>().pushSongToQueue(song);
      _snack(context, '${'nowPlaying'.tr}: ${r.label}');
    } else {
      _snack(context, '${'identified'.tr}: ${r.label}');
    }
  } catch (_) {
    if (context.mounted) _snack(context, '${'identified'.tr}: ${r.label}');
  }
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
      .showSnackBar(snackbar(context, msg, size: SanckBarSize.MEDIUM));
}

void showAuddTokenDialog(BuildContext context) {
  final settings = Get.find<SettingsScreenController>();
  final ctrl = TextEditingController(text: settings.auddApiToken.value);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('identifySong'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('auddTokenHint'.tr,
              style: Theme.of(ctx).textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            decoration: InputDecoration(
              labelText: 'auddToken'.tr,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('cancel'.tr),
        ),
        TextButton(
          onPressed: () {
            final token = ctrl.text.trim();
            settings.setBox.put('auddApiToken', token);
            settings.auddApiToken.value = token;
            Navigator.of(ctx).pop();
          },
          child: Text('save'.tr),
        ),
      ],
    ),
  );
}

/// A small "listening" dialog with a pulsing waveform icon.
class _ListeningDialog extends StatefulWidget {
  const _ListeningDialog();

  @override
  State<_ListeningDialog> createState() => _ListeningDialogState();
}

class _ListeningDialogState extends State<_ListeningDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.15).animate(
                CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
            child: Icon(Icons.graphic_eq, size: 64, color: accent),
          ),
          const SizedBox(height: 20),
          Text('listening'.tr, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
