import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'slsk_message.dart';

/// One audio hit from a Soulseek network search.
class SoulseekFile {
  const SoulseekFile({
    required this.username,
    required this.filename,
    required this.size,
    required this.hasFreeSlot,
    required this.speed,
    this.bitRate,
    this.lengthSeconds,
  });

  final String username;
  final String filename;
  final int size;
  final bool hasFreeSlot;
  final int speed;
  final int? bitRate;
  final int? lengthSeconds;

  List<String> get pathParts {
    final normalized = filename.replaceAll('/', '\\');
    return normalized
        .split('\\')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String get displayName {
    final parts = pathParts;
    final base = parts.isEmpty ? filename : parts.last;
    return base.trim().isEmpty ? filename : base;
  }

  /// Parent folder path (everything except the file name).
  String get folderPath {
    final parts = pathParts;
    if (parts.length <= 1) return '';
    return parts.sublist(0, parts.length - 1).join('/');
  }

  /// Leaf folder name used for album grouping.
  String get folderName {
    final parts = pathParts;
    if (parts.length <= 1) return username;
    return parts[parts.length - 2];
  }

  String get extension {
    final base = displayName;
    final dot = base.lastIndexOf('.');
    if (dot < 0) return '';
    return base.substring(dot + 1).toLowerCase();
  }

  String get sizeLabel {
    if (size <= 0) return '—';
    const kb = 1000.0;
    const mb = kb * 1000;
    const gb = mb * 1000;
    if (size >= gb) return '${(size / gb).toStringAsFixed(2)} GB';
    if (size >= mb) return '${(size / mb).toStringAsFixed(1)} MB';
    if (size >= kb) return '${(size / kb).toStringAsFixed(0)} KB';
    return '$size B';
  }

  String get lengthLabel {
    if (lengthSeconds == null || lengthSeconds! <= 0) return '';
    final m = lengthSeconds! ~/ 60;
    final s = lengthSeconds! % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get metaLabel {
    final bits = <String>[sizeLabel];
    if (bitRate != null && bitRate! > 0) bits.add('${bitRate}kbps');
    final len = lengthLabel;
    if (len.isNotEmpty) bits.add(len);
    if (hasFreeSlot) bits.add('slot');
    bits.add(username);
    return bits.join(' · ');
  }
}

class SoulseekException implements Exception {
  SoulseekException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Direct Soulseek network client (login, search, download) — no remote
/// slskd/server required. Protocol inspired by [slsk-client](https://github.com/f-hj/slsk-client)
/// and the Nicotine+ docs.
class SoulseekClient {
  SoulseekClient({
    this.host = 'server.slsknet.org',
    this.port = 2242,
    this.listenPort = 2234,
  });

  final String host;
  final int port;
  final int listenPort;

  static const _audioExt = {
    'mp3',
    'flac',
    'm4a',
    'aac',
    'ogg',
    'opus',
    'wav',
    'wma',
    'aiff',
    'alac',
  };

  Socket? _server;
  ServerSocket? _listener;
  final _framer = SlskMessageFramer();
  final _peers = <String, _PeerConn>{};
  final _searchCallbacks = <String, void Function(SoulseekFile)>{};
  final _downloadByToken = <String, _DownloadJob>{};
  final _downloadByKey = <String, _DownloadJob>{};

  String? username;
  bool get isConnected => _server != null;
  bool loggedIn = false;

  Completer<void>? _loginCompleter;

  Future<void> connectAndLogin({
    required String user,
    required String pass,
  }) async {
    await disconnect();
    username = user.trim();
    final password = pass;
    if (username!.isEmpty || password.isEmpty) {
      throw SoulseekException('Username and password are required');
    }

    try {
      _listener = await ServerSocket.bind(InternetAddress.anyIPv4, listenPort);
      _listener!.listen(_onIncomingPeer);
    } catch (_) {
      // Listening is best-effort (NAT / permission). Search still works.
      _listener = null;
    }

    _server = await Socket.connect(host, port,
        timeout: const Duration(seconds: 20));
    _server!.listen(
      _onServerData,
      onError: (_) {},
      onDone: () {
        loggedIn = false;
      },
      cancelOnError: false,
    );

    _loginCompleter = Completer<void>();
    final hash = md5.convert(utf8.encode('$username$password')).toString();
    // Client version fields: unique-ish minor for Riff (see Soulseek.NET notes).
    _sendServer(
      SlskWriter()
          .write32(1) // Login
          .writeStr(username!)
          .writeStr(password)
          .write32(160)
          .writeStr(hash)
          .write32(42),
    );
    _sendServer(SlskWriter().write32(2).write32(listenPort)); // SetWaitPort

    await _loginCompleter!.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () => throw SoulseekException('Login timed out'),
    );
  }

  Future<void> disconnect() async {
    loggedIn = false;
    for (final p in _peers.values.toList()) {
      p.destroy();
    }
    _peers.clear();
    _searchCallbacks.clear();
    await _server?.close();
    _server = null;
    await _listener?.close();
    _listener = null;
    _framer.reset();
  }

  /// Search the network. Collects results for [timeout], then returns.
  ///
  /// When [onHit] is set, it is invoked for each new audio hit as peers
  /// respond (sockseek-style live results). Final list is still returned.
  Future<List<SoulseekFile>> search(
    String query, {
    Duration timeout = const Duration(seconds: 8),
    void Function(SoulseekFile hit)? onHit,
  }) async {
    if (!loggedIn || _server == null) {
      throw SoulseekException('Not logged in');
    }
    final q = query.trim();
    if (q.isEmpty) return [];

    final token = _randomToken();
    final results = <SoulseekFile>[];
    final seen = <String>{};

    _searchCallbacks[token] = (hit) {
      if (!_audioExt.contains(hit.extension)) return;
      final key = '${hit.username}|${hit.filename}';
      if (!seen.add(key)) return;
      results.add(hit);
      onHit?.call(hit);
    };

    _sendServer(
      SlskWriter()
          .write32(26)
          .writeRawHex(token)
          .writeStr(q),
    );

    await Future<void>.delayed(timeout);
    _searchCallbacks.remove(token);

    results.sort((a, b) {
      final slot = (b.hasFreeSlot ? 1 : 0).compareTo(a.hasFreeSlot ? 1 : 0);
      if (slot != 0) return slot;
      final br = (b.bitRate ?? 0).compareTo(a.bitRate ?? 0);
      if (br != 0) return br;
      return b.speed.compareTo(a.speed);
    });
    return results;
  }

  // Fix: use proper writer for file search
  void _sendServer(SlskWriter w) {
    _server?.add(w.toPacket());
  }

  Future<File> download(
    SoulseekFile file, {
    required String saveDirectory,
    void Function(double progress)? onProgress,
  }) async {
    if (!loggedIn) throw SoulseekException('Not logged in');
    Directory(saveDirectory).createSync(recursive: true);

    var peer = _peers[file.username];
    if (peer == null || peer.host == null || peer.port == null) {
      final addr = Completer<_PeerAddr>();
      late void Function(_PeerAddr) handler;
      handler = (a) {
        if (a.user == file.username && !addr.isCompleted) {
          addr.complete(a);
        }
      };
      _peerAddressWaiters.add(handler);
      _sendServer(SlskWriter().write32(3).writeStr(file.username));
      final resolved = await addr.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw SoulseekException(
          'Could not reach peer ${file.username}',
        ),
      );
      _peerAddressWaiters.remove(handler);
      peer = await _connectPeer(resolved.user, resolved.host, resolved.port);
    }

    final token = _randomToken();
    final completer = Completer<File>();
    final destName = _safeFileName(file.displayName);
    final destPath = p.join(saveDirectory, destName);
    final job = _DownloadJob(
      user: file.username,
      filename: file.filename,
      size: file.size,
      token: token,
      savePath: destPath,
      completer: completer,
      onProgress: onProgress,
    );
    _downloadByToken[token] = job;
    _downloadByKey['${file.username}_${file.filename}'] = job;

    peer.send(
      SlskWriter()
          .write32(40) // TransferRequest
          .write32(0) // download direction
          .writeRawHex(token)
          .writeStr(file.filename)
          .toPacket(),
    );

    return completer.future.timeout(
      const Duration(minutes: 30),
      onTimeout: () {
        _downloadByToken.remove(token);
        throw SoulseekException('Download timed out');
      },
    );
  }

  final _peerAddressWaiters = <void Function(_PeerAddr)>[];

  void _onServerData(Uint8List data) {
    for (final frame in _framer.push(data)) {
      _handleServerFrame(frame);
    }
  }

  void _handleServerFrame(Uint8List frame) {
    try {
      final msg = SlskReader(frame);
      final size = msg.read32();
      if (size < 4) return;
      final code = msg.read32();
      switch (code) {
        case 1: // Login
          final success = msg.read8();
          if (success == 1) {
            loggedIn = true;
            _sendServer(SlskWriter().write32(35).write32(1).write32(1));
            _sendServer(SlskWriter().write32(71).write32(1)); // HaveNoParents
            _sendServer(SlskWriter().write32(28).write32(2)); // Online
            _loginCompleter?.complete();
          } else {
            final reason = msg.readStr();
            loggedIn = false;
            _loginCompleter?.completeError(SoulseekException(reason));
          }
          _loginCompleter = null;
          break;
        case 3: // GetPeerAddress
          final user = msg.readStr();
          final ip = [
            msg.read8(),
            msg.read8(),
            msg.read8(),
            msg.read8(),
          ];
          final host = '${ip[3]}.${ip[2]}.${ip[1]}.${ip[0]}';
          final peerPort = msg.read32();
          final addr = _PeerAddr(user, host, peerPort);
          for (final w in List.of(_peerAddressWaiters)) {
            w(addr);
          }
          break;
        case 18: // ConnectToPeer
          final user = msg.readStr();
          final type = msg.readStr();
          final ip = [
            msg.read8(),
            msg.read8(),
            msg.read8(),
            msg.read8(),
          ];
          final host = '${ip[3]}.${ip[2]}.${ip[1]}.${ip[0]}';
          final peerPort = msg.read32();
          final token = msg.readRawHex(4);
          unawaited(_handleConnectToPeer(user, type, host, peerPort, token));
          break;
        case 102: // NetInfo — search parents
          final n = msg.read32();
          for (var i = 0; i < n; i++) {
            final user = msg.readStr();
            final ip = [
              msg.read8(),
              msg.read8(),
              msg.read8(),
              msg.read8(),
            ];
            final host = '${ip[3]}.${ip[2]}.${ip[1]}.${ip[0]}';
            final peerPort = msg.read32();
            _sendServer(
              SlskWriter()
                  .write32(73)
                  .write8(ip[0])
                  .write8(ip[1])
                  .write8(ip[2])
                  .write8(ip[3]),
            );
            unawaited(_handleConnectToPeer(
              user,
              'D',
              host,
              peerPort,
              _randomToken(),
            ));
          }
          break;
        default:
          break;
      }
    } catch (_) {/* ignore malformed */}
  }

  Future<void> _handleConnectToPeer(
    String user,
    String type,
    String host,
    int peerPort,
    String token,
  ) async {
    if (type == 'F') {
      unawaited(_downloadPeerFile(
        host: host,
        port: peerPort,
        token: token,
        user: user,
        pierce: true,
      ));
      return;
    }
    try {
      await _connectPeer(user, host, peerPort, token: token, type: type);
    } catch (_) {}
  }

  Future<_PeerConn> _connectPeer(
    String user,
    String host,
    int peerPort, {
    String? token,
    String type = 'P',
  }) async {
    final existing = _peers[user];
    if (existing != null && !existing.destroyed) {
      existing.host = host;
      existing.port = peerPort;
      return existing;
    }
    final socket = await Socket.connect(
      host,
      peerPort,
      timeout: const Duration(seconds: 12),
    );
    final peer = _PeerConn(
      socket: socket,
      user: user,
      host: host,
      port: peerPort,
      onSearchResult: _onPeerSearchResult,
      onTransferResponse: _onTransferResponse,
      onTransferRequest: _onTransferRequest,
    );
    _peers[user] = peer;
    if (token != null) {
      // Pierce firewall / init: 5-byte header used by slsk-client
      final pierce = Uint8List.fromList([
        0x05, 0x00, 0x00, 0x00, 0x00,
        ..._hexToBytes(token),
      ]);
      socket.add(pierce);
    }
    return peer;
  }

  void _onIncomingPeer(Socket socket) {
    // Minimal accept — full reverse connections need PeerInit parsing.
    socket.listen((_) {}, onError: (_) {}, onDone: () {});
  }

  void _onPeerSearchResult(String token, List<SoulseekFile> files) {
    final cb = _searchCallbacks[token];
    if (cb == null) return;
    for (final f in files) {
      cb(f);
    }
  }

  void _onTransferRequest(_PeerConn peer, String token, String file, int dir) {
    // Peer wants to send us a file (dir==1) after we requested.
    final job = _downloadByToken[token];
    if (job != null && dir == 1) {
      // already tracked
    }
    peer.send(
      SlskWriter().write32(41).writeRawHex(token).write8(1).toPacket(),
    );
  }

  void _onTransferResponse(_PeerConn peer, String token, bool allowed) {
    final job = _downloadByToken[token];
    if (job == null) return;
    if (!allowed) {
      // Queue — wait for TransferRequest from peer
      return;
    }
    if (peer.host != null && peer.port != null) {
      unawaited(_downloadPeerFile(
        host: peer.host!,
        port: peer.port!,
        token: token,
        user: peer.user,
        pierce: false,
      ));
    }
  }

  Future<void> _downloadPeerFile({
    required String host,
    required int port,
    required String token,
    required String user,
    required bool pierce,
  }) async {
    final job = _downloadByToken[token];
    if (job == null) return;

    Socket socket;
    try {
      socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 15));
    } catch (e) {
      if (!job.completer.isCompleted) {
        job.completer.completeError(
          SoulseekException('Peer connection failed'),
        );
      }
      return;
    }

    if (pierce) {
      socket.add(SlskWriter().write8(0).writeRawHex(token).toPacket());
    } else {
      socket.add(
        SlskWriter()
            .write8(1)
            .writeStr(username ?? '')
            .writeStr('F')
            .writeRawHex(token)
            .toPacket(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      socket.add(Uint8List(8)); // 8 zero bytes
    }

    final builder = BytesBuilder(copy: false);
    var started = pierce;
    late StreamSubscription sub;
    sub = socket.listen(
      (data) {
        if (!started && !pierce) {
          // first chunk may be token ack
          started = true;
          if (data.length <= 4) {
            socket.add(Uint8List(8));
            return;
          }
        }
        if (!pierce && builder.isEmpty && data.length <= 8) {
          socket.add(Uint8List(8));
        }
        builder.add(data);
        final got = builder.length;
        if (job.size > 0) {
          job.onProgress?.call((got / job.size).clamp(0.0, 1.0));
        }
        if (job.size > 0 && got >= job.size) {
          unawaited(sub.cancel());
          unawaited(socket.close());
        }
      },
      onDone: () => _finishDownload(job, builder.toBytes()),
      onError: (e) {
        if (!job.completer.isCompleted) {
          job.completer.completeError(SoulseekException('$e'));
        }
      },
      cancelOnError: true,
    );
  }

  void _finishDownload(_DownloadJob job, Uint8List bytes) {
    try {
      final file = File(job.savePath);
      file.writeAsBytesSync(bytes);
      if (!job.completer.isCompleted) job.completer.complete(file);
    } catch (e) {
      if (!job.completer.isCompleted) {
        job.completer.completeError(SoulseekException('$e'));
      }
    } finally {
      _downloadByToken.remove(job.token);
      _downloadByKey.remove('${job.user}_${job.filename}');
    }
  }

  static String _randomToken() {
    final r = Random.secure();
    final b = List<int>.generate(4, (_) => r.nextInt(256));
    return b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _safeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
}


class _PeerAddr {
  _PeerAddr(this.user, this.host, this.port);
  final String user;
  final String host;
  final int port;
}

class _DownloadJob {
  _DownloadJob({
    required this.user,
    required this.filename,
    required this.size,
    required this.token,
    required this.savePath,
    required this.completer,
    this.onProgress,
  });

  final String user;
  final String filename;
  final int size;
  final String token;
  final String savePath;
  final Completer<File> completer;
  final void Function(double progress)? onProgress;
}

class _PeerConn {
  _PeerConn({
    required this.socket,
    required this.user,
    this.host,
    this.port,
    required this.onSearchResult,
    required this.onTransferResponse,
    required this.onTransferRequest,
  }) {
    socket.listen(
      (data) {
        for (final frame in _framer.push(data)) {
          _handle(frame);
        }
      },
      onError: (_) => destroy(),
      onDone: destroy,
    );
  }

  final Socket socket;
  final String user;
  String? host;
  int? port;
  final void Function(String token, List<SoulseekFile> files) onSearchResult;
  final void Function(_PeerConn peer, String token, bool allowed)
      onTransferResponse;
  final void Function(_PeerConn peer, String token, String file, int dir)
      onTransferRequest;

  final _framer = SlskMessageFramer();
  bool destroyed = false;

  void send(Uint8List packet) {
    if (!destroyed) socket.add(packet);
  }

  void destroy() {
    if (destroyed) return;
    destroyed = true;
    socket.destroy();
  }

  void _handle(Uint8List frame) {
    try {
      final msg = SlskReader(frame);
      final size = msg.read32();
      if (size <= 4) return;
      final code = msg.read32();
      switch (code) {
        case 4: // GetSharedFileList — send empty-ish list
          send(
            SlskWriter()
                .write32(5)
                .write32(0)
                .toPacket(),
          );
          break;
        case 9: // FileSearchResult (zlib)
          final content = frame.sublist(msg.pointer, size + 4);
          final inflated = zlib.decode(content);
          final parsed = _parseSearchResult(Uint8List.fromList(inflated));
          if (parsed != null) {
            onSearchResult(parsed.token, parsed.files);
          }
          break;
        case 40: // TransferRequest
          final dir = msg.read32();
          final token = msg.readRawHex(4);
          final file = msg.readStr();
          onTransferRequest(this, token, file, dir);
          break;
        case 41: // TransferResponse
          final token = msg.readRawHex(4);
          final allowed = msg.read8() == 1;
          onTransferResponse(this, token, allowed);
          break;
        default:
          break;
      }
    } catch (_) {}
  }

  static ({String token, List<SoulseekFile> files})? _parseSearchResult(
    Uint8List buffer,
  ) {
    try {
      final msg = SlskReader(buffer);
      final user = msg.readStr();
      final token = msg.readRawHex(4);
      final nb = msg.read32();
      final files = <SoulseekFile>[];
      for (var i = 0; i < nb; i++) {
        msg.read8();
        final filename = msg.readStr();
        final size = msg.read32();
        msg.read32(); // size high
        msg.readStr(); // ext
        final nbAttr = msg.read32();
        int? bitRate;
        int? length;
        for (var a = 0; a < nbAttr; a++) {
          final code = msg.read32();
          final val = msg.read32();
          if (code == 0) bitRate = val;
          if (code == 1) length = val;
        }
        files.add(
          SoulseekFile(
            username: user,
            filename: filename,
            size: size,
            hasFreeSlot: false,
            speed: 0,
            bitRate: bitRate,
            lengthSeconds: length,
          ),
        );
      }
      final slots = msg.read8();
      final speed = msg.read32();
      return (
        token: token,
        files: files
            .map(
              (f) => SoulseekFile(
                username: f.username,
                filename: f.filename,
                size: f.size,
                hasFreeSlot: slots == 1,
                speed: speed,
                bitRate: f.bitRate,
                lengthSeconds: f.lengthSeconds,
              ),
            )
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }
}
