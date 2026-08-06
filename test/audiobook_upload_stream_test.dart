import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/audiobookshelf_service.dart';

/// Read a multipart body out of a form the same way dio would when sending it.
Future<String> _finalizeToString(FormData form) async {
  final chunks = <int>[];
  await for (final c in form.finalize()) {
    chunks.addAll(c);
  }
  return utf8.decode(chunks, allowMalformed: true);
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('abs_upload_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('absUploadFilesFromPicked', () {
    test('keeps name and path, never touches file contents', () {
      final files = absUploadFilesFromPicked([
        (name: 'part1.mp3', path: '/storage/emulated/0/books/part1.mp3'),
        (name: 'part2.mp3', path: '/storage/emulated/0/books/part2.mp3'),
      ]);
      expect(files.map((f) => f.filename), ['part1.mp3', 'part2.mp3']);
      expect(files.map((f) => f.path), [
        '/storage/emulated/0/books/part1.mp3',
        '/storage/emulated/0/books/part2.mp3',
      ]);
    });

    // The picker no longer runs with `withData: true`, so an entry without a
    // path has nothing we can stream from — it must be dropped, not read.
    test('skips entries the picker gave no usable path for', () {
      final files = absUploadFilesFromPicked([
        (name: 'ok.m4b', path: '/books/ok.m4b'),
        (name: 'no-path.m4b', path: null),
        (name: 'empty-path.m4b', path: ''),
      ]);
      expect(files.length, 1);
      expect(files.single.filename, 'ok.m4b');
    });
  });

  group('buildAbsUploadFormData', () {
    test('carries the metadata fields ABS expects', () async {
      final book = File('${tmp.path}/book.m4b')..writeAsStringSync('audio');
      final form = await buildAbsUploadFormData(
        libraryId: 'lib1',
        folderId: 'fold1',
        title: 'Moby Dick',
        author: '  Herman Melville  ',
        series: '   ',
        files: [AbsUploadFile(filename: 'book.m4b', path: book.path)],
      );
      final fields = {for (final f in form.fields) f.key: f.value};
      expect(fields['title'], 'Moby Dick');
      expect(fields['library'], 'lib1');
      expect(fields['folder'], 'fold1');
      expect(fields['author'], 'Herman Melville');
      expect(fields.containsKey('series'), isFalse);
      // ABS keys the parts 0,1,2… in pick order.
      expect(form.files.map((e) => e.key), ['0']);
      expect(form.files.single.value.filename, 'book.m4b');
    });

    test('numbers multiple parts in order', () async {
      final a = File('${tmp.path}/a.mp3')..writeAsStringSync('aaaa');
      final b = File('${tmp.path}/b.mp3')..writeAsStringSync('bbbb');
      final form = await buildAbsUploadFormData(
        libraryId: 'lib1',
        folderId: 'fold1',
        title: 'Two parts',
        files: [
          AbsUploadFile(filename: 'a.mp3', path: a.path),
          AbsUploadFile(filename: 'b.mp3', path: b.path),
        ],
      );
      expect(form.files.map((e) => e.key), ['0', '1']);
      expect(form.files.map((e) => e.value.filename), ['a.mp3', 'b.mp3']);
    });

    // Regression: the upload API used to take `List<int> bytes`, so the whole
    // book sat in the Dart heap from the moment it was picked until the (up to
    // 30 minute) request finished — a 700 MB m4b got the app OOM-killed. The
    // part must read off disk while the request is being sent, which we can
    // observe: rewrite the file after building the form and the *new* content
    // is what goes out on the wire. A buffered part would still send the copy
    // taken at build time.
    test('streams file content from disk instead of buffering it', () async {
      final book = File('${tmp.path}/book.m4b')..writeAsStringSync('OLDCONTENT');
      final form = await buildAbsUploadFormData(
        libraryId: 'lib1',
        folderId: 'fold1',
        title: 'Streamed',
        files: [AbsUploadFile(filename: 'book.m4b', path: book.path)],
      );
      // Same length, different bytes: the part's declared size stays valid.
      book.writeAsStringSync('NEWCONTENT');

      final body = await _finalizeToString(form);
      expect(body, contains('NEWCONTENT'),
          reason: 'body must come from the file at send time');
      expect(body, isNot(contains('OLDCONTENT')),
          reason: 'file bytes must not be snapshotted into memory');
      expect(body, contains('filename="book.m4b"'));
    });
  });
}
