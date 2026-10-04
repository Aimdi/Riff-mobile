import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/song_recognition/shazam_signature.dart';

/// 10 s of deterministic "music": two note lines, a sweep and noise.
Int16List testSignal() {
  const n = 16000 * 10;
  final s = Int16List(n);
  final rnd = math.Random(7);
  final notes = [
    262.0,
    330.0,
    392.0,
    523.0,
    659.0,
    784.0,
    1046.0,
    1568.0,
    2093.0,
    3136.0,
    4186.0
  ];
  for (var i = 0; i < n; i++) {
    final t = i / 16000;
    final step = (t * 4).floor();
    final f1 = notes[step % notes.length];
    final f2 = notes[(step * 3 + 2) % notes.length];
    final v = 6000 * math.sin(2 * math.pi * f1 * t) +
        4000 * math.sin(2 * math.pi * f2 * t) +
        2500 * math.sin(2 * math.pi * (300 + 900 * (t % 1)) * t) +
        (rnd.nextDouble() - 0.5) * 800;
    s[i] = v.round().clamp(-32768, 32767);
  }
  return s;
}

/// Band -> peaks (pass, magnitude, bin) decoded from a signature URI.
Map<int, List<List<int>>> decode(String uri) {
  final b = base64.decode(uri.substring(ShazamSignature.uriPrefix.length));
  final d = ByteData.sublistView(b);
  final out = <int, List<List<int>>>{};
  var i = 56;
  while (i < b.length) {
    final band = d.getUint32(i, Endian.little) - 0x60030040;
    final size = d.getUint32(i + 4, Endian.little);
    i += 8;
    var j = i, pass = 0;
    final peaks = <List<int>>[];
    while (j < i + size) {
      if (b[j] == 0xff) {
        pass = d.getUint32(j + 1, Endian.little);
        j += 5;
        continue;
      }
      pass += b[j];
      peaks.add([
        pass,
        d.getUint16(j + 1, Endian.little),
        d.getUint16(j + 3, Endian.little)
      ]);
      j += 5;
    }
    out[band] = peaks;
    i += size + (4 - size % 4) % 4;
  }
  return out;
}

void main() {
  test('header, sizes and CRC32 are well formed', () {
    final uri = ShazamSignature.fromPcm16(testSignal());
    expect(uri, startsWith(ShazamSignature.uriPrefix));
    final b = base64.decode(uri.substring(ShazamSignature.uriPrefix.length));
    final d = ByteData.sublistView(b);
    expect(d.getUint32(0, Endian.little), 0xcafe2580);
    expect(d.getUint32(8, Endian.little), b.length - 48);
    expect(d.getUint32(52, Endian.little), b.length - 48);
    expect(d.getUint32(4, Endian.little), getCrc32(b.sublist(8)));
    expect(d.getUint32(28, Endian.little), 3 << 27); // 16 kHz
    expect(d.getUint32(40, Endian.little), 160000 + 3840);
  });

  test('matches the SongRec/Audire Rust signature (peak for peak)', () {
    final ref = decode(File('test/fixtures/shazam_signature_reference.txt')
        .readAsStringSync()
        .trim());
    final got = decode(ShazamSignature.fromPcm16(testSignal()));
    expect(got.keys.toSet(), ref.keys.toSet());
    // Rust works in f32 and this port in f64, so a peak right at a
    // threshold can flip, and the interpolated frequency (1/64 bin) and
    // magnitude can differ by 1. Shazam matching tolerates far more; require
    // 98% of the reference peaks to be found here.
    for (final band in ref.keys) {
      final r = ref[band]!, g = got[band]!;
      expect((g.length - r.length).abs(), lessThanOrEqualTo(r.length ~/ 50 + 1),
          reason: 'band $band peak count');
      var matched = 0;
      for (final p in r) {
        if (g.any((q) =>
            q[0] == p[0] &&
            (q[1] - p[1]).abs() <= 1 &&
            (q[2] - p[2]).abs() <= 1)) {
          matched++;
        }
      }
      expect(matched / r.length, greaterThanOrEqualTo(0.98),
          reason: 'band $band: $matched of ${r.length} peaks match');
    }
  });

  test('silence gives an empty but valid signature', () {
    final uri = ShazamSignature.fromPcm16(Int16List(16000 * 3));
    expect(decode(uri), isEmpty);
  });
}
