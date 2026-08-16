import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/songs_url_cache.dart';

String _url({required int expireEpoch}) =>
    'https://googlevideo.com/videoplayback?expire=$expireEpoch&id=x';

int _epochFromNow(Duration offset) =>
    DateTime.now().millisecondsSinceEpoch ~/ 1000 + offset.inSeconds;

Map<String, dynamic> _quality(String url) => {
      'itag': 140,
      'audioCodec': 'Codec.mp4a',
      'bitrate': 128000,
      'loudnessDb': 0,
      'url': url,
      'approxDurationMs': 180000,
      'size': 1,
    };

Map<String, dynamic> _cacheEntry({String? lowUrl, String? highUrl}) => {
      'playable': true,
      'statusMSG': 'OK',
      if (lowUrl != null) 'lowQualityAudio': _quality(lowUrl),
      if (highUrl != null) 'highQualityAudio': _quality(highUrl),
    };

void main() {
  final fresh = _url(expireEpoch: _epochFromNow(const Duration(hours: 2)));
  final stale = _url(expireEpoch: _epochFromNow(const Duration(minutes: 5)));

  group('songsUrlCacheEntryExpired', () {
    test('keeps a current HMStreamingData map with fresh quality URLs', () {
      expect(
        songsUrlCacheEntryExpired(
            _cacheEntry(lowUrl: fresh, highUrl: fresh)),
        isFalse,
      );
    });

    test('deletes a map whose quality URLs are all expired', () {
      expect(
        songsUrlCacheEntryExpired(
            _cacheEntry(lowUrl: stale, highUrl: stale)),
        isTrue,
      );
    });

    test('keeps a map when any quality URL is still fresh', () {
      expect(
        songsUrlCacheEntryExpired(
            _cacheEntry(lowUrl: stale, highUrl: fresh)),
        isFalse,
      );
      expect(
        songsUrlCacheEntryExpired(
            _cacheEntry(lowUrl: fresh, highUrl: stale)),
        isFalse,
      );
    });

    test('does not treat a quality map as list index [1]', () {
      // Old sweeper did `box.get(id)[1]`. On a Map that is null, so every
      // good SongsUrlCache entry was deleted.
      final entry = _cacheEntry(lowUrl: fresh, highUrl: fresh);
      // Hive used to index cache values as lists (`box.get(id)[1]`).
      // On a Map that lookup is null — do not treat the map as expired.
      expect(Map<Object?, Object?>.from(entry)[1], isNull);
      expect(songsUrlCacheEntryExpired(entry), isFalse);
    });

    test('deletes a map with no quality URLs', () {
      expect(songsUrlCacheEntryExpired({'playable': true}), isTrue);
      expect(songsUrlCacheEntryExpired(<String, dynamic>{}), isTrue);
    });

    test('keeps a legacy [low, high] list when a quality URL is fresh', () {
      expect(
        songsUrlCacheEntryExpired([_quality(stale), _quality(fresh)]),
        isFalse,
      );
    });

    test('deletes a legacy list whose quality URLs are expired', () {
      expect(
        songsUrlCacheEntryExpired([_quality(stale), _quality(stale)]),
        isTrue,
      );
    });

    test('deletes null and empty string entries', () {
      expect(songsUrlCacheEntryExpired(null), isTrue);
      expect(songsUrlCacheEntryExpired(''), isTrue);
    });

    test('leaves unknown shapes alone so good cache is not wiped', () {
      expect(songsUrlCacheEntryExpired(42), isFalse);
    });
  });
}
