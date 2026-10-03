import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_playback_profile.dart';
import 'package:hive/hive.dart';

void main() {
  group('speed and skip snapping', () {
    test('speed clamps to 0.5–3.0 and keeps two decimals', () {
      expect(PodcastPlaybackProfile.snapSpeed(0.1), 0.5);
      expect(PodcastPlaybackProfile.snapSpeed(9), 3.0);
      expect(PodcastPlaybackProfile.snapSpeed(1.25), 1.25);
      expect(PodcastPlaybackProfile.snapSpeed(1.2000000001), 1.2);
      expect(PodcastPlaybackProfile.snapSpeed(null), 1.0);
      expect(PodcastPlaybackProfile.snapSpeed(double.nan), 1.0);
    });

    test('skip lengths snap to the nearest allowed choice', () {
      expect(PodcastPlaybackProfile.snapSkip(10, fallback: 30), 10);
      expect(PodcastPlaybackProfile.snapSkip(12, fallback: 30), 10);
      expect(PodcastPlaybackProfile.snapSkip(40, fallback: 30), 45);
      expect(PodcastPlaybackProfile.snapSkip(500, fallback: 30), 60);
      expect(PodcastPlaybackProfile.snapSkip(null, fallback: 30), 30);
    });
  });

  group('fromMap / toMap', () {
    test('round trip', () {
      const p = PodcastPlaybackProfile(
        speed: 1.5,
        skipBackSec: 15,
        skipForwardSec: 45,
        trimSilence: true,
        voiceBoost: PodcastVoiceBoost.high,
        segmentSkip: false,
      );
      expect(PodcastPlaybackProfile.fromMap(p.toMap()), p);
    });

    test('garbage and missing keys fall back without throwing', () {
      const fb = PodcastPlaybackProfile(speed: 1.3, skipForwardSec: 15);
      expect(PodcastPlaybackProfile.fromMap(null, fallback: fb), fb);
      expect(PodcastPlaybackProfile.fromMap('x', fallback: fb), fb);
      final p = PodcastPlaybackProfile.fromMap({
        'speed': 'fast',
        'skipBack': 'ten',
        'trimSilence': 1,
        'voiceBoost': 'loudest',
      }, fallback: fb);
      expect(p.speed, 1.3);
      expect(p.skipBackSec, fb.skipBackSec);
      expect(p.skipForwardSec, 15);
      expect(p.trimSilence, isFalse);
      expect(p.voiceBoost, PodcastVoiceBoost.off);
    });

    test('out-of-range values are clamped', () {
      final p = PodcastPlaybackProfile.fromMap({'speed': 7, 'skipBack': 2});
      expect(p.speed, 3.0);
      expect(p.skipBackSec, 5);
    });
  });

  group('seedPodcastDefaults (migration)', () {
    test('first run carries over what podcasts played with before', () {
      final p = seedPodcastDefaults(
          appSpeed: 1.4, appSkipSilence: true, autoSkipAds: false);
      expect(p.speed, 1.4);
      expect(p.trimSilence, isTrue);
      expect(p.segmentSkip, isFalse);
      expect(p.skipBackSec, 10);
      expect(p.skipForwardSec, 30);
      expect(p.voiceBoost, PodcastVoiceBoost.off);
    });

    test('nothing stored at all gives plain defaults', () {
      expect(seedPodcastDefaults(), const PodcastPlaybackProfile());
    });

    test('stored defaults win over the app-wide values', () {
      final p = seedPodcastDefaults(
        stored: const PodcastPlaybackProfile(speed: 2.0).toMap(),
        appSpeed: 1.4,
      );
      expect(p.speed, 2.0);
    });

    test('the ad-skip toggle is the source of truth for segment skip', () {
      final p = seedPodcastDefaults(
        stored: const PodcastPlaybackProfile(segmentSkip: true).toMap(),
        autoSkipAds: false,
      );
      expect(p.segmentSkip, isFalse);
    });
  });

  group('show keys', () {
    test('RSS shows use the feed URL', () {
      const item = MediaItem(
          id: 'podcast_1',
          title: 'Ep',
          extras: {'feedUrl': 'https://a.example/feed.xml'});
      expect(podcastShowKey(item), 'https://a.example/feed.xml');
    });

    test('YouTube shows use the playlist id without VL / MPSP', () {
      expect(podcastShowKeyForYoutube('VLPLabc'), 'yt:PLabc');
      expect(podcastShowKeyForYoutube('MPSPPLabc'), 'yt:PLabc');
      expect(podcastShowKeyForYoutube('PLabc'), 'yt:PLabc');
      const item = MediaItem(
          id: 'vid', title: 'Ep', extras: {'podcastPlaylistId': 'PLabc'});
      expect(podcastShowKey(item), 'yt:PLabc');
    });

    test('YouTube episodes get tagged with the show they came from', () {
      const bare = MediaItem(id: 'vid', title: 'Ep', extras: {'a': 1});
      final tagged = withPodcastShowId(bare, 'MPSPPLabc');
      expect(podcastShowKey(tagged), 'yt:PLabc');
      expect(tagged.extras!['a'], 1);
      const rss = MediaItem(
          id: 'p', title: 'Ep', extras: {'feedUrl': 'https://f'});
      expect(withPodcastShowId(rss, 'PLx'), same(rss));
      expect(withPodcastShowId(bare, null), same(bare));
    });

    test('unknown show has no key', () {
      expect(podcastShowKey(const MediaItem(id: 'x', title: 'y')), isNull);
      expect(podcastShowKeyForFeed('  '), isNull);
      expect(podcastShowKeyForYoutube(''), isNull);
    });
  });

  group('smart resume', () {
    test('rewind steps by pause length', () {
      expect(smartResumeRewind(const Duration(seconds: 4)), Duration.zero);
      expect(smartResumeRewind(const Duration(seconds: 5)),
          const Duration(seconds: 3));
      expect(smartResumeRewind(const Duration(minutes: 1)),
          const Duration(seconds: 3));
      expect(smartResumeRewind(const Duration(minutes: 1, seconds: 1)),
          const Duration(seconds: 5));
      expect(smartResumeRewind(const Duration(minutes: 10)),
          const Duration(seconds: 5));
      expect(smartResumeRewind(const Duration(minutes: 11)),
          const Duration(seconds: 10));
    });

    test('target never goes below zero', () {
      expect(
          smartResumeTarget(
              const Duration(seconds: 2), const Duration(seconds: 10)),
          Duration.zero);
      expect(
          smartResumeTarget(
              const Duration(seconds: 60), const Duration(seconds: 10)),
          const Duration(seconds: 50));
    });
  });

  group('sleep fade', () {
    test('volume factor goes linearly from 1 to 0', () {
      const len = Duration(seconds: 10);
      expect(sleepFadeFactor(Duration.zero, len), 1.0);
      expect(sleepFadeFactor(const Duration(seconds: 5), len), 0.5);
      expect(sleepFadeFactor(const Duration(seconds: 12), len), 0.0);
      expect(sleepFadeFactor(Duration.zero, Duration.zero), 0.0);
    });

    test('wall-clock time accounts for playback speed', () {
      expect(wallClockRemaining(const Duration(seconds: 20), 2.0),
          const Duration(seconds: 10));
      expect(wallClockRemaining(const Duration(seconds: 20), 0),
          const Duration(seconds: 20));
    });
  });

  group('PodcastPlaybackPrefs (Hive)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('riff_pod_prefs_');
      Hive.init(tmp.path);
      await Hive.openBox('AppPrefs');
      await Hive.openBox(PodcastPlaybackPrefs.showBox);
    });
    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('shows use the global defaults until they get overrides', () async {
      await Hive.box('AppPrefs').put('playbackSpeed', 1.2);
      expect(PodcastPlaybackPrefs.forShow('feed').speed, 1.2);
      await PodcastPlaybackPrefs.setShowOverride(
          'feed', const PodcastPlaybackProfile(speed: 1.8));
      expect(PodcastPlaybackPrefs.hasShowOverride('feed'), isTrue);
      expect(PodcastPlaybackPrefs.forShow('feed').speed, 1.8);
      expect(PodcastPlaybackPrefs.forShow('other').speed, 1.2);
      await PodcastPlaybackPrefs.clearShowOverride('feed');
      expect(PodcastPlaybackPrefs.forShow('feed').speed, 1.2);
    });

    test('saveForShow writes where the show\'s settings live', () async {
      await PodcastPlaybackPrefs.saveForShow(
          'feed', const PodcastPlaybackProfile(speed: 1.6));
      expect(PodcastPlaybackPrefs.globalDefaults.speed, 1.6);
      expect(PodcastPlaybackPrefs.hasShowOverride('feed'), isFalse);
      await PodcastPlaybackPrefs.setShowOverride(
          'feed', const PodcastPlaybackProfile(speed: 2.0));
      await PodcastPlaybackPrefs.saveForShow(
          'feed', const PodcastPlaybackProfile(speed: 2.5));
      expect(PodcastPlaybackPrefs.forShow('feed').speed, 2.5);
      expect(PodcastPlaybackPrefs.globalDefaults.speed, 1.6);
    });

    test('global segment skip writes the existing ad-skip key', () async {
      await PodcastPlaybackPrefs.setGlobalDefaults(
          const PodcastPlaybackProfile(segmentSkip: false));
      expect(Hive.box('AppPrefs').get('podcastAutoSkipAds'), isFalse);
      expect(PodcastPlaybackPrefs.globalDefaults.segmentSkip, isFalse);
    });

    test('smart resume defaults on', () async {
      expect(PodcastPlaybackPrefs.smartResume, isTrue);
      await PodcastPlaybackPrefs.setSmartResume(false);
      expect(PodcastPlaybackPrefs.smartResume, isFalse);
    });

    test('a corrupt show entry falls back to the defaults', () async {
      await Hive.box(PodcastPlaybackPrefs.showBox).put('feed', 'nonsense');
      expect(PodcastPlaybackPrefs.hasShowOverride('feed'), isFalse);
      expect(PodcastPlaybackPrefs.forShow('feed'),
          PodcastPlaybackPrefs.globalDefaults);
    });
  });
}
