import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/cover_resolver.dart';
import 'package:harmonymusic/services/music_service.dart';

/// Answers square-cover lookups from [answers]; each lookup waits for
/// [release] so tests can overlap calls.
class _FakeMusic extends MusicServices {
  final calls = <String>[];
  Completer<void> release = Completer<void>()..complete();

  @override
  Future<void> init() async {} // no Hive / network in tests

  @override
  Future<String?> squareCoverForVideo(String videoId,
      {String? title, String? artist}) async {
    calls.add(videoId);
    await release.future;
    return 'https://lh3.googleusercontent.com/$videoId=w544-h544';
  }
}

void main() {
  late _FakeMusic music;

  setUp(() {
    CoverResolver.resetForTest();
    music = Get.put<MusicServices>(_FakeMusic()) as _FakeMusic;
  });

  tearDown(() {
    Get.reset();
    CoverResolver.resetForTest();
  });

  test('a second request for the same song joins the lookup', () async {
    music.release = Completer<void>();
    final first = CoverResolver.resolve('v1', title: 'T', artist: 'A');
    final second = CoverResolver.resolve('v1', title: 'T', artist: 'A');
    music.release.complete();
    final urls = await Future.wait([first, second]);
    // The joiner used to get null and keep showing the video frame.
    expect(urls[0], isNotNull);
    expect(urls[1], urls[0]);
    expect(music.calls, ['v1']);
    expect(CoverResolver.cached('v1'), urls[0]);
  });

  test('the memory cache stays bounded', () async {
    for (var i = 0; i < CoverResolver.memoryCap + 25; i++) {
      await CoverResolver.resolve('id$i', title: 't$i');
    }
    expect(CoverResolver.memoryEntries, CoverResolver.memoryCap);
    // Recent entries stay in memory; the oldest went (no Hive box open).
    expect(
        CoverResolver.cached('id${CoverResolver.memoryCap + 24}'), isNotNull);
    expect(CoverResolver.cached('id0'), isNull);
  });
}
