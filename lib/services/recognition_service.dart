import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide FormData, MultipartFile, Response;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '/ui/screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';

enum RecogStatus { success, noMatch, noToken, noPermission, error }

class RecogResult {
  RecogResult(this.status, {this.title, this.artist});
  final RecogStatus status;
  final String? title;
  final String? artist;

  String get label => [title, artist]
      .whereType<String>()
      .where((e) => e.isNotEmpty)
      .join(' – ');
}

/// Shazam/Audire-style song recognition: record a few seconds of microphone
/// audio and identify it via the audD API (audd.io). audD needs an API token
/// (set in Settings) — there is no robust key-free song-recognition service,
/// which is why Audire uses audD too. The recorded clip is sent to audD and
/// then deleted; nothing is stored.
class RecognitionService {
  RecognitionService._();

  static final AudioRecorder _recorder = AudioRecorder();
  static bool _busy = false;

  static bool get isBusy => _busy;

  static Future<RecogResult> identify() async {
    if (_busy) return RecogResult(RecogStatus.error);
    final token =
        Get.find<SettingsScreenController>().auddApiToken.value.trim();
    if (token.isEmpty) return RecogResult(RecogStatus.noToken);
    if (!await _recorder.hasPermission()) {
      return RecogResult(RecogStatus.noPermission);
    }
    _busy = true;
    String? recordedPath;
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/riff_recognize.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      await Future.delayed(const Duration(seconds: 7));
      recordedPath = await _recorder.stop() ?? path;

      final form = FormData.fromMap({
        'api_token': token,
        'return': 'apple_music,spotify',
        'file': await MultipartFile.fromFile(recordedPath, filename: 'clip.m4a'),
      });
      final res = await Dio().post(
        'https://api.audd.io/',
        data: form,
        options: Options(receiveTimeout: const Duration(seconds: 25)),
      );
      final data = res.data is String ? jsonDecode(res.data) : res.data;
      final result = (data is Map) ? data['result'] : null;
      if (result == null) return RecogResult(RecogStatus.noMatch);
      return RecogResult(
        RecogStatus.success,
        title: result['title']?.toString(),
        artist: result['artist']?.toString(),
      );
    } catch (e) {
      printERROR('Recognition failed: $e');
      try {
        await _recorder.stop();
      } catch (_) {}
      return RecogResult(RecogStatus.error);
    } finally {
      _busy = false;
      // Best-effort cleanup of the temporary clip.
      if (recordedPath != null) {
        try {
          await _recorder.cancel();
        } catch (_) {}
      }
    }
  }
}
