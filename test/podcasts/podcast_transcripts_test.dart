import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/services/podcast_transcripts.dart';
import 'package:hive/hive.dart';

PodcastTranscriptCue cue(double s, String t, {double? e, String? p}) =>
    PodcastTranscriptCue(startSec: s, endSec: e, speaker: p, text: t);

MediaItem ep(String id, {Map<String, dynamic> extras = const {}}) =>
    MediaItem(id: id, title: 'Ep', artist: 'Show', extras: {
      'isPodcast': true,
      ...extras,
    });

void main() {
  group('parsing', () {
    test('application/srt is read as SubRip', () {
      const srt = '1\n00:00:01,000 --> 00:00:02,500\nHello there.\n\n'
          '2\n00:00:03,000 --> 00:00:04,000\nGeneral Kenobi.\n';
      final out = PodcastService.parseTranscriptDocument(srt,
          type: 'application/srt');
      expect(out.map((c) => c.text), ['Hello there.', 'General Kenobi.']);
      expect(out.first.endSec, 2.5);
    });

    test('a fetched transcript is parsed off the UI isolate, same result',
        () async {
      const srt = '1\n00:00:01,000 --> 00:00:02,000\nAlex: Hello there.\n\n'
          '2\n00:00:03,000 --> 00:00:04,500\nSam: Hi!\n';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) => req.response
        ..write(srt)
        ..close());
      final cues = await PodcastService.transcript(
          'http://127.0.0.1:${server.port}/t.srt',
          type: 'application/srt');
      final direct =
          PodcastService.parseTranscriptDocument(srt, type: 'application/srt');
      expect(cues.map((c) => c.toJson()), direct.map((c) => c.toJson()));
      expect(cues.map((c) => c.speaker), ['Alex', 'Sam']);
    });

    test('tiny cues merge into sentence-length lines', () {
      const vtt = 'WEBVTT\n\n'
          '00:00.000 --> 00:01.000\nSo today we\n\n'
          '00:01.000 --> 00:02.000\nare talking about\n\n'
          '00:02.000 --> 00:03.000\ntranscripts.\n\n'
          '00:03.200 --> 00:04.000\nNext line.\n';
      final out =
          PodcastService.parseTranscriptDocument(vtt, type: 'text/vtt');
      expect(out.map((c) => c.text),
          ['So today we are talking about transcripts.', 'Next line.']);
      expect(out.first.startSec, 0);
      expect(out.first.endSec, 3);
    });

    test('YouTube auto captions: rolling repeats are removed', () {
      const vtt = 'WEBVTT\nKind: captions\nLanguage: en\n\n'
          '00:00:00.000 --> 00:00:02.310 align:start position:0%\n'
          'hello<00:00:00.320><c> everyone</c>\n\n'
          '00:00:02.310 --> 00:00:02.320 align:start position:0%\n'
          'hello everyone\n\n'
          '00:00:02.320 --> 00:00:05.000 align:start position:0%\n'
          'hello everyone\nand<00:00:02.500><c> welcome</c>\n\n'
          '00:00:05.000 --> 00:00:07.000 align:start position:0%\n'
          'and welcome\nto the show\n';
      final rolled = PodcastService.parseTranscriptDocument(vtt,
          type: 'text/vtt', rolling: true);
      expect(rolled.map((c) => c.text).join(' '),
          'hello everyone and welcome to the show');
      // Without the flag (human-made tracks) the text is left alone.
      final plain =
          PodcastService.parseTranscriptDocument(vtt, type: 'text/vtt');
      expect(plain.map((c) => c.text).join(' '), contains('hello everyone hello'));
    });

    test('dedupe keeps a cue with no overlap whole', () {
      final out = PodcastService.dedupeRollingCaptions([
        cue(0, 'one two', e: 1),
        cue(1, 'three four', e: 2),
      ]);
      expect(out.map((c) => c.text), ['one two', 'three four']);
    });

    test('cue json round trip; junk is null', () {
      final c = cue(1.5, 'Hi', e: 2, p: 'Ana');
      final back = PodcastTranscriptCue.fromJson(c.toJson())!;
      expect(back.startSec, 1.5);
      expect(back.endSec, 2);
      expect(back.speaker, 'Ana');
      expect(back.text, 'Hi');
      expect(PodcastTranscriptCue.fromJson({'s': 1}), isNull);
      expect(PodcastTranscriptCue.fromJson('x'), isNull);
      expect(cue(-1, 'x').timed, isFalse);
    });
  });

  group('source', () {
    test('feed transcript wins over YouTube', () {
      final src = transcriptSourceFor(ep('dQw4w9WgXcQ', extras: {
        'transcriptUrl': 'https://x/t.vtt',
        'transcriptType': 'text/vtt',
      }))!;
      expect(src.isYoutube, isFalse);
      expect(src.key, 'https://x/t.vtt');
      expect(src.type, 'text/vtt');
    });

    test('YouTube episode without a feed transcript uses captions', () {
      final src = transcriptSourceFor(ep('dQw4w9WgXcQ'))!;
      expect(src.isYoutube, isTrue);
      expect(src.key, 'yt:dQw4w9WgXcQ');
    });

    test('no source: RSS without transcript, music, null', () {
      expect(transcriptSourceFor(ep('podcast_123')), isNull);
      expect(
          transcriptSourceFor(
              const MediaItem(id: 'dQw4w9WgXcQ', title: 'A song')),
          isNull);
      expect(transcriptSourceFor(null), isNull);
    });

    test('caption track choice', () {
      expect(pickCaptionTrack(const [], 'en'), -1);
      final tracks = [
        (lang: 'de', auto: true),
        (lang: 'en', auto: true),
        (lang: 'en-GB', auto: false),
        (lang: 'fr', auto: false),
      ];
      expect(pickCaptionTrack(tracks, 'en_US'), 2);
      expect(pickCaptionTrack(tracks, 'de'), 0);
      expect(pickCaptionTrack(tracks, 'ja'), 2);
      expect(pickCaptionTrack([(lang: 'ko', auto: true)], 'en'), 0);
    });
  });

  group('search', () {
    final cues = [
      cue(0, 'The cat sat.'),
      cue(5, 'A dog barked.', p: 'Cathy'),
      cue(9, 'Concatenate CAT cat'),
    ];

    test('matches lines, case-insensitive, speakers too', () {
      expect(transcriptMatches(cues, 'cat'), [0, 1, 2]);
      expect(transcriptMatches(cues, 'dog'), [1]);
      expect(transcriptMatches(cues, '  '), isEmpty);
    });

    test('ranges inside a line', () {
      expect(matchRanges('Concatenate CAT cat', 'cat'),
          [(3, 6), (12, 15), (16, 19)]);
      expect(matchRanges('abc', ''), isEmpty);
    });

    test('next / previous wrap; start near the active line', () {
      expect(stepMatch(-1, 3, forward: true), 0);
      expect(stepMatch(-1, 3, forward: false), 2);
      expect(stepMatch(2, 3, forward: true), 0);
      expect(stepMatch(0, 3, forward: false), 2);
      expect(stepMatch(0, 0, forward: true), -1);
      expect(firstMatchFrom([2, 8, 15], 9), 2);
      expect(firstMatchFrom([2, 8, 15], 20), 0);
      expect(firstMatchFrom(const [], 3), -1);
    });
  });

  group('cache', () {
    test('usable only with lines', () {
      expect(transcriptCacheUsable({'cues': [{'s': 0, 't': 'x'}]}), isTrue);
      expect(transcriptCacheUsable({'cues': []}), isFalse);
      expect(transcriptCacheUsable('junk'), isFalse);
      expect(transcriptCacheUsable(null), isFalse);
    });

    test('evicts the oldest beyond the cap', () {
      expect(transcriptKeysToEvict({'a': 3, 'b': 1, 'c': 2}, 2), ['b']);
      expect(transcriptKeysToEvict({'a': 1}, 2), isEmpty);
    });

    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_transcripts_');
      Hive.init(tmp.path);
      await Hive.openBox(PodcastTranscriptService.box);
      PodcastTranscriptService.clearMemory();
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('load reads a stored transcript without the network', () async {
      await Hive.box(PodcastTranscriptService.box).put('yt:dQw4w9WgXcQ', {
        'at': 1,
        'yt': true,
        'auto': true,
        'cues': [
          cue(0, 'First').toJson(),
          {'bad': 1},
          cue(2, 'Second').toJson(),
        ],
      });
      final t = await PodcastTranscriptService.load(ep('dQw4w9WgXcQ'));
      expect(t.cues.map((c) => c.text), ['First', 'Second']);
      expect(t.youtube, isTrue);
      expect(t.auto, isTrue);
      expect(t.timed, isTrue);
    });

    test('only the most recent transcripts stay parsed in memory', () async {
      final box = Hive.box(PodcastTranscriptService.box);
      for (var i = 0; i < 10; i++) {
        await box.put('https://x/$i.json', {
          'at': i,
          'cues': [cue(0, 'Line $i').toJson()],
        });
      }
      MediaItem feedEp(int i) =>
          ep('podcast_$i', extras: {'transcriptUrl': 'https://x/$i.json'});
      for (var i = 0; i < 10; i++) {
        await PodcastTranscriptService.load(feedEp(i));
      }
      // Every transcript used to stay in memory for the whole session.
      expect(PodcastTranscriptService.memoryCount, lessThanOrEqualTo(4));
      // An evicted one comes back from the box.
      final first = await PodcastTranscriptService.load(feedEp(0));
      expect(first.cues.single.text, 'Line 0');
    });

    test('availability: feed sync, YouTube after a probe/cache', () async {
      expect(
          PodcastTranscriptService.available(
              ep('podcast_1', extras: {'transcriptUrl': 'https://x/t.json'})),
          isTrue);
      expect(PodcastTranscriptService.available(ep('podcast_1')), isFalse);
      expect(PodcastTranscriptService.available(ep('dQw4w9WgXcQ')), isFalse);
      await Hive.box(PodcastTranscriptService.box).put('yt:dQw4w9WgXcQ', {
        'cues': [cue(0, 'x').toJson()]
      });
      await PodcastTranscriptService.probe(ep('dQw4w9WgXcQ'));
      expect(PodcastTranscriptService.available(ep('dQw4w9WgXcQ')), isTrue);
    });
  });
}
