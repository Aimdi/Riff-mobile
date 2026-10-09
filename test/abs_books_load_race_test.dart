import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/audiobookshelf_service.dart';
import 'package:hive/hive.dart';

/// A tiny Audiobookshelf server: one book library whose item pages and
/// search the test controls.
class _FakeAbs {
  late HttpServer server;
  int fullPages = 0;
  Completer<void>? holdPage1;
  final page1Asked = Completer<void>();
  bool searchFails = false;

  String get url => 'http://127.0.0.1:${server.port}';

  Map<String, dynamic> _item(String id, String title) => {
        'id': id,
        'media': {
          'metadata': {'title': title},
        },
      };

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await req.drain<void>();
      final path = req.uri.path;
      Object? body;
      if (path == '/login') {
        body = {
          'user': {'id': 'u1', 'accessToken': 'token'}
        };
      } else if (path == '/api/libraries') {
        body = {
          'libraries': [
            {'id': 'lib', 'name': 'Books', 'mediaType': 'book'}
          ]
        };
      } else if (path == '/api/libraries/lib/items') {
        final page = int.parse(req.uri.queryParameters['page'] ?? '0');
        if (page == 0) {
          final n = fullPages > 0 ? 50 : 1;
          body = {
            'results': [for (var i = 0; i < n; i++) _item('b$i', 'Book $i')]
          };
        } else {
          if (!page1Asked.isCompleted) page1Asked.complete();
          await holdPage1?.future;
          body = {
            'results': [_item('late', 'Late page')]
          };
        }
      } else if (path == '/api/libraries/lib/search') {
        if (searchFails) {
          req.response.statusCode = 500;
          await req.response.close();
          return;
        }
        body = {
          'book': [
            {'libraryItem': _item('hit', 'Search hit')}
          ]
        };
      } else {
        body = <dynamic>[];
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(body));
      await req.response.close();
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late _FakeAbs fake;
  late AudiobookshelfService abs;

  setUp(() async {
    // Real sockets to the local server (the test binding fakes HTTP).
    HttpOverrides.global = null;
    tmp = await Directory.systemTemp.createTemp('abs_race');
    Hive.init(tmp.path);
    await Hive.openBox('AppPrefs');
    fake = _FakeAbs();
    await fake.start();
    Get.reset();
    abs = Get.put(AudiobookshelfService());
    await abs.login(serverUrl: fake.url, user: 'u', password: 'p');
  });

  tearDown(() async {
    Get.reset();
    await fake.server.close(force: true);
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('a search keeps its results when a library page lands after it',
      () async {
    expect(abs.books.map((b) => b.title), ['Book 0']);
    fake
      ..fullPages = 1
      ..holdPage1 = Completer<void>();
    final load = abs.fetchBooks();
    await fake.page1Asked.future;

    await abs.searchBooks('hit');
    expect(abs.books.map((b) => b.title), ['Search hit']);

    // The rest of the library arrives late; it used to be appended to the
    // search results.
    fake.holdPage1!.complete();
    await load;
    expect(abs.books.map((b) => b.title), ['Search hit']);
    expect(abs.isLoading.isFalse, isTrue);
  });

  test('a failed search keeps the list and does not throw', () async {
    fake.searchFails = true;
    await expectLater(abs.searchBooks('boom'), completes);
    expect(abs.books.map((b) => b.title), ['Book 0']);
    expect(abs.isLoading.isFalse, isTrue);
  });
}
