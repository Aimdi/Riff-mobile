@Tags(['live'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/song_recognition/shazam_client.dart';
import 'package:harmonymusic/services/song_recognition/shazam_signature.dart';

/// Real Shazam round trip: 10 s of a well-known Kevin MacLeod track
/// (incompetech, CC BY), decoded to 16 kHz mono with ffmpeg, signed by
/// the Dart port, sent to Shazam. Needs network and ffmpeg (CI has both).
void main() {
  test('Shazam names a real recording from the Dart signature', () async {
    final ffmpeg = await Process.run('which', ['ffmpeg']);
    if (ffmpeg.exitCode != 0) {
      markTestSkipped('ffmpeg not installed');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('shazam');
    final mp3 = File('${dir.path}/song.mp3');
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(
        'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Monkeys%20Spinning%20Monkeys.mp3'));
    final res = await req.close();
    expect(res.statusCode, 200);
    await res.pipe(mp3.openWrite());
    final pcm = await Process.run(
        'ffmpeg',
        [
          '-v',
          'error',
          '-ss',
          '30',
          '-t',
          '10',
          '-i',
          mp3.path,
          '-ac',
          '1',
          '-ar',
          '16000',
          '-f',
          's16le',
          '-'
        ],
        stdoutEncoding: null);
    expect(pcm.exitCode, 0, reason: '${pcm.stderr}');
    final bytes = Uint8List.fromList(pcm.stdout as List<int>);
    final samples = Int16List.view(bytes.buffer, 0, bytes.length ~/ 2);
    final uri = ShazamSignature.fromPcm16(samples);
    final song = await ShazamClient().identify(uri, 10000);
    // ignore: avoid_print
    print('Shazam: ${song?.title} — ${song?.artist} (${song?.album})');
    expect(song, isNotNull);
    expect(song!.title.toLowerCase(), contains('monkeys'));
    await dir.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
