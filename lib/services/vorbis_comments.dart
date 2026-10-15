import 'dart:convert';
import 'dart:typed_data';

/// The fields of a Vorbis comment [block] (a FLAC's VORBIS_COMMENT
/// metadata block, past its header): each one's name in capitals (names
/// are case-insensitive) and its value. Stops at a field cut short.
Iterable<(String, String)> vorbisComments(Uint8List block) sync* {
  if (block.length < 8) return;
  final b = ByteData.sublistView(block);
  // The vendor string, then the number of fields.
  var at = 4 + b.getUint32(0, Endian.little);
  if (at + 4 > block.length) return;
  final count = b.getUint32(at, Endian.little);
  at += 4;
  for (var i = 0; i < count && at + 4 <= block.length; i++) {
    final length = b.getUint32(at, Endian.little);
    at += 4;
    if (at + length > block.length) return;
    final field = utf8.decode(Uint8List.sublistView(block, at, at + length),
        allowMalformed: true);
    at += length;
    final eq = field.indexOf('=');
    if (eq <= 0) continue;
    yield (field.substring(0, eq).toUpperCase(), field.substring(eq + 1));
  }
}
