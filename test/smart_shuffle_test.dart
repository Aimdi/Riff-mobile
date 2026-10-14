import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/discovery/discovery_service.dart';
import 'package:harmonymusic/services/smart_shuffle.dart';

MediaItem _song(String id) => MediaItem(id: id, title: id);

class _FakeDiscovery extends GetxService implements DiscoveryService {
  final asked = <String>[];
  Map<String, List<MediaItem>> like = const {};
  Set<String> failing = const {};

  @override
  Future<List<MediaItem>> similarSongs(MediaItem seed,
      {int limit = 25, bool unheardOnly = false}) async {
    asked.add(seed.id);
    if (failing.contains(seed.id)) throw Exception('offline');
    return like[seed.id] ?? const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(Get.reset);

  test('a suggestion after every three songs, marked; never one of its own',
      () {
    final songs = [for (var i = 1; i <= 7; i++) _song('s$i')];
    final picks = [
      _song('p1'),
      _song('s2'), // already in the playlist
      _song('p1'), // twice
      _song('p2'),
      _song('p3'),
    ];
    final order = smartShuffleOrder(songs, picks, random: Random(1));
    expect(order, hasLength(9));
    expect([
      for (final m in order)
        if (isSmartShufflePick(m)) m.id
    ], [
      'p1',
      'p2'
    ]);
    expect(order.indexWhere(isSmartShufflePick), 3);
    expect(order[3].extras?['discoverySource'], 'smart_shuffle');
    final own = order.where((m) => !isSmartShufflePick(m));
    expect(own.map((m) => m.id).toSet(), {for (final s in songs) s.id});
  });

  test('no suggestions: shuffled as it is', () {
    final songs = [for (var i = 1; i <= 5; i++) _song('s$i')];
    final order = smartShuffleOrder(songs, const [], random: Random(2));
    expect(order.map((m) => m.id).toSet(), {'s1', 's2', 's3', 's4', 's5'});
    expect(order.any(isSmartShufflePick), isFalse);
  });

  test('suggestions: songs like a few of its own, none of them', () async {
    final discovery = Get.put<DiscoveryService>(_FakeDiscovery()
      ..like = {
        's1': [_song('a'), _song('s2')],
        's2': [_song('b'), _song('a')],
        's3': [_song('c')],
      }
      ..failing = {'s4'}) as _FakeDiscovery;
    final picks = await smartShufflePicks(
        [_song('s1'), _song('s2'), _song('s3'), _song('s4')],
        seeds: 4, random: Random(3));
    expect(discovery.asked.toSet(), {'s1', 's2', 's3', 's4'});
    expect(picks.map((m) => m.id).toList()..sort(), ['a', 'b', 'c']);
  });

  test('nothing to ask: no suggestions', () async {
    expect(await smartShufflePicks([_song('s1')]), isEmpty);
    expect(await smartShufflePicks(const []), isEmpty);
  });
}
