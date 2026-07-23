import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/nav_parser.dart';

void main() {
  test('getTabBrowseId returns null for missing / unselectable tabs', () {
    expect(getTabBrowseId({}, 2), isNull);
    expect(
      getTabBrowseId({
        'tabs': [
          {
            'tabRenderer': {
              'endpoint': {
                'browseEndpoint': {'browseId': 'lyrics'}
              }
            }
          },
        ]
      }, 2),
      isNull,
    );
    expect(
      getTabBrowseId({
        'tabs': [
          {'tabRenderer': {}},
          {'tabRenderer': {}},
          {
            'tabRenderer': {
              'unselectable': true,
              'endpoint': {
                'browseEndpoint': {'browseId': 'related'}
              }
            }
          },
        ]
      }, 2),
      isNull,
    );
    expect(
      getTabBrowseId({
        'tabs': [
          {'tabRenderer': {}},
          {'tabRenderer': {}},
          {
            'tabRenderer': {
              'endpoint': {
                'browseEndpoint': {'browseId': 'MFAR123'}
              }
            }
          },
        ]
      }, 2),
      'MFAR123',
    );
  });
}
