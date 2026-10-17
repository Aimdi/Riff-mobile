import 'package:audio_session/audio_session.dart';

/// Headphones coming back after their going paused playback, as AntennaPod's
/// Bluetooth reconnect and Headphones reconnect: Bluetooth ones (Settings ›
/// Resume on Bluetooth) or wired and USB ones (Resume on headphones), each
/// noticed as it appears among the outputs.
///
/// Only a pause the unplugging made counts, and only until playback starts
/// some other way: played on through the speaker meanwhile, or paused and
/// played again, plugging them back in later starts nothing.
class HeadphonesBack {
  bool _hadBluetooth = false;
  bool _hadWired = false;
  bool _pausedByUnplug = false;

  static const _bluetooth = {
    AudioDeviceType.bluetoothA2dp,
    AudioDeviceType.bluetoothSco,
    AudioDeviceType.bluetoothLe,
  };

  static const _wired = {
    AudioDeviceType.wiredHeadset,
    AudioDeviceType.wiredHeadphones,
    // USB-C headphones and dongles.
    AudioDeviceType.usbAudio,
  };

  static bool isBluetoothOutput(AudioDevice d) =>
      d.isOutput && _bluetooth.contains(d.type);

  static bool isWiredOutput(AudioDevice d) =>
      d.isOutput && _wired.contains(d.type);

  /// What's connected at the start (nothing to come back yet).
  void seed(Iterable<AudioDevice> devices) {
    _hadBluetooth = devices.any(isBluetoothOutput);
    _hadWired = devices.any(isWiredOutput);
  }

  /// The unplugging (Android's "becoming noisy") just paused playback.
  void pausedByUnplug() => _pausedByUnplug = true;

  /// Playback started or stopped; started, there's nothing to resume.
  void playing(bool playing) {
    if (playing) _pausedByUnplug = false;
  }

  /// The outputs changed to [devices]: whether to play again, Bluetooth
  /// headphones being back with [bluetooth] on, or wired ones with [wired].
  bool resumeNow(Iterable<AudioDevice> devices,
      {required bool bluetooth, required bool wired}) {
    final hasBluetooth = devices.any(isBluetoothOutput);
    final hasWired = devices.any(isWiredOutput);
    final back = (bluetooth && hasBluetooth && !_hadBluetooth) ||
        (wired && hasWired && !_hadWired);
    _hadBluetooth = hasBluetooth;
    _hadWired = hasWired;
    if (!back || !_pausedByUnplug) return false;
    _pausedByUnplug = false;
    return true;
  }
}
