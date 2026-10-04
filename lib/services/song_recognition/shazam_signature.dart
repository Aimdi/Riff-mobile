import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

/// Shazam audio signature, ported to Dart from SongRec
/// (https://github.com/marin-m/SongRec, GPL-3.0) by way of Audire's
/// shazam-signature-jni (https://github.com/alexmercerind/audire, GPL-3.0).
///
/// Input: signed 16-bit mono PCM at 16 kHz. Output: the
/// `data:audio/vnd.shazam.sig;base64,…` URI Shazam's tag endpoint takes.
/// Pure Dart, so it runs anywhere (and in an isolate) without a native
/// library.
class ShazamSignature {
  ShazamSignature._();

  static const int sampleRate = 16000;
  static const String uriPrefix = 'data:audio/vnd.shazam.sig;base64,';

  /// Builds the signature URI for [samples].
  static String fromPcm16(Int16List samples) =>
      uriPrefix + base64.encode(encode(generate(samples), samples.length));

  /// Peaks per frequency band (0: 250–520 Hz … 3: 3500–5500 Hz).
  static Map<int, List<FrequencyPeak>> generate(Int16List samples) {
    final g = _Generator();
    final chunks = samples.length ~/ 128;
    for (var c = 0; c < chunks; c++) {
      g.doFft(samples, c * 128);
      g.doPeakSpreading();
      g.spreadFftsDone++;
      if (g.spreadFftsDone >= 46) g.doPeakRecognition();
    }
    return g.peaks;
  }

  /// Binary signature (header, per-band peak lists, CRC32).
  static Uint8List encode(
      Map<int, List<FrequencyPeak>> bandPeaks, int numberSamples) {
    final out = BytesBuilder();
    void u32(int v) =>
        out.add((ByteData(4)..setUint32(0, v & 0xffffffff, Endian.little))
            .buffer
            .asUint8List());

    u32(0xcafe2580);
    u32(0); // CRC32, patched below
    u32(0); // size minus header, patched below
    u32(0x94119c00);
    u32(0);
    u32(0);
    u32(0);
    u32(3 << 27); // 16000 Hz
    u32(0);
    u32(0);
    u32(numberSamples + (sampleRate * 0.24).toInt());
    u32((15 << 19) + 0x40000);
    u32(0x40000000);
    u32(0); // size minus header, patched below

    final bands = bandPeaks.keys.toList()..sort();
    for (final band in bands) {
      final peaks = BytesBuilder();
      var pass = 0;
      for (final p in bandPeaks[band]!) {
        if (p.fftPassNumber - pass >= 255) {
          peaks.addByte(0xff);
          peaks.add((ByteData(4)..setUint32(0, p.fftPassNumber, Endian.little))
              .buffer
              .asUint8List());
          pass = p.fftPassNumber;
        }
        peaks.addByte(p.fftPassNumber - pass);
        peaks.add((ByteData(4)
              ..setUint16(0, p.magnitude, Endian.little)
              ..setUint16(2, p.correctedBin, Endian.little))
            .buffer
            .asUint8List());
        pass = p.fftPassNumber;
      }
      final bytes = peaks.toBytes();
      u32(0x60030040 + band);
      u32(bytes.length);
      out.add(bytes);
      final pad = (4 - bytes.length % 4) % 4;
      for (var i = 0; i < pad; i++) {
        out.addByte(0);
      }
    }

    final buf = out.toBytes();
    final data = ByteData.sublistView(buf);
    data.setUint32(8, buf.length - 48, Endian.little);
    data.setUint32(48 + 4, buf.length - 48, Endian.little);
    data.setUint32(4, getCrc32(buf.sublist(8)), Endian.little);
    return buf;
  }
}

/// One spectral peak in the signature.
class FrequencyPeak {
  const FrequencyPeak(this.fftPassNumber, this.magnitude, this.correctedBin);
  final int fftPassNumber;
  final int magnitude;
  final int correctedBin;
}

/// numpy.hanning(2050)[1:-1], as SongRec uses.
final Float64List _hanning = Float64List.fromList([
  for (var i = 0; i < 2048; i++)
    0.5 - 0.5 * math.cos(2 * math.pi * (i + 1) / 2049)
]);

class _Generator {
  final Int16List ring = Int16List(2048);
  int ringIndex = 0;

  final List<Float64List> fftOutputs =
      List.generate(256, (_) => Float64List(1025));
  int fftIndex = 0;

  final List<Float64List> spreadOutputs =
      List.generate(256, (_) => Float64List(1025));
  int spreadIndex = 0;

  int spreadFftsDone = 0;

  final Map<int, List<FrequencyPeak>> peaks = {};

  final Float64List _re = Float64List(2048);
  final Float64List _im = Float64List(2048);

  void doFft(Int16List samples, int offset) {
    for (var i = 0; i < 128; i++) {
      ring[ringIndex + i] = samples[offset + i];
    }
    ringIndex = (ringIndex + 128) & 2047;

    for (var i = 0; i < 2048; i++) {
      _re[i] = ring[(i + ringIndex) & 2047] * _hanning[i];
      _im[i] = 0;
    }
    _fft(_re, _im);

    final out = fftOutputs[fftIndex];
    for (var i = 0; i <= 1024; i++) {
      final v = (_re[i] * _re[i] + _im[i] * _im[i]) / (1 << 17);
      out[i] = v < 1e-10 ? 1e-10 : v;
    }
    fftIndex = (fftIndex + 1) & 255;
  }

  void doPeakSpreading() {
    final real = fftOutputs[(fftIndex - 1) & 255];
    final spread = spreadOutputs[spreadIndex];
    spread.setAll(0, real);
    for (var p = 0; p <= 1022; p++) {
      spread[p] = math.max(spread[p], math.max(spread[p + 1], spread[p + 2]));
    }
    final copy = Float64List.fromList(spread);
    for (final former in const [1, 3, 6]) {
      final f = spreadOutputs[(spreadIndex - former) & 255];
      for (var p = 0; p <= 1024; p++) {
        if (copy[p] > f[p]) f[p] = copy[p];
      }
    }
    spreadIndex = (spreadIndex + 1) & 255;
  }

  static double _mag(double v) =>
      math.max(math.log(v), 1.0 / 64.0) * 1477.3 + 6144.0;

  void doPeakRecognition() {
    final m46 = fftOutputs[(fftIndex - 46) & 255];
    final m49 = spreadOutputs[(spreadIndex - 49) & 255];

    for (var bin = 10; bin <= 1014; bin++) {
      final v = m46[bin];
      if (v < 1.0 / 64.0 || v < m49[bin - 1]) continue;

      var maxNeighbor = 0.0;
      for (final o in const [-10, -7, -4, -3, 1, 2, 5, 8]) {
        maxNeighbor = math.max(maxNeighbor, m49[bin + o]);
      }
      if (v <= maxNeighbor) continue;

      var maxOther = maxNeighbor;
      for (final o in const [
        -53,
        -45,
        165,
        172,
        179,
        186,
        193,
        200,
        214,
        221,
        228,
        235,
        242,
        249
      ]) {
        maxOther =
            math.max(maxOther, spreadOutputs[(spreadIndex + o) & 255][bin - 1]);
      }
      if (v <= maxOther) continue;

      final pass = spreadFftsDone - 46;
      final magnitude = _mag(v);
      final before = _mag(m46[bin - 1]);
      final after = _mag(m46[bin + 1]);
      final variation1 = magnitude * 2 - before - after;
      final variation2 = (after - before) * 32 / variation1;
      // Rust `as u16`: truncates toward zero, saturating to 0..65535.
      final v2 = variation2.isNaN ? 0 : variation2.truncate().clamp(0, 65535);
      final corrected = (bin * 64 + v2) & 0xffff;
      final hz = corrected * (16000.0 / 2.0 / 1024.0 / 64.0);
      final int band;
      final h = hz.truncate();
      if (h >= 250 && h <= 519) {
        band = 0;
      } else if (h >= 520 && h <= 1449) {
        band = 1;
      } else if (h >= 1450 && h <= 3499) {
        band = 2;
      } else if (h >= 3500 && h <= 5500) {
        band = 3;
      } else {
        continue;
      }
      (peaks[band] ??= []).add(
          FrequencyPeak(pass, magnitude.truncate().clamp(0, 65535), corrected));
    }
  }

  /// In-place iterative radix-2 FFT (length 2048).
  static void _fft(Float64List re, Float64List im) {
    final n = re.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final ang = -2 * math.pi / len;
      final wr = math.cos(ang), wi = math.sin(ang);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0, ci = 0.0;
        for (var k = 0; k < len ~/ 2; k++) {
          final ar = re[i + k], ai = im[i + k];
          final br = re[i + k + len ~/ 2], bi = im[i + k + len ~/ 2];
          final tr = br * cr - bi * ci, ti = br * ci + bi * cr;
          re[i + k] = ar + tr;
          im[i + k] = ai + ti;
          re[i + k + len ~/ 2] = ar - tr;
          im[i + k + len ~/ 2] = ai - ti;
          final ncr = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = ncr;
        }
      }
    }
  }
}
