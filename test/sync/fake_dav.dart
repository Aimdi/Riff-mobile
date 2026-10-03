import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:harmonymusic/services/sync/webdav_client.dart';

/// A WebDAV server in memory: files with ETags, 412 on a stale If-Match.
class FakeDav implements HttpClientAdapter {
  final files = <String, String>{};
  final etags = <String, String>{};
  final folders = <String>{'/dav/'};
  final requests = <RequestOptions>[];
  String password = 'secret';
  var _n = 0;

  /// Next PUT to this path fails with 412 once (another device wrote).
  String? raceOn;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body,
      Future<void>? cancelFuture) async {
    requests.add(o);
    final auth = o.headers['Authorization'];
    if (auth != 'Basic ${base64Encode(utf8.encode('me:$password'))}') {
      return ResponseBody.fromString('', 401);
    }
    final path = Uri.decodeFull(o.uri.path);
    switch (o.method) {
      case 'PROPFIND':
        return ResponseBody.fromString('', folders.contains(path) ? 207 : 404);
      case 'MKCOL':
        if (folders.contains(path)) return ResponseBody.fromString('', 405);
        folders.add(path);
        return ResponseBody.fromString('', 201);
      case 'GET':
        final f = files[path];
        if (f == null) return ResponseBody.fromString('', 404);
        return ResponseBody.fromString(f, 200, headers: {
          'etag': [etags[path]!]
        });
      case 'PUT':
        final ifMatch = o.headers['If-Match'];
        final ifNone = o.headers['If-None-Match'];
        if (raceOn == path) {
          raceOn = null;
          files[path] = files[path] ?? '';
          etags[path] = '"race${_n++}"';
          return ResponseBody.fromString('', 412);
        }
        if (ifMatch != null && etags[path] != ifMatch) {
          return ResponseBody.fromString('', 412);
        }
        if (ifNone == '*' && files.containsKey(path)) {
          return ResponseBody.fromString('', 412);
        }
        final bytes = <int>[];
        await for (final c in body!) {
          bytes.addAll(c);
        }
        files[path] = utf8.decode(bytes);
        etags[path] = '"${_n++}"';
        return ResponseBody.fromString('', 201);
    }
    return ResponseBody.fromString('', 405);
  }

  @override
  void close({bool force = false}) {}
}

WebDavClient client(FakeDav dav, {String password = 'secret'}) {
  final dio = Dio()..httpClientAdapter = dav;
  return WebDavClient(
      baseUrl: 'https://cloud.example.com/dav',
      user: 'me',
      password: password,
      dio: dio);
}
