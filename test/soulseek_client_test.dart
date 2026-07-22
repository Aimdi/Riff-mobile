import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/soulseek/slsk_message.dart';
import 'package:harmonymusic/services/soulseek/soulseek_client.dart';

void main() {
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
