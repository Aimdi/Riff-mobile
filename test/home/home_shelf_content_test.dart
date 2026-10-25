import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/artist.dart';
import 'package:harmonymusic/models/home_shelf_content.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/models/shelf_header.dart';

MediaItem song(String id, String title, String artist) =>
    MediaItemBuilder.fromJson({
      'videoId': id,
      'title': title,
      'artists': [
        {'name': artist, 'id': 'UC_$id'}
      ],
      'thumbnails': [
        {'url': 'https://example.com/$id.jpg'}
      ],
    });

void main() {
  test('song shelf survives the Home cache round trip', () {
    final shelf = SongContent(title: 'Listen again', songs: [
      song('a1', 'Redbone', 'Childish Gambino'),
      song('a2', 'Nights', 'Frank Ocean'),
    ]);
    final back = SongContent.fromJson(shelf.toJson());
    expect(back.title, 'Listen again');
    expect(back.songs.map((s) => s.id), ['a1', 'a2']);
    expect(back.songs.first.artist, 'Childish Gambino');
    expect(shelf.toJson()['type'], 'Song Content');
  });

  test('artist shelf survives the Home cache round trip', () {
    final shelf = ArtistShelf(title: 'Similar artists', artists: [
      Artist(
          name: 'Clairo',
          browseId: 'UC1',
          thumbnailUrl: 'https://example.com/c.jpg',
          subscribers: '3M subscribers'),
    ]);
    final back = ArtistShelf.fromJson(shelf.toJson());
    expect(back.title, 'Similar artists');
    expect(back.artists.single.browseId, 'UC1');
    expect(back.artists.single.name, 'Clairo');
    expect(shelf.toJson()['type'], 'Artist Content');
  });

  test('the line and picture over a shelf survive the cache round trip', () {
    const header = ShelfHeader(
        strapline: 'Similar to',
        art: 'https://example.com/nova.jpg',
        round: true,
        named: true);
    final shelf = ArtistShelf(title: 'Nova Hart', header: header, artists: [
      Artist(
          name: 'Odd Weather',
          browseId: 'UC2',
          thumbnailUrl: 'https://example.com/o.jpg',
          subscribers: '318K subscribers'),
    ]);
    final back = ArtistShelf.fromJson(shelf.toJson()).header!;
    expect(back.strapline, 'Similar to');
    expect(back.art, 'https://example.com/nova.jpg');
    expect(back.round, isTrue);
    expect(back.named, isTrue);

    final songs = SongContent(
        title: 'Listen again',
        header: const ShelfHeader(strapline: 'Sam Okafor'),
        songs: [song('a1', 'Redbone', 'Childish Gambino')]);
    final again = SongContent.fromJson(songs.toJson()).header!;
    expect(again.strapline, 'Sam Okafor');
    expect(again.art, isNull);
    expect(again.round, isFalse);
    expect(again.named, isFalse);
  });

  test('shelves cached before headers, or with an empty one, have none', () {
    final old = SongContent.fromJson({
      'type': 'Song Content',
      'title': 'Listen again',
      'songs': <dynamic>[],
    });
    expect(old.header, isNull);
    expect(old.toJson().containsKey('header'), isFalse);
    expect(ShelfHeader.fromJson({'strapline': '  ', 'round': true}), isNull);
    expect(ShelfHeader.fromJson('not a map'), isNull);
  });
}
