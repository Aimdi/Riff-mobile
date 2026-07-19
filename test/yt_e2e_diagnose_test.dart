// End-to-end diagnostics against the real YouTube Music API.
//
// This suite exists because the development container has no YouTube
// egress: CI runners do, so `flutter test test/yt_e2e_diagnose_test.dart`
// there tells us exactly which layer breaks (request vs parsing vs
// stream resolution) with a full stack trace.
//
// Note: googlevideo stream URLs are often IP-locked/403 for datacenter
// IPs, so the stream HEAD check can fail on CI while working fine on a
// phone - the manifest fetch result is what matters here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:harmonymusic/services/kugou_lyrics_service.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/stream_service.dart';

Future<MusicServices> _makeService() async {
  final ms = MusicServices();
  await ms.init();
  return ms;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The test binding stubs HttpClient to always return 400; reset the
    // override so these diagnostics hit the real network.
    HttpOverrides.global = null;
    Hive.init(Directory.systemTemp.createTempSync('riffhive').path);
    await Hive.openBox('AppPrefs');
    await Hive.openBox('BannedSongs');
    await Hive.openBox('BannedArtists');
  });

  test('home feed loads and parses', () async {
    final ms = await _makeService();
    final home = await ms.getHome(limit: 4);
    // ignore: avoid_print
    print('HOME OK: ${home.length} sections');
    for (final s in home) {
      // ignore: avoid_print
      print('  - ${s["title"]}: ${(s["contents"] as List).length} items');
    }
    expect(home, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('charts load and parse', () async {
    final ms = await _makeService();
    final charts = await ms.getCharts("TR");
    // ignore: avoid_print
    print('CHARTS OK: ${charts.length} sections');
    expect(charts, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('search works', () async {
    final ms = await _makeService();
    final res = await ms.search("never gonna give you up", filter: "songs");
    // ignore: avoid_print
    print('SEARCH keys: ${res.keys.toList()}');
    final lists = res.values.whereType<List>().toList();
    final total = lists.fold<int>(0, (s, l) => s + l.length);
    // ignore: avoid_print
    print('SEARCH OK: $total results across ${lists.length} sections');
    expect(total, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('watch playlist (radio/up-next) works', () async {
    final ms = await _makeService();
    // dQw4w9WgXcQ - stable, well-known video id
    final wp = await ms.getWatchPlaylist(videoId: "dQw4w9WgXcQ", limit: 10);
    final tracks = wp['tracks'] as List;
    // ignore: avoid_print
    print('WATCH PLAYLIST OK: ${tracks.length} tracks');
    expect(tracks, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('stream resolution (youtube_explode_dart 3.x fix)', () async {
    final provider = await StreamProvider.fetch("dQw4w9WgXcQ");
    // ignore: avoid_print
    print('STREAM: playable=${provider.playable} msg=${provider.statusMSG} '
        'formats=${provider.audioFormats?.map((a) => a.itag).toList()}');
    // Do not hard-fail on !playable: datacenter IPs may be blocked from
    // googlevideo endpoints while phones are fine. The printout is the
    // diagnostic signal.
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('KuGou lyrics fallback resolves', () async {
    final lrc = await KuGouLyricsService.getSyncedLyrics(
        "Rick Astley", "Never Gonna Give You Up", 213);
    // ignore: avoid_print
    print('KUGOU LYRICS: ${lrc == null ? "none" : "${lrc.length} chars, "
        "synced=${lrc.contains("[")}"}');
    // Non-fatal: KuGou may rate-limit datacenter IPs; the print is the
    // signal that the provider wiring works.
  }, timeout: const Timeout(Duration(minutes: 3)));
}
