import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/audiobookshelf_service.dart';

/// Guards the OOM-avoidance property of audiobook uploads.
///
/// Audiobooks routinely run to hundreds of megabytes and a multi-part book is
/// several of those at once, so reading a selected file into the Dart heap
/// gets the app killed. `AbsUploadFile` must therefore be constructible from a
/// path alone, and `uploadBook` prefers `MultipartFile.fromFile` (lazy disk
/// read) whenever a path is present.
void main() {
  group('AbsUploadFile', () {
    test('is constructible from a path alone, with no bytes in memory', () {
      final f = AbsUploadFile(filename: 'part1.m4b', path: '/tmp/part1.m4b');
      expect(f.path, '/tmp/part1.m4b');
      expect(f.bytes, isNull,
          reason: 'a path-based file must not carry its contents');
      expect(f.filename, 'part1.m4b');
    });

    // The bytes path stays available for pickers that hand back no path
    // (some content providers), so it must not be removed outright.
    test('still accepts bytes when the platform gave no path', () {
      final f = AbsUploadFile(filename: 'x.mp3', bytes: const [1, 2, 3]);
      expect(f.bytes, isNotEmpty);
      expect(f.path, isNull);
    });

    test('rejects a file with neither a path nor bytes', () {
      expect(() => AbsUploadFile(filename: 'empty.mp3'), throwsA(anything),
          reason: 'there would be nothing to send');
    });

    test('a multi-part book stages every part by path', () {
      final parts = List.generate(
        12,
        (i) => AbsUploadFile(filename: 'part$i.m4b', path: '/tmp/part$i.m4b'),
      );
      expect(parts.every((p) => p.path != null && p.bytes == null), isTrue,
          reason: 'buffering a 12-part book would be gigabytes of heap');
    });
  });
}
