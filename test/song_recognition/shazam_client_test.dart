import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/song_recognition/shazam_client.dart';

void main() {
  test('UUID v5 matches RFC 4122 (python uuid5(NAMESPACE_DNS, "python.org"))',
      () {
    expect(ShazamClient.uuidV5(ShazamClient.dnsNamespace, 'python.org'),
        '886313e1-3b8a-5372-9b90-0c9aee199e5d');
  });

  test('request body carries the signature and a plausible identity', () {
    final body = ShazamClient(random: math.Random(1)).requestBody(
        'data:audio/vnd.shazam.sig;base64,AAAA', 5000,
        timestamp: 1234);
    expect(body['timestamp'], 1234);
    expect(body['signature'], {
      'samplems': 5000,
      'timestamp': 1234,
      'uri': 'data:audio/vnd.shazam.sig;base64,AAAA'
    });
    final geo = body['geolocation'] as Map;
    expect((geo['latitude'] as double).abs(), lessThanOrEqualTo(90));
    expect((geo['longitude'] as double).abs(), lessThanOrEqualTo(180));
    expect(body['timezone'], startsWith('Europe/'));
  });

  test('reads a Shazam match', () {
    final song = RecognizedSong.fromShazamResponse({
      'matches': [{}],
      'track': {
        'title': 'Monkeys Spinning Monkeys',
        'subtitle': 'Kevin MacLeod',
        'url': 'https://www.shazam.com/track/1',
        'images': {'coverart': 'c.jpg', 'coverarthq': 'hq.jpg'},
        'sections': [
          {
            'type': 'SONG',
            'metadata': [
              {'title': 'Album', 'text': 'Comedy'},
              {'title': 'Label', 'text': 'incompetech'},
              {'title': 'Released', 'text': '2014'},
            ]
          },
          {
            'type': 'LYRICS',
            'text': ['la', 'la']
          },
        ],
      },
    })!;
    expect(song.title, 'Monkeys Spinning Monkeys');
    expect(song.artist, 'Kevin MacLeod');
    expect(song.coverUrl, 'hq.jpg');
    expect(song.album, 'Comedy');
    expect(song.label, 'incompetech');
    expect(song.released, '2014');
    expect(song.lyrics, 'la\nla');
    expect(song.query, 'Monkeys Spinning Monkeys Kevin MacLeod');
  });

  test('no track means no match', () {
    expect(RecognizedSong.fromShazamResponse({'matches': []}), isNull);
    expect(RecognizedSong.fromShazamResponse('nope'), isNull);
  });

  test('history entries round-trip', () {
    final at = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final s = RecognizedSong(
        title: 'T', artist: 'A', album: 'B', coverUrl: 'c', recognizedAt: at);
    final back = RecognizedSong.fromJson(s.toJson())!;
    expect(back.title, 'T');
    expect(back.album, 'B');
    expect(back.recognizedAt, at);
    expect(RecognizedSong.fromJson({'title': 1}), isNull);
  });
}
