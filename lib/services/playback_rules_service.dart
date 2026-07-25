import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/ui/player/player_controller.dart';
import '/utils/helper.dart';

/// Pause-on-mute / resume-on-Bluetooth style playback rules (Echo-inspired).
class PlaybackRulesService extends GetxService {
  StreamSubscription<void>? _noisySub;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesSub;
  bool _pausedByNoisy = false;
  bool _hadBtOutput = false;

  Future<PlaybackRulesService> init() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _noisySub = session.becomingNoisyEventStream.listen((_) {
        if (!_enabled('pauseOnHeadsetDisconnect')) return;
        if (!Get.isRegistered<PlayerController>()) return;
        final p = Get.find<PlayerController>();
        if (p.buttonState.value == PlayButtonState.playing) {
          _pausedByNoisy = true;
          p.pause();
          printINFO('PlaybackRules: paused (becoming noisy)');
        }
      });
      _devicesSub = session.devicesChangedEventStream.listen((event) {
        _onDevicesChanged(session);
      });
      // Seed BT state.
      final devices = await session.getDevices();
      _hadBtOutput = devices.any(_isBtOutput);
    } catch (e) {
      printINFO('PlaybackRules init skipped: $e');
    }
    return this;
  }

  bool _enabled(String key) => Hive.box('AppPrefs').get(key) ?? true;

  bool _isBtOutput(AudioDevice d) {
    final t = d.type;
    // ignore: experimental_member_use
    return t == AudioDeviceType.bluetoothA2dp ||
        // ignore: experimental_member_use
        t == AudioDeviceType.bluetoothSco ||
        // ignore: experimental_member_use
        t == AudioDeviceType.bluetoothLe;
  }

  Future<void> _onDevicesChanged(AudioSession session) async {
    if (!_enabled('resumeOnBluetooth')) return;
    if (!Get.isRegistered<PlayerController>()) return;
    try {
      final devices = await session.getDevices();
      final hasBt = devices.any(_isBtOutput);
      if (hasBt && !_hadBtOutput && _pausedByNoisy) {
        final p = Get.find<PlayerController>();
        if (p.buttonState.value != PlayButtonState.playing) {
          p.play();
          printINFO('PlaybackRules: resumed on Bluetooth');
        }
        _pausedByNoisy = false;
      }
      _hadBtOutput = hasBt;
    } catch (_) {}
  }

  @override
  void onClose() {
    _noisySub?.cancel();
    _devicesSub?.cancel();
    super.onClose();
  }
}
