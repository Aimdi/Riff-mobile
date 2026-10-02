import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/home_chip.dart';

Map<String, dynamic> _chip(String title, {String? params, String? browseId}) =>
    {
      'chipCloudChipRenderer': {
        'text': {
          'runs': [
            {'text': title}
          ]
        },
        'navigationEndpoint': {
          if (params != null)
            'browseEndpoint': {
              'browseId': browseId ?? 'FEmusic_home',
              'params': params,
            },
        },
      }
    };

void main() {
  test('reads title and params from the home header chip cloud', () {
    final chips = parseHomeChips({
      'header': {
        'chipCloudRenderer': {
          'chips': [
            _chip('Relax', params: 'ggMPOg1uX1JZ'),
            _chip('Workout', params: 'ggMPOg1uX2Fx'),
          ]
        }
      },
      'contents': [],
    });
    expect(chips.map((c) => c.title), ['Relax', 'Workout']);
    expect(chips.first.params, 'ggMPOg1uX1JZ');
    expect(chips.first.browseId, 'FEmusic_home');
  });

  test('skips chips without params and the Podcasts / Uploads chips', () {
    final chips = parseHomeChips({
      'header': {
        'chipCloudRenderer': {
          'chips': [
            _chip('Energize', params: 'a'),
            _chip('Toggle only'),
            _chip('Podcasts', params: 'b'),
            _chip('Uploads', params: 'c'),
            {'somethingElse': {}},
          ]
        }
      },
    });
    expect(chips.map((c) => c.title), ['Energize']);
  });

  test('no header, no chips', () {
    expect(parseHomeChips({'contents': []}), isEmpty);
    expect(parseHomeChips(null), isEmpty);
  });

  test('chips survive the Home cache round trip', () {
    const chip =
        HomeChip(title: 'Relax', params: 'p1', browseId: 'FEmusic_home');
    expect(HomeChip.fromJson(chip.toJson()), chip);
  });
}
