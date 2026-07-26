import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/client_config_service.dart';

/// Shape the resolver actually consumes (StreamService._attemptsFromConfig).
String _validConfig() => jsonEncode({
      'version': 1,
      'attempts': [
        [
          {
            'name': 'ANDROID_VR_1_65_10',
            'apiUrl':
                'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
            'payload': {
              'context': {
                'client': {
                  'clientName': 'ANDROID_VR',
                  'clientVersion': '1.65.10',
                }
              }
            },
          }
        ],
        [
          {
            'name': 'VISIONOS',
            'apiUrl':
                'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
            'payload': {
              'context': {
                'client': {'clientName': 'VISIONOS', 'clientVersion': '0.1'}
              }
            },
          }
        ],
      ],
    });

void main() {
  group('validateConfigJson', () {
    test('accepts a well-formed config', () {
      expect(ClientConfigService.validateConfigJson(_validConfig()), isNull);
    });

    test('rejects a typo in the top-level attempts key', () {
      // The old gate was `body.contains("attempts")` — this body contains the
      // substring, so it used to be cached and then silently degraded to the
      // built-in attempts on device (emergency fix shipping as a no-op).
      final body = jsonEncode({
        'version': 1,
        'comment': 'groups listed under attempts',
        'attempt': jsonDecode(_validConfig())['attempts'],
      });
      expect(body.contains('attempts'), isTrue,
          reason: 'old gate would have accepted this');
      expect(ClientConfigService.validateConfigJson(body),
          'missing "attempts"');
    });

    test('rejects a typo in a client entry key', () {
      final config = jsonDecode(_validConfig()) as Map<String, dynamic>;
      final client =
          (config['attempts'] as List)[0][0] as Map<String, dynamic>;
      client['api_url'] = client.remove('apiUrl');
      expect(ClientConfigService.validateConfigJson(jsonEncode(config)),
          'client entry missing "apiUrl"');
    });

    test('rejects a client entry whose payload lost its context', () {
      final config = jsonDecode(_validConfig()) as Map<String, dynamic>;
      final client =
          (config['attempts'] as List)[0][0] as Map<String, dynamic>;
      client['payload'] = {'ctx': {}};
      expect(ClientConfigService.validateConfigJson(jsonEncode(config)),
          'client payload missing "context"');
    });

    test('rejects malformed JSON that still mentions attempts', () {
      const body = '{"attempts": [ [ {"apiUrl": "https://x", ';
      expect(body.contains('attempts'), isTrue);
      expect(
          ClientConfigService.validateConfigJson(body), 'malformed JSON');
    });

    test('rejects an empty attempts list', () {
      expect(
          ClientConfigService.validateConfigJson(
              jsonEncode({'version': 1, 'attempts': []})),
          '"attempts" is empty');
    });

    test('rejects attempts made only of empty groups', () {
      expect(
          ClientConfigService.validateConfigJson(jsonEncode({
            'version': 1,
            'attempts': [[], []]
          })),
          'no non-empty attempt groups');
    });

    test('rejects a non-object root and an empty body', () {
      expect(ClientConfigService.validateConfigJson('[]'),
          'root is not an object');
      expect(ClientConfigService.validateConfigJson('   '), 'empty body');
      expect(ClientConfigService.validateConfigJson(null), 'empty body');
    });
  });

  group('shouldRefresh (cold-start TTL)', () {
    test('refreshes when there is no cached copy, however recent the stamp',
        () {
      expect(
          ClientConfigService.shouldRefresh(
              hasCached: false, fetchedAtMs: 1000, nowMs: 1000),
          isTrue);
    });

    test('skips while the cache is inside the TTL', () {
      expect(
          ClientConfigService.shouldRefresh(
              hasCached: true,
              fetchedAtMs: 0,
              nowMs: ClientConfigService.ttlMs - 1),
          isFalse);
    });

    test('refreshes once the TTL has elapsed', () {
      expect(
          ClientConfigService.shouldRefresh(
              hasCached: true,
              fetchedAtMs: 0,
              nowMs: ClientConfigService.ttlMs),
          isTrue);
    });
  });

  group('forceRefreshAllowed (repair-lever cooldown)', () {
    test('a never-forced install is allowed immediately', () {
      expect(
          ClientConfigService.forceRefreshAllowed(
              lastAttemptMs: 0, nowMs: 5000),
          isTrue);
    });

    test('bypasses the 12h TTL — the cooldown is the only gate', () {
      // Fetched one second ago: shouldRefresh says no, forceRefresh says yes.
      const now = 100000000;
      expect(
          ClientConfigService.shouldRefresh(
              hasCached: true, fetchedAtMs: now - 1000, nowMs: now),
          isFalse);
      expect(
          ClientConfigService.forceRefreshAllowed(
              lastAttemptMs: 0, nowMs: now),
          isTrue);
    });

    test('a failing track cannot hammer the endpoint inside the cooldown', () {
      const last = 100000000;
      expect(
          ClientConfigService.forceRefreshAllowed(
              lastAttemptMs: last,
              nowMs: last + ClientConfigService.forceRefreshCooldownMs - 1),
          isFalse);
    });

    test('allowed again once the cooldown elapses', () {
      const last = 100000000;
      expect(
          ClientConfigService.forceRefreshAllowed(
              lastAttemptMs: last,
              nowMs: last + ClientConfigService.forceRefreshCooldownMs),
          isTrue);
    });

    test('a backwards clock jump does not lock the lever out', () {
      expect(
          ClientConfigService.forceRefreshAllowed(
              lastAttemptMs: 100000000, nowMs: 90000000),
          isTrue);
    });

    test('cooldown is 5 minutes and shorter than the TTL', () {
      expect(ClientConfigService.forceRefreshCooldownMs, 5 * 60 * 1000);
      expect(ClientConfigService.forceRefreshCooldownMs,
          lessThan(ClientConfigService.ttlMs));
    });
  });
}
