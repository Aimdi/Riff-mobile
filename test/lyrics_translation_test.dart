import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/lyrics_translation.dart';
import 'package:harmonymusic/ui/player/components/lyrics_widget.dart';

/// A real answer for "사랑해\n\n고마워\nhello there\n너만" (trimmed).
const _answer = '[[["I love you\\n\\n","사랑해\\n\\n",null,null,3],'
    '["thank you\\n","고마워\\n",null,null,3],'
    '["hello there\\n","hello there\\n",null,null,3],'
    '["Only you","너만",null,null,3]],null,"ko",null,null,null,1,[]]';

void main() {
  test('reads Google Translate answers', () {
    final data = jsonDecode(_answer);
    expect(gtxTranslatedText(data),
        'I love you\n\nthank you\nhello there\nOnly you');
    expect(gtxSourceLanguage(data), 'ko');
    expect(gtxTranslatedText('nonsense'), isNull);
    expect(gtxTranslatedText(const []), isNull);
    expect(gtxSourceLanguage(const [[]]), isNull);
  });

  test('a translation under each line that needs one', () {
    const lines = ['사랑해', '', '고마워', 'hello there', '너만'];
    final translated = gtxTranslatedText(jsonDecode(_answer))!.split('\n');
    expect(alignLyricsTranslation(lines, translated),
        ['I love you', null, 'thank you', null, 'Only you']);
  });

  test('none when the lines no longer match up', () {
    expect(alignLyricsTranslation(['a', 'b'], ['x']), [null, null]);
  });

  test('long lyrics go in several requests, whole lines', () {
    final lines = [for (var i = 0; i < 10; i++) 'line $i'];
    final chunks = lyricsTranslationChunks(lines, maxChars: 20);
    expect(chunks.expand((c) => c), lines);
    expect(chunks.length, greaterThan(1));
    for (final chunk in chunks) {
      expect(chunk.join('\n').length, lessThanOrEqualTo(20));
    }
    expect(lyricsTranslationChunks(['a', 'b']), [
      ['a', 'b']
    ]);
  });

  test('romanization and translation share the second line', () {
    expect(
        lyricsSecondLine('saranghae', 'I love you'), 'saranghae\nI love you');
    expect(lyricsSecondLine(null, 'I love you'), 'I love you');
    expect(lyricsSecondLine('saranghae', null), 'saranghae');
    expect(lyricsSecondLine(null, ' '), isNull);
  });

  group('the switch', () {
    tearDown(() => LyricsTranslation.setEnabled(false));

    test('off: no translations', () {
      expect(LyricsTranslation.linesFor(['사랑해'], language: 'en'), isNull);
    });

    test('on: the translations fetched for the lyrics', () async {
      await LyricsTranslation.setEnabled(true);
      LyricsTranslation.debugCache(['사랑해', 'hi'], 'en', ['I love you', null]);
      expect(LyricsTranslation.linesFor(['사랑해', 'hi'], language: 'en'),
          ['I love you', null]);
    });
  });

  test('plain lyrics: each line, then its translation', () {
    final span = romanizedLyricsText('Hello\nОдин',
        style: const TextStyle(),
        romanStyle: const TextStyle(fontSize: 10),
        translations: const [null, 'One']);
    // Cyrillic is also romanized: both go under the line.
    expect(span.toPlainText(), 'Hello\nОдин\nOdin\nOne');
  });
}
