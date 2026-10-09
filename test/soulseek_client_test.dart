import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/soulseek/slsk_message.dart';
import 'package:harmonymusic/services/soulseek/soulseek_client.dart';
import 'package:path/path.dart' as p;

/// A free local TCP port (bound and released again).
Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

void main() {
  group('file transfer', () {
    late Directory tmp;
    late ServerSocket peer;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('slsk_dl');
      peer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    });
    tearDown(() async {
      await peer.close();
      tmp.deleteSync(recursive: true);
    });

    final payload =
        Uint8List.fromList(List.generate(300 * 1024, (i) => (i * 7) & 0xff));

    test(
        'finishes when the whole file has arrived, even if the peer keeps '
        'the connection open', () async {
      final held = <Socket>[];
      peer.listen((s) {
        held.add(s);
        s.add(payload); // and never close
      });
      final dest = p.join(tmp.path, 'song.flac');
      final file = await SoulseekClient()
          .debugReceiveFile(
              host: '127.0.0.1',
              port: peer.port,
              savePath: dest,
              size: payload.length)
          .timeout(const Duration(seconds: 10));
      expect(file.path, dest);
      expect(await file.readAsBytes(), payload);
      // Only the finished file is left behind, no part files.
      expect(tmp.listSync().map((e) => p.basename(e.path)), ['song.flac']);
      for (final s in held) {
        s.destroy();
      }
    });

    test('a transfer cut short is an error, not a truncated file', () async {
      peer.listen((s) async {
        s.add(payload.sublist(0, 1000));
        await s.flush();
        await s.close();
      });
      final dest = p.join(tmp.path, 'cut.flac');
      await expectLater(
          SoulseekClient()
              .debugReceiveFile(
                  host: '127.0.0.1',
                  port: peer.port,
                  savePath: dest,
                  size: payload.length)
              .timeout(const Duration(seconds: 10)),
          throwsA(isA<SoulseekException>()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(tmp.listSync(), isEmpty);
    });
  });

  test('a failed login closes the server socket and frees the listen port',
      () async {
    // A "server" that hangs up straight away.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) => s.destroy());
    final listenPort = await _freePort();
    final client = SoulseekClient(
        host: '127.0.0.1', port: server.port, listenPort: listenPort);

    final watch = Stopwatch()..start();
    await expectLater(client.connectAndLogin(user: 'u', pass: 'p'),
        throwsA(isA<SoulseekException>()));
    // Fails as soon as the server hangs up, not after the 25 s timeout.
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    expect(client.isConnected, isFalse);
    expect(client.loggedIn, isFalse);
    // The peer listener is gone: the port can be bound again.
    final again = await ServerSocket.bind(InternetAddress.anyIPv4, listenPort);
    await again.close();
    await server.close();
  });

  test('an unreachable server frees the listen port too', () async {
    final deadPort = await _freePort();
    final listenPort = await _freePort();
    final client = SoulseekClient(
        host: '127.0.0.1', port: deadPort, listenPort: listenPort);
    await expectLater(
        client.connectAndLogin(user: 'u', pass: 'p'), throwsA(anything));
    final again = await ServerSocket.bind(InternetAddress.anyIPv4, listenPort);
    await again.close();
  });

  test('SlskWriter frames packets with little-endian length', () {
    final packet = SlskWriter().write32(26).writeStr('hi').toPacket();
    final len = ByteData.sublistView(packet, 0, 4).getUint32(0, Endian.little);
    expect(len, packet.length - 4);
    final reader = SlskReader(packet);
    expect(reader.read32(), len);
    expect(reader.read32(), 26);
    expect(reader.readStr(), 'hi');
  });

  test('SlskMessageFramer reassembles split chunks', () {
    final packet = SlskWriter().write32(1).writeStr('ok').toPacket();
    final framer = SlskMessageFramer();
    final mid = packet.length ~/ 2;
    expect(framer.push(packet.sublist(0, mid)), isEmpty);
    final frames = framer.push(packet.sublist(mid));
    expect(frames.length, 1);
    expect(frames.first, packet);
  });

  test('SoulseekFile display helpers', () {
    const hit = SoulseekFile(
      username: 'alice',
      filename: r'@@alice\Music\Song.flac',
      size: 12 * 1000 * 1000,
      hasFreeSlot: true,
      speed: 100,
      bitRate: 320,
      lengthSeconds: 200,
    );
    expect(hit.displayName, 'Song.flac');
    expect(hit.extension, 'flac');
    expect(hit.metaLabel, contains('alice'));
    expect(hit.metaLabel, contains('slot'));
  });
}
