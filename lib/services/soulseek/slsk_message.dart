import 'dart:convert';
import 'dart:typed_data';

/// Binary writer for Soulseek protocol messages (little-endian).
class SlskWriter {
  final BytesBuilder _buf = BytesBuilder(copy: false);

  SlskWriter write8(int val) {
    _buf.addByte(val & 0xff);
    return this;
  }

  SlskWriter write32(int val) {
    final b = ByteData(4)..setUint32(0, val, Endian.little);
    _buf.add(b.buffer.asUint8List());
    return this;
  }

  SlskWriter writeStr(String val) {
    final encoded = utf8.encode(val);
    write32(encoded.length);
    _buf.add(encoded);
    return this;
  }

  SlskWriter writeRawHex(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    _buf.add(out);
    return this;
  }

  SlskWriter writeBytes(List<int> bytes) {
    _buf.add(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    return this;
  }

  /// Prefix with 4-byte little-endian length (Soulseek framing).
  Uint8List toPacket() {
    final payload = _buf.toBytes();
    final out = BytesBuilder(copy: false);
    final len = ByteData(4)..setUint32(0, payload.length, Endian.little);
    out.add(len.buffer.asUint8List());
    out.add(payload);
    return out.toBytes();
  }

  Uint8List toBytes() => _buf.toBytes();
}

/// Binary reader for Soulseek protocol messages (little-endian).
class SlskReader {
  SlskReader(this._data) : pointer = 0;

  final Uint8List _data;
  int pointer;

  int get remaining => _data.length - pointer;

  int read8() {
    final v = _data[pointer];
    pointer += 1;
    return v;
  }

  int read32() {
    final v = ByteData.sublistView(_data, pointer, pointer + 4)
        .getUint32(0, Endian.little);
    pointer += 4;
    return v;
  }

  String readStr() {
    final size = read32();
    if (size < 0 || pointer + size > _data.length) {
      throw FormatException('Invalid string length $size');
    }
    final s = utf8.decode(
      _data.sublist(pointer, pointer + size),
      allowMalformed: true,
    );
    pointer += size;
    return s;
  }

  String readRawHex(int size) {
    final hex = _data
        .sublist(pointer, pointer + size)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    pointer += size;
    return hex;
  }

  Uint8List readBytes(int size) {
    final out = _data.sublist(pointer, pointer + size);
    pointer += size;
    return out;
  }

  void seek(int n) => pointer += n;
}

/// Splits a TCP byte stream into length-prefixed Soulseek messages.
class SlskMessageFramer {
  Uint8List _rest = Uint8List(0);

  /// Returns complete frames (4-byte length prefix + body).
  List<Uint8List> push(Uint8List chunk) {
    final combined = Uint8List(_rest.length + chunk.length)
      ..setAll(0, _rest)
      ..setAll(_rest.length, chunk);
    _rest = Uint8List(0);

    final out = <Uint8List>[];
    var offset = 0;
    while (offset + 4 <= combined.length) {
      final size = ByteData.sublistView(combined, offset, offset + 4)
          .getUint32(0, Endian.little);
      if (size + 4 > combined.length - offset) break;
      out.add(combined.sublist(offset, offset + size + 4));
      offset += size + 4;
    }
    if (offset < combined.length) {
      _rest = combined.sublist(offset);
    }
    return out;
  }

  void reset() => _rest = Uint8List(0);
}
