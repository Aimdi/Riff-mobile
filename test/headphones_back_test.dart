import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/headphones_back.dart';

AudioDevice _device(AudioDeviceType type,
        {bool output = true, String id = '1'}) =>
    AudioDevice(
        id: id, name: '$type', isInput: !output, isOutput: output, type: type);

final _speaker = _device(AudioDeviceType.builtInSpeaker, id: 'speaker');
final _bluetooth = _device(AudioDeviceType.bluetoothA2dp, id: 'bt');
final _wired = _device(AudioDeviceType.wiredHeadphones, id: 'jack');
final _usb = _device(AudioDeviceType.usbAudio, id: 'usb');

/// Headphones coming back after their going paused playback (AntennaPod's
/// Bluetooth reconnect and Headphones reconnect).
void main() {
  late HeadphonesBack back;

  setUp(() {
    back = HeadphonesBack()..seed([_speaker, _bluetooth]);
  });

  bool resume(List<AudioDevice> devices,
          {bool bluetooth = true, bool wired = true}) =>
      back.resumeNow(devices, bluetooth: bluetooth, wired: wired);

  test('Bluetooth headphones gone, then back: playback goes on', () {
    back.pausedByUnplug();
    expect(resume([_speaker]), isFalse);
    expect(resume([_speaker, _bluetooth]), isTrue);
    // Once: going and coming again starts nothing more.
    expect(resume([_speaker]), isFalse);
    expect(resume([_speaker, _bluetooth]), isFalse);
  });

  test('wired and USB headphones too, with Resume on headphones', () {
    back.seed([_speaker, _wired]);
    back.pausedByUnplug();
    expect(resume([_speaker]), isFalse);
    expect(resume([_speaker, _wired]), isTrue);

    back.pausedByUnplug();
    expect(resume([_speaker]), isFalse);
    expect(resume([_speaker, _usb]), isTrue);
  });

  test('each setting off leaves its kind alone', () {
    back.pausedByUnplug();
    expect(resume([_speaker]), isFalse);
    expect(resume([_speaker, _wired], wired: false), isFalse);
    expect(resume([_speaker, _bluetooth], bluetooth: false), isFalse);
    // Still waiting for the one turned on.
    expect(resume([_speaker]), isFalse);
    expect(resume([_speaker, _bluetooth]), isTrue);
  });

  test('not paused by the unplugging: nothing to resume', () {
    expect(resume([_speaker]), isFalse);
    expect(resume([_speaker, _bluetooth]), isFalse);
  });

  test('played again meanwhile (the speaker): plugging back in starts nothing',
      () {
    back.pausedByUnplug();
    expect(resume([_speaker]), isFalse);
    back.playing(true);
    back.playing(false);
    expect(resume([_speaker, _bluetooth]), isFalse);
  });

  test('headphones still in, or only a microphone, are not a coming back', () {
    back.pausedByUnplug();
    expect(resume([_speaker, _bluetooth]), isFalse);
    expect(
        resume([
          _speaker,
          _bluetooth,
          _device(AudioDeviceType.usbAudio, output: false)
        ]),
        isFalse);
  });
}
