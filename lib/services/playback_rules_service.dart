import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/headphones_back.dart';
import '/ui/player/player_controller.dart';
import '/utils/helper.dart';

/// Pause on headset disconnect, and play again when the headphones come
/// back (Resume on Bluetooth, Resume on headphones: HeadphonesBack).
class PlaybackRulesService extends GetxService {
  StreamSubscription<void>? _noisySub;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesSub;
  StreamSubscription<bool>? _playingSub;
  final _back = HeadphonesBack();

  Future<PlaybackRulesService> init() async {
    try {
      final session = await AudioSession.instance;
      // Music, unless the player has set it up for an episode or a book
      // already (SpokenAudioFocus).
      if (!session.isConfigured) {
        await session.configure(const AudioSessionConfiguration.music());
      }
      _noisySub = session.becomingNoisyEventStream.listen((_) {
        if (!_enabled('pauseOnHeadsetDisconnect')) return;
        if (!Get.isRegistered<PlayerController>()) return;
        final p = Get.find<PlayerController>();
        if (p.buttonState.value == PlayButtonState.playing) {
          _back.pausedByUnplug();
          p.pause();
          printINFO('PlaybackRules: paused (becoming noisy)');
        }
      });
      _devicesSub = session.devicesChangedEventStream.listen((event) {
        _onDevicesChanged(session);
      });
      // Played again some other way: the headphones coming back later
      // start nothing.
      if (Get.isRegistered<AudioHandler>()) {
        _playingSub = Get.find<AudioHandler>()
            .playbackState
            .map((state) => state.playing)
            .distinct()
            .listen(_back.playing);
      }
      _back.seed(await session.getDevices());
    } catch (e) {
      printINFO('PlaybackRules init skipped: $e');
    }
    return this;
  }

  bool _enabled(String key) => Hive.box('AppPrefs').get(key) ?? true;

  Future<void> _onDevicesChanged(AudioSession session) async {
    try {
      final devices = await session.getDevices();
      final resume = _back.resumeNow(devices,
          bluetooth: _enabled('resumeOnBluetooth'),
          wired: _enabled('resumeOnHeadphones'));
      if (!resume || !Get.isRegistered<PlayerController>()) return;
      final p = Get.find<PlayerController>();
      if (p.buttonState.value != PlayButtonState.playing) {
        p.play();
        printINFO('PlaybackRules: resumed (headphones back)');
      }
    } catch (_) {}
  }

  @override
  void onClose() {
    _noisySub?.cancel();
    _devicesSub?.cancel();
    _playingSub?.cancel();
    super.onClose();
  }
}
