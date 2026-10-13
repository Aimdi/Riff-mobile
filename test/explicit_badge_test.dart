import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/models/media_item_extras.dart';
import 'package:harmonymusic/services/nav_parser.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/explicit_badge.dart';
import 'package:harmonymusic/ui/widgets/song_list_tile.dart';

Map<String, dynamic> _flex(String text) => {
      'musicResponsiveListItemFlexColumnRenderer': {
        'text': {
          'runs': [
            {'text': text}
          ]
        }
      }
    };

/// The badge YouTube Music puts on an explicit row.
const _explicitBadge = [
  {
    'musicInlineBadgeRenderer': {
      'icon': {'iconType': 'MUSIC_EXPLICIT_BADGE'},
      'accessibilityData': {
        'accessibilityData': {'label': 'Explicit'}
      },
    }
  }
];

Map<String, dynamic> _row(String videoId, {bool explicit = false}) => {
      'musicResponsiveListItemRenderer': {
        'playlistItemData': {'videoId': videoId},
        'flexColumns': [_flex('Song $videoId'), _flex('Artist')],
        if (explicit) 'badges': _explicitBadge,
      }
    };

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final isCurrentSongFav = false.obs;
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final slidableActionEnabled = true.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('rows with the badge are explicit, the others not', () {
    final songs = parsePlaylistItems([
      _row('a', explicit: true),
      _row('b'),
    ]).cast<MediaItem>();
    expect(songs.map((s) => s.isExplicit), [true, false]);
    expect(hasExplicitBadge({'badges': _explicitBadge}), isTrue);
    expect(hasExplicitBadge(const {}), isFalse);
  });

  test('the mark survives being saved and read back', () {
    final explicit = MediaItemBuilder.fromJson(
        {'videoId': 'a', 'title': 'A', 'isExplicit': true});
    final clean = MediaItemBuilder.fromJson({'videoId': 'b', 'title': 'B'});
    expect(
        MediaItemBuilder.fromJson(MediaItemBuilder.toJson(explicit)).isExplicit,
        isTrue);
    expect(MediaItemBuilder.fromJson(MediaItemBuilder.toJson(clean)).isExplicit,
        isFalse);
    // Clean songs are stored exactly as before.
    expect(MediaItemBuilder.toJson(clean).containsKey('isExplicit'), isFalse);
  });

  group('song rows', () {
    setUp(() {
      Get.put<PlayerController>(_FakePlayer());
      Get.put<SettingsScreenController>(_FakeSettings());
    });
    tearDown(Get.reset);

    Future<void> pumpRow(WidgetTester tester, MediaItem song) =>
        tester.pumpWidget(MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: Scaffold(
            body: SongListTile(
                song: song, thumbReplacementWithIndex: true, index: 1),
          ),
        ));

    testWidgets('an explicit song shows the E before its artist',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpRow(
          tester,
          const MediaItem(
              id: 'a',
              title: 'Song A',
              artist: 'Artist',
              extras: {'isExplicit': true}));
      expect(find.byType(ExplicitBadge), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('explicit')), findsWidgets);
      semantics.dispose();
    });

    testWidgets('a clean one has no badge', (tester) async {
      await pumpRow(
          tester, const MediaItem(id: 'b', title: 'Song B', artist: 'Artist'));
      expect(find.byType(ExplicitBadge), findsNothing);
      expect(find.text('Artist'), findsOneWidget);
    });
  });
}
