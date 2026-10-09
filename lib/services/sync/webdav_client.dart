/// A small WebDAV client: just what sync needs (check the account, make a
/// folder, read a file with its ETag, write it only if it didn't change).
library;

import 'dart:convert';

import 'package:dio/dio.dart';

/// Why a WebDAV call failed, for the settings page.
enum WebDavError {
  /// Wrong user or password (401 / 403).
  auth,

  /// The URL isn't a WebDAV folder (404 / 405 on the base URL).
  notFound,

  /// The server or the network didn't answer.
  network,

  /// Another device wrote the file in between (412).
  conflict,

  /// The file on the server isn't in a format we can read.
  badFile,

  /// The folder was written by a newer app version.
  tooNew,

  /// Anything else the server said no to.
  server,
}

class WebDavException implements Exception {
  const WebDavException(this.error, {this.status, this.message = ''});
  final WebDavError error;
  final int? status;
  final String message;

  @override
  String toString() => 'WebDavException(${error.name}, $status, $message)';
}

/// A file read from the server.
class WebDavFile {
  const WebDavFile(this.body, this.etag);
  final String body;
  final String? etag;
}

/// The URL of [path] under [base]: the base gets a trailing slash, each
/// path segment is percent-encoded.
Uri webDavUrl(String base, String path) {
  var b = base.trim();
  if (!b.endsWith('/')) b = '$b/';
  final baseUri = Uri.parse(b);
  final segments = path
      .split('/')
      .where((s) => s.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');
  final trailing = path.endsWith('/') && segments.isNotEmpty ? '/' : '';
  return baseUri.resolve('$segments$trailing');
}

/// Whether [url] looks like something we can connect to.
bool validWebDavBase(String url) {
  final u = Uri.tryParse(url.trim());
  return u != null &&
      (u.isScheme('https') || u.isScheme('http')) &&
      u.host.isNotEmpty;
}

WebDavError webDavErrorFor(int status) {
  if (status == 401 || status == 403) return WebDavError.auth;
  if (status == 404 || status == 405) return WebDavError.notFound;
  if (status == 412) return WebDavError.conflict;
  return WebDavError.server;
}

class WebDavClient {
  WebDavClient({
    required this.baseUrl,
    required String user,
    required String password,
    Dio? dio,
  })  : _auth = 'Basic ${base64Encode(utf8.encode('$user:$password'))}',
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 60),
            ));

  final String baseUrl;
  final String _auth;
  final Dio _dio;

  /// Releases the connection pool; the client can't be used afterwards.
  void close() => _dio.close();

  Future<Response<String>> _send(String method, String path,
      {Map<String, String> headers = const {}, String? body}) async {
    // Encoded once: a playlists file is sent as these bytes and measured
    // for Content-Length (it used to be encoded twice).
    final bytes = body == null ? null : utf8.encode(body);
    try {
      return await _dio.requestUri<String>(
        webDavUrl(baseUrl, path),
        data: bytes,
        options: Options(
          method: method,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          followRedirects: false,
          headers: {
            'Authorization': _auth,
            if (bytes != null) 'Content-Length': '${bytes.length}',
            ...headers,
          },
        ),
      );
    } on DioException catch (e) {
      throw WebDavException(WebDavError.network, message: e.message ?? '');
    }
  }

  /// Check the URL and account: a `PROPFIND` on the base folder.
  Future<void> check() async {
    final r = await _send('PROPFIND', '',
        headers: {
          'Depth': '0',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        body: '<?xml version="1.0" encoding="utf-8"?>'
            '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop>'
            '</d:propfind>');
    final s = r.statusCode ?? 0;
    if (s == 207 || s == 200) return;
    throw WebDavException(webDavErrorFor(s), status: s);
  }

  /// Make the folder [path] (and its parents). Folders that are already
  /// there are fine.
  Future<void> ensureFolder(String path) async {
    var sofar = '';
    for (final part in path.split('/').where((s) => s.isNotEmpty)) {
      sofar = '$sofar$part/';
      final r = await _send('MKCOL', sofar);
      final s = r.statusCode ?? 0;
      // 201 made; 405 / 301 already there.
      if (s == 201 || s == 405 || s == 301 || s == 200) continue;
      throw WebDavException(webDavErrorFor(s), status: s);
    }
  }

  /// The file at [path], or null when there's none.
  Future<WebDavFile?> read(String path) async {
    final r = await _send('GET', path);
    final s = r.statusCode ?? 0;
    if (s == 404) return null;
    if (s != 200) throw WebDavException(webDavErrorFor(s), status: s);
    return WebDavFile(r.data ?? '', r.headers.value('etag'));
  }

  /// Write [body] to [path]: only over the version with [ifMatch] when
  /// given, only if there's no file when [create]. Throws a
  /// [WebDavError.conflict] when someone else wrote it first.
  Future<void> write(String path, String body,
      {String? ifMatch,
      bool create = false,
      required String contentType}) async {
    final r = await _send('PUT', path, body: body, headers: {
      'Content-Type': contentType,
      if (ifMatch != null) 'If-Match': ifMatch,
      if (ifMatch == null && create) 'If-None-Match': '*',
    });
    final s = r.statusCode ?? 0;
    if (s >= 200 && s < 300) return;
    throw WebDavException(webDavErrorFor(s), status: s);
  }
}
