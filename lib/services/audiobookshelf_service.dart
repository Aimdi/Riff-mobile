import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
// get also exports FormData/MultipartFile for its own HTTP client; hide them
// so the dio versions used for uploads win unambiguously.
import 'package:get/get.dart' hide FormData, MultipartFile;
import 'package:hive/hive.dart';

import '../utils/helper.dart';
import 'abs_progress.dart';

export 'abs_progress.dart' show mapAbsCurrentTimeToTrack, parseAbsProgress;

/// Minimal library entry from Audiobookshelf (Lissen-style).
class AbsLibrary {
  AbsLibrary(
      {required this.id,
      required this.name,
      this.mediaType = 'book',
      this.folders = const []});
  final String id;
  final String name;
  final String mediaType;

  /// Storage folders configured for this library. Uploads must target one of
  /// these by its folder id.
  final List<AbsFolder> folders;
}

/// A storage folder within a library (upload destination).
class AbsFolder {
  AbsFolder({required this.id, required this.fullPath});
  final String id;
  final String fullPath;
}

/// A local file staged for upload to the server. Prefer [path] (streamed from
/// disk) over [bytes] to avoid OOM on large audiobooks.
class AbsUploadFile {
  AbsUploadFile({required this.filename, this.bytes, this.path})
      : assert(bytes != null || path != null);
  final String filename;
  final List<int>? bytes;
  final String? path;
}

/// Book row in a library listing.
class AbsBook {
  AbsBook({
    required this.id,
    required this.title,
    this.author,
    this.subtitle,
    this.duration,
    this.progress,
  });
  final String id;
  final String title;
  final String? author;
  final String? subtitle;
  final double? duration;
  final double? progress; // 0..1 if known

  String coverUrl(String host, String token) =>
      '$host/api/items/$id/cover?width=400&token=${Uri.encodeComponent(token)}';
}

/// One streamable audio track / chapter file.
class AbsAudioTrack {
  AbsAudioTrack({
    required this.index,
    required this.title,
    required this.contentUrl,
    required this.duration,
    this.mimeType,
    this.ino,
  });
  final int index;
  final String title;
  final String contentUrl; // relative /api/items/.../file/...
  final double duration;
  final String? mimeType;
  final String? ino;
}

/// Detailed book with tracks ready for playback.
class AbsBookDetail {
  AbsBookDetail({
    required this.id,
    required this.title,
    required this.author,
    required this.tracks,
    this.description,
    this.narrator,
    this.currentTime = 0,
    this.sessionId,
  });
  final String id;
  final String title;
  final String author;
  final String? description;
  final String? narrator;
  final List<AbsAudioTrack> tracks;
  final double currentTime;
  final String? sessionId;
}

/// Audiobookshelf client modeled on Lissen
/// (https://github.com/GrakovNe/lissen-android).
///
/// Talks to a self-hosted ABS server: login, browse book libraries, start a
/// play session, and stream files via tokenized URLs through Riff's player.
class AudiobookshelfService extends GetxService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'content-type': 'application/json',
      'user-agent': 'Riff-mobile/1.0 (Audiobookshelf; Lissen-compatible)',
    },
  ));

  final isConnected = false.obs;
  final host = ''.obs;
  final username = ''.obs;
  final libraries = <AbsLibrary>[].obs;
  final selectedLibraryId = ''.obs;
  final books = <AbsBook>[].obs;
  final inProgressBooks = <AbsBook>[].obs;
  final isLoading = false.obs;
  final statusMessage = ''.obs;

  String? _token;
  String? _userId;

  Box get _prefs => Hive.box('AppPrefs');

  String? get token => _token;

  @override
  void onInit() {
    super.onInit();
    _restoreSession();
  }

  void _restoreSession() {
    final cfg = _prefs.get('audiobookshelf');
    if (cfg is! Map) return;
    host.value = (cfg['host'] ?? '').toString();
    username.value = (cfg['username'] ?? '').toString();
    _token = cfg['token']?.toString();
    _userId = cfg['userId']?.toString();
    selectedLibraryId.value = (cfg['libraryId'] ?? '').toString();
    if (_token != null && _token!.isNotEmpty && host.value.isNotEmpty) {
      isConnected.value = true;
      // Lazy refresh libraries
      Future.microtask(() async {
        try {
          await fetchLibraries();
          if (selectedLibraryId.value.isNotEmpty) {
            await fetchBooks();
          } else {
            await fetchInProgress();
          }
        } catch (e) {
          printERROR('ABS restore failed: $e');
        }
      });
    }
  }

  void _persist() {
    _prefs.put('audiobookshelf', {
      'host': host.value,
      'username': username.value,
      'token': _token,
      'userId': _userId,
      'libraryId': selectedLibraryId.value,
    });
  }

  String _normalizeHost(String raw) {
    var h = raw.trim();
    if (h.endsWith('/')) h = h.substring(0, h.length - 1);
    if (!h.startsWith('http://') && !h.startsWith('https://')) {
      h = 'https://$h';
    }
    return h;
  }

  Options get _authOptions => Options(headers: {
        if (_token != null) 'Authorization': 'Bearer $_token',
      });

  /// Login with username/password (same endpoint as Lissen: POST /login).
  Future<void> login({
    required String serverUrl,
    required String user,
    required String password,
  }) async {
    isLoading.value = true;
    statusMessage.value = '';
    try {
      final h = _normalizeHost(serverUrl);
      final res = await _dio.post(
        '$h/login',
        data: {'username': user, 'password': password},
        options: Options(headers: {'x-return-tokens': 'true'}),
      );
      final data = res.data;
      if (data is! Map || data['user'] is! Map) {
        throw StateError('Unexpected login response');
      }
      final u = data['user'] as Map;
      _token = (u['accessToken'] ?? u['token'])?.toString();
      _userId = u['id']?.toString();
      if (_token == null || _token!.isEmpty) {
        throw StateError('No token in login response');
      }
      host.value = h;
      username.value = user;
      isConnected.value = true;
      _persist();
      await fetchLibraries();
      if (libraries.isNotEmpty) {
        // Prefer book libraries
        final bookLib = libraries.firstWhereOrNull((l) => l.mediaType == 'book');
        selectedLibraryId.value = (bookLib ?? libraries.first).id;
        _persist();
        await fetchBooks();
      }
      await fetchInProgress();
      statusMessage.value = '';
    } on DioException catch (e) {
      isConnected.value = false;
      statusMessage.value = e.response?.statusCode == 401
          ? 'absLoginFailed'.tr
          : (e.message ?? 'networkError'.tr);
      rethrow;
    } catch (e) {
      isConnected.value = false;
      statusMessage.value = e.toString();
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _userId = null;
    isConnected.value = false;
    libraries.clear();
    books.clear();
    inProgressBooks.clear();
    selectedLibraryId.value = '';
    host.value = '';
    username.value = '';
    _prefs.delete('audiobookshelf');
  }

  Future<void> fetchLibraries() async {
    _ensureConnected();
    final res = await _dio.get(
      '${host.value}/api/libraries',
      options: _authOptions,
    );
    final list = <AbsLibrary>[];
    final libs = res.data is Map ? res.data['libraries'] : res.data;
    if (libs is List) {
      for (final l in libs) {
        if (l is! Map) continue;
        final folders = <AbsFolder>[];
        if (l['folders'] is List) {
          for (final f in (l['folders'] as List)) {
            if (f is Map && f['id'] != null) {
              folders.add(AbsFolder(
                id: f['id'].toString(),
                fullPath: (f['fullPath'] ?? f['path'] ?? '').toString(),
              ));
            }
          }
        }
        list.add(AbsLibrary(
          id: l['id'].toString(),
          name: (l['name'] ?? 'Library').toString(),
          mediaType: (l['mediaType'] ?? 'book').toString(),
          folders: folders,
        ));
      }
    }
    libraries.assignAll(list);
  }

  Future<void> selectLibrary(String id) async {
    selectedLibraryId.value = id;
    _persist();
    await fetchBooks();
  }

  AbsLibrary? get selectedLibrary =>
      libraries.firstWhereOrNull((l) => l.id == selectedLibraryId.value);

  /// Upload one or more local audio files as a new item to the server, via
  /// ABS's multipart `POST /api/upload`. Files are sent under the `0`, `1`, …
  /// keys the server expects. [onProgress] reports 0..1 send progress.
  ///
  /// Requires the logged-in user to have upload permission on the server.
  Future<void> uploadBook({
    required String libraryId,
    required String folderId,
    required String title,
    String? author,
    String? series,
    required List<AbsUploadFile> files,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    _ensureConnected();
    if (files.isEmpty) {
      throw StateError('No files to upload');
    }
    final form = FormData();
    form.fields
      ..add(MapEntry('title', title))
      ..add(MapEntry('library', libraryId))
      ..add(MapEntry('folder', folderId));
    if (author != null && author.trim().isNotEmpty) {
      form.fields.add(MapEntry('author', author.trim()));
    }
    if (series != null && series.trim().isNotEmpty) {
      form.fields.add(MapEntry('series', series.trim()));
    }
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final part = (f.path != null && f.path!.isNotEmpty)
          ? await MultipartFile.fromFile(f.path!, filename: f.filename)
          : MultipartFile.fromBytes(f.bytes ?? const [], filename: f.filename);
      form.files.add(MapEntry('$i', part));
    }
    try {
      await _dio.post(
        '${host.value}/api/upload',
        data: form,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            if (_token != null) 'Authorization': 'Bearer $_token',
            'content-type': 'multipart/form-data',
          },
          // Uploads can take a while; don't cut them off at 30s.
          sendTimeout: const Duration(minutes: 30),
          receiveTimeout: const Duration(minutes: 5),
        ),
        onSendProgress: (sent, total) {
          if (total > 0 && onProgress != null) onProgress(sent / total);
        },
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      final code = e.response?.statusCode;
      if (code == 403) {
        throw StateError('absUploadForbidden');
      }
      throw StateError(e.response?.data?.toString() ?? e.message ?? 'upload failed');
    }
    // Refresh the library so the new item shows up.
    await fetchBooks();
  }

  Future<void> fetchBooks({int page = 0, int limit = 50}) async {
    _ensureConnected();
    final libId = selectedLibraryId.value;
    if (libId.isEmpty) return;
    isLoading.value = true;
    try {
      final res = await _dio.get(
        '${host.value}/api/libraries/$libId/items',
        queryParameters: {
          'limit': limit,
          'page': page,
          'sort': 'media.metadata.title',
          'desc': '0',
          'minified': '1',
        },
        options: _authOptions,
      );
      final results = res.data is Map ? res.data['results'] : null;
      final list = <AbsBook>[];
      if (results is List) {
        for (final r in results) {
          if (r is! Map) continue;
          final media = (r['media'] is Map) ? r['media'] as Map : {};
          final meta = media['metadata'] is Map
              ? media['metadata'] as Map
              : <String, dynamic>{};
          list.add(AbsBook(
            id: r['id'].toString(),
            title: (meta['title'] ?? 'Untitled').toString(),
            author: meta['authorName']?.toString(),
            subtitle: meta['subtitle']?.toString(),
            duration: (media['duration'] as num?)?.toDouble() ??
                (r['duration'] as num?)?.toDouble(),
            progress: parseAbsProgress(r),
          ));
        }
      }
      if (page == 0) {
        books.assignAll(list);
      } else {
        books.addAll(list);
      }
      if (page == 0) await fetchInProgress();
    } finally {
      isLoading.value = false;
    }
  }

  /// Continue Listening shelf: GET /api/me/items-in-progress (or /api/me/progress).
  Future<void> fetchInProgress() async {
    if (!isConnected.value || _token == null || host.value.isEmpty) {
      inProgressBooks.clear();
      return;
    }
    try {
      dynamic data;
      try {
        final res = await _dio.get(
          '${host.value}/api/me/items-in-progress',
          queryParameters: {'limit': 25},
          options: _authOptions,
        );
        data = res.data;
      } catch (_) {
        final res = await _dio.get(
          '${host.value}/api/me/progress',
          options: _authOptions,
        );
        data = res.data;
      }

      final raw = <Map>[];
      if (data is List) {
        for (final e in data) {
          if (e is Map) raw.add(e);
        }
      } else if (data is Map) {
        final candidates =
            data['libraryItems'] ?? data['results'] ?? data['mediaProgress'];
        if (candidates is List) {
          for (final e in candidates) {
            if (e is Map) raw.add(e);
          }
        }
      }

      final scored = <MapEntry<AbsBook, int>>[];
      for (final r in raw) {
        if (r['mediaType']?.toString() == 'podcast') continue;
        if (r['episodeId'] != null) continue;
        if (r['isFinished'] == true) continue;
        if (r['hideFromContinueListening'] == true) continue;

        final id = (r['id'] ?? r['libraryItemId'])?.toString();
        if (id == null || id.isEmpty) continue;

        final media = (r['media'] is Map) ? r['media'] as Map : {};
        final meta = media['metadata'] is Map
            ? media['metadata'] as Map
            : <String, dynamic>{};
        final known = books.firstWhereOrNull((b) => b.id == id);
        final title = (meta['title'] ?? known?.title)?.toString();
        if (title == null || title.isEmpty) continue;

        final progress = parseAbsProgress(r) ?? known?.progress;
        scored.add(MapEntry(
          AbsBook(
            id: id,
            title: title,
            author: meta['authorName']?.toString() ??
                meta['author']?.toString() ??
                known?.author,
            subtitle: meta['subtitle']?.toString() ?? known?.subtitle,
            duration: (media['duration'] as num?)?.toDouble() ??
                (r['duration'] as num?)?.toDouble() ??
                known?.duration,
            progress: progress,
          ),
          (r['progressLastUpdate'] as num?)?.toInt() ??
              (r['lastUpdate'] as num?)?.toInt() ??
              0,
        ));
      }
      scored.sort((a, b) => b.value.compareTo(a.value));
      inProgressBooks.assignAll(scored.map((e) => e.key));
    } catch (_) {
      inProgressBooks.clear();
    }
  }

  Future<void> searchBooks(String query) async {
    _ensureConnected();
    final libId = selectedLibraryId.value;
    if (libId.isEmpty || query.trim().isEmpty) {
      await fetchBooks();
      return;
    }
    isLoading.value = true;
    try {
      final res = await _dio.get(
        '${host.value}/api/libraries/$libId/search',
        queryParameters: {'q': query.trim(), 'limit': 40},
        options: _authOptions,
      );
      final list = <AbsBook>[];
      final bookHits = res.data is Map ? res.data['book'] : null;
      if (bookHits is List) {
        for (final hit in bookHits) {
          if (hit is! Map) continue;
          final item = hit['libraryItem'] is Map
              ? hit['libraryItem'] as Map
              : hit;
          final meta = (item['media'] is Map)
              ? (item['media']['metadata'] as Map? ?? {})
              : <String, dynamic>{};
          list.add(AbsBook(
            id: item['id'].toString(),
            title: (meta['title'] ?? 'Untitled').toString(),
            author: meta['authorName']?.toString() ??
                (meta['authors'] is List && (meta['authors'] as List).isNotEmpty
                    ? (meta['authors'][0] is Map
                        ? meta['authors'][0]['name']?.toString()
                        : meta['authors'][0]?.toString())
                    : null),
            progress: parseAbsProgress(Map<String, dynamic>.from(item)),
          ));
        }
      }
      books.assignAll(list);
    } finally {
      isLoading.value = false;
    }
  }

  /// Start playback session and return book detail with streamable tracks.
  Future<AbsBookDetail> openBook(String itemId) async {
    _ensureConnected();
    // Metadata
    final detailRes = await _dio.get(
      '${host.value}/api/items/$itemId',
      options: _authOptions,
    );
    final d = detailRes.data as Map;
    final media = d['media'] is Map ? d['media'] as Map : {};
    final meta = media['metadata'] is Map ? media['metadata'] as Map : {};
    final title = (meta['title'] ?? 'Audiobook').toString();
    String author = meta['authorName']?.toString() ?? '';
    if (author.isEmpty && meta['authors'] is List) {
      author = (meta['authors'] as List)
          .map((a) => a is Map ? a['name'] : a)
          .whereType<String>()
          .join(', ');
    }
    final narrators = meta['narrators'] is List
        ? (meta['narrators'] as List).join(', ')
        : meta['narrator']?.toString();
    final description = meta['description']?.toString();

    // Play session → content URLs (same as Lissen)
    final playRes = await _dio.post(
      '${host.value}/api/items/$itemId/play',
      data: {
        'deviceInfo': {
          'clientName': 'Riff',
          'deviceId': 'riff-${_userId ?? "device"}',
          'deviceName': 'Riff Mobile',
        },
        'supportedMimeTypes': [
          'audio/flac',
          'audio/mpeg',
          'audio/mp4',
          'audio/ogg',
          'audio/aac',
          'audio/webm',
          'audio/x-m4a',
        ],
        'mediaPlayer': 'Riff',
        'forceTranscode': false,
        'forceDirectPlay': true,
      },
      options: _authOptions,
    );
    final session = playRes.data as Map;
    final sessionId = session['id']?.toString();
    final currentTime = (session['currentTime'] as num?)?.toDouble() ?? 0;
    final tracks = <AbsAudioTrack>[];
    final audioTracks = session['audioTracks'] as List? ?? const [];
    for (var i = 0; i < audioTracks.length; i++) {
      final t = audioTracks[i];
      if (t is! Map) continue;
      final contentUrl = t['contentUrl']?.toString();
      if (contentUrl == null || contentUrl.isEmpty) continue;
      final trackTitle = (t['title'] ??
              t['metadata']?['filename'] ??
              'Track ${i + 1}')
          .toString();
      tracks.add(AbsAudioTrack(
        index: (t['index'] as num?)?.toInt() ?? i,
        title: trackTitle,
        contentUrl: contentUrl,
        duration: (t['duration'] as num?)?.toDouble() ?? 0,
        mimeType: t['mimeType']?.toString(),
        ino: t['ino']?.toString(),
      ));
    }

    // Fallback: build file URLs from item audioFiles if session had none
    if (tracks.isEmpty && media['audioFiles'] is List) {
      final files = media['audioFiles'] as List;
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        if (f is! Map) continue;
        final ino = f['ino']?.toString();
        if (ino == null) continue;
        tracks.add(AbsAudioTrack(
          index: (f['index'] as num?)?.toInt() ?? i,
          title: (f['metaTags']?['tagTitle'] ??
                  f['metadata']?['filename'] ??
                  'Track ${i + 1}')
              .toString(),
          contentUrl: '/api/items/$itemId/file/$ino',
          duration: (f['duration'] as num?)?.toDouble() ?? 0,
          mimeType: f['mimeType']?.toString(),
          ino: ino,
        ));
      }
    }

    return AbsBookDetail(
      id: itemId,
      title: title,
      author: author,
      description: description,
      narrator: narrators,
      tracks: tracks,
      currentTime: currentTime,
      sessionId: sessionId,
    );
  }

  /// Absolute stream URL with token (query auth works for ABS file endpoints).
  String streamUrl(String contentUrl) {
    _ensureConnected();
    final path = contentUrl.startsWith('http')
        ? contentUrl
        : '${host.value}${contentUrl.startsWith('/') ? '' : '/'}$contentUrl';
    final sep = path.contains('?') ? '&' : '?';
    return '$path${sep}token=${Uri.encodeComponent(_token!)}';
  }

  String coverUrl(String itemId, {int width = 400}) {
    _ensureConnected();
    return '${host.value}/api/items/$itemId/cover?width=$width&token=${Uri.encodeComponent(_token!)}';
  }

  /// Convert book tracks into [MediaItem]s the Riff player can stream.
  /// IDs use the `abs_` prefix so [MyAudioHandler.checkNGetUrl] skips YT resolve.
  List<MediaItem> toMediaItems(AbsBookDetail book) {
    final cover = coverUrl(book.id);
    var startOffset = 0.0;
    return book.tracks.map((t) {
      final id = 'abs_${book.id}_${t.index}';
      final url = streamUrl(t.contentUrl);
      final thisStart = startOffset;
      startOffset += t.duration > 0 ? t.duration : 0;
      return MediaItem(
        id: id,
        title: t.title,
        album: book.title,
        artist: book.author.isEmpty ? 'Audiobook' : book.author,
        duration: t.duration > 0
            ? Duration(milliseconds: (t.duration * 1000).round())
            : null,
        artUri: Uri.tryParse(cover),
        extras: {
          'url': url,
          'streamSource': 'audiobookshelf',
          'absItemId': book.id,
          'absSessionId': book.sessionId,
          'absTrackIndex': t.index,
          'absStartOffsetSec': thisStart,
          'album': {'name': book.title, 'id': book.id},
          'artists': [
            {'name': book.author.isEmpty ? 'Audiobook' : book.author, 'id': null}
          ],
        },
      );
    }).toList();
  }

  /// Map ABS book-absolute [currentTimeSec] onto a track index + in-track offset.
  static (int trackIndex, Duration offset) mapCurrentTimeToTrack(
    double currentTimeSec,
    List<double> trackDurationsSec,
  ) =>
      mapAbsCurrentTimeToTrack(currentTimeSec, trackDurationsSec);

  /// Optional progress sync (Lissen: POST /api/session/{id}/sync).
  Future<void> syncProgress({
    required String sessionId,
    required double currentTime,
    required double duration,
    double timeListened = 0,
    bool isPaused = false,
  }) async {
    if (!isConnected.value || sessionId.isEmpty) return;
    try {
      await _dio.post(
        '${host.value}/api/session/$sessionId/sync',
        data: {
          'currentTime': currentTime,
          'duration': duration,
          'timeListened': timeListened,
          if (isPaused) 'isPaused': true,
        },
        options: _authOptions,
      );
    } catch (e) {
      printERROR('ABS progress sync failed: $e');
    }
  }

  /// Close a listening session (Lissen: POST /api/session/{id}/close).
  Future<void> closeSession(
    String sessionId, {
    required double currentTime,
    required double duration,
    double timeListened = 0,
  }) async {
    if (!isConnected.value || sessionId.isEmpty) return;
    try {
      await _dio.post(
        '${host.value}/api/session/$sessionId/close',
        data: {
          'currentTime': currentTime,
          'duration': duration,
          'timeListened': timeListened,
        },
        options: _authOptions,
      );
    } catch (e) {
      printERROR('ABS session close failed: $e');
    }
  }

  void _ensureConnected() {
    if (!isConnected.value || _token == null || host.value.isEmpty) {
      throw StateError('Not connected to Audiobookshelf');
    }
  }
}
