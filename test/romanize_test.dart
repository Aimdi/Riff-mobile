import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/lyrics_romanization.dart';
import 'package:harmonymusic/ui/player/components/lyrics_widget.dart';
import 'package:harmonymusic/utils/romanize.dart';

void main() {
  group('Korean, as sung', () {
    const words = {
      '안녕하세요': 'annyeonghaseyo',
      '사랑해': 'saranghae',
      '감사합니다': 'gamsahamnida', // ㅂ before ㄴ is m
      '음악': 'eumak', // the final moves on to the vowel
      '있어': 'isseo',
      '많아': 'mana', // ㅎ is silent before a vowel
      '좋아': 'joa',
      '좋다': 'jota', // and makes the next consonant aspirated
      '축하': 'chuka',
      '같이': 'gachi', // ㅌ before 이 is ch
      '신라': 'silla',
      '설날': 'seollal',
      '종로': 'jongno',
      '백리': 'baengni',
      '빛': 'bit',
      '꽃이': 'kkochi',
    };
    for (final word in words.entries) {
      test('${word.key} → ${word.value}',
          () => expect(romanize(word.key), word.value));
    }

    test('spaces, punctuation and Latin stay', () {
      expect(romanize('사랑해 baby, 너만'), 'saranghae baby, neoman');
    });
  });

  test('Cyrillic', () {
    expect(romanize('Привет, мир'), 'Privet, mir');
    expect(romanize('Ёжик в тумане'), 'Yozhik v tumane');
    expect(romanize('щука'), 'shchuka');
    expect(romanize('ЖУК'), 'ZHUK');
    expect(romanize('Їжак'), 'Yizhak');
  });

  test('Greek', () {
    expect(romanize('Γεια σου'), 'Geia sou');
    expect(romanize('Αθήνα'), 'Athina');
    expect(romanize('Ευχαριστώ'), 'Evcharisto');
  });

  test('nothing to romanize', () {
    expect(romanize('Hello, world'), isNull);
    expect(romanize('君の名は'), isNull);
    expect(romanizableScripts('Hello 너 Привет'),
        {RomanizedScript.korean, RomanizedScript.cyrillic});
  });

  group('LyricsRomanization', () {
    tearDown(() => LyricsRomanization.enabled.value = true);

    test("not for the app language's own script", () {
      expect(LyricsRomanization.lineFor('사랑해', appLanguage: 'en'), 'saranghae');
      expect(LyricsRomanization.lineFor('사랑해', appLanguage: 'ko'), isNull);
      expect(LyricsRomanization.lineFor('Привет', appLanguage: 'uk'), isNull);
      expect(LyricsRomanization.lineFor('Привет 사랑해', appLanguage: 'ru'),
          'Privet saranghae');
      expect(LyricsRomanization.lineFor('Hello', appLanguage: 'en'), isNull);
    });

    test('turned off in Settings: none', () {
      LyricsRomanization.enabled.value = false;
      expect(LyricsRomanization.lineFor('사랑해', appLanguage: 'en'), isNull);
    });
  });

  test('plain lyrics: each line, then its romanization', () {
    final span = romanizedLyricsText('Hello\n사랑해\nПривет',
        style: const TextStyle(), romanStyle: const TextStyle(fontSize: 10));
    expect(span.toPlainText(), 'Hello\n사랑해\nsaranghae\nПривет\nPrivet');
  });
}
