/// Lyrics in Latin letters, for scripts many listeners can't read, as
/// Metrolist and YouTube Music show them under the line: Korean (Revised
/// Romanization, with the sound changes heard in song), Cyrillic and Greek.
/// Everything else (Latin, digits, punctuation, other scripts) is kept.
library;

/// Scripts [romanize] turns into Latin letters.
enum RomanizedScript { korean, cyrillic, greek }

const _hangulFirst = 0xAC00;
const _hangulLast = 0xD7A3;

bool _isHangul(int rune) => rune >= _hangulFirst && rune <= _hangulLast;
bool _isCyrillic(int rune) => rune >= 0x0400 && rune <= 0x04FF;
bool _isGreek(int rune) =>
    (rune >= 0x0370 && rune <= 0x03FF) || (rune >= 0x1F00 && rune <= 0x1FFF);

/// The scripts in [text] that [romanize] changes.
Set<RomanizedScript> romanizableScripts(String text) => {
      for (final rune in text.runes)
        if (_isHangul(rune))
          RomanizedScript.korean
        else if (_isCyrillic(rune))
          RomanizedScript.cyrillic
        else if (_isGreek(rune))
          RomanizedScript.greek,
    };

/// [text] in Latin letters, or null when there is nothing to change.
String? romanize(String text) {
  if (romanizableScripts(text).isEmpty) return null;
  final runes = text.runes.toList();
  final out = StringBuffer();
  var i = 0;
  while (i < runes.length) {
    final rune = runes[i];
    if (_isHangul(rune)) {
      var end = i;
      while (end < runes.length && _isHangul(runes[end])) {
        end++;
      }
      out.write(_romanizeKoreanWord(runes.sublist(i, end)));
      i = end;
    } else if (_isCyrillic(rune) || _isGreek(rune)) {
      i = _writeLetter(out, runes, i);
    } else {
      out.writeCharCode(rune);
      i++;
    }
  }
  final result = out.toString();
  return result == text ? null : result;
}

// ── Korean ─────────────────────────────────────────────────────────────

// Initial consonants, in Unicode order.
const _gIni = 0, _nIni = 2, _dIni = 3, _rIni = 5, _mIni = 6;
const _sIni = 9, _silentIni = 11, _jIni = 12, _hIni = 18;

const _initials = [
  'g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp', 's', //
  'ss', '', 'j', 'jj', 'ch', 'k', 't', 'p', 'h',
];

const _medials = [
  'a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa', 'wae', //
  'oe', 'yo', 'u', 'wo', 'we', 'wi', 'yu', 'eu', 'ui', 'i',
];
const _iMedial = 20;

// Final consonants, in Unicode order (0: none).
const _fG = 1, _fGG = 2, _fGS = 3, _fN = 4, _fNJ = 5, _fNH = 6, _fD = 7;
const _fL = 8, _fLG = 9, _fLM = 10, _fLB = 11, _fLS = 12, _fLT = 13;
const _fLP = 14, _fLH = 15, _fM = 16, _fB = 17, _fBS = 18, _fS = 19;
const _fSS = 20, _fNG = 21, _fJ = 22, _fCh = 23, _fK = 24, _fT = 25;
const _fP = 26, _fH = 27;

/// A final consonant at the end of a word or before a consonant.
const _finals = [
  '', 'k', 'k', 'k', 'n', 'n', 'n', 't', 'l', 'k', 'm', 'l', 'l', 'l', //
  'p', 'l', 'm', 'p', 'p', 't', 't', 'ng', 't', 't', 'k', 't', 'p', 't',
];

/// A final consonant carried over to a following vowel (liaison): what
/// stays behind and what starts the next syllable.
const _liaison = <int, (String, String)>{
  _fG: ('', 'g'),
  _fGG: ('', 'kk'),
  _fGS: ('k', 's'),
  _fN: ('', 'n'),
  _fNJ: ('n', 'j'),
  _fNH: ('', 'n'),
  _fD: ('', 'd'),
  _fL: ('', 'r'),
  _fLG: ('l', 'g'),
  _fLM: ('l', 'm'),
  _fLB: ('l', 'b'),
  _fLS: ('l', 's'),
  _fLT: ('l', 't'),
  _fLP: ('l', 'p'),
  _fLH: ('', 'r'),
  _fM: ('', 'm'),
  _fB: ('', 'b'),
  _fBS: ('p', 's'),
  _fS: ('', 's'),
  _fSS: ('', 'ss'),
  _fJ: ('', 'j'),
  _fCh: ('', 'ch'),
  _fK: ('', 'k'),
  _fT: ('', 't'),
  _fP: ('', 'p'),
  _fH: ('', ''),
};

const _kFinals = {_fG, _fGG, _fGS, _fLG, _fK};
const _tFinals = {_fD, _fS, _fSS, _fJ, _fCh, _fT, _fH};
const _pFinals = {_fB, _fBS, _fLP, _fP};

/// One word (a run of syllables): each syllable's sounds, with the final
/// and the next initial adjusted where they meet.
String _romanizeKoreanWord(List<int> syllables) {
  final ini = <int>[], med = <int>[], fin = <int>[];
  for (final rune in syllables) {
    final s = rune - _hangulFirst;
    ini.add(s ~/ 588);
    med.add((s % 588) ~/ 28);
    fin.add(s % 28);
  }
  final out = StringBuffer();
  String? nextInitial;
  for (var i = 0; i < syllables.length; i++) {
    out.write(nextInitial ?? _initials[ini[i]]);
    out.write(_medials[med[i]]);
    nextInitial = null;
    final f = fin[i];
    if (i + 1 == syllables.length) {
      out.write(_finals[f]);
      break;
    }
    final (finalSound, initial) = _meet(f, ini[i + 1], med[i + 1]);
    out.write(finalSound);
    nextInitial = initial;
  }
  return out.toString();
}

/// How final [f] and the next syllable's initial [n] (vowel [nm]) sound
/// together: the final's letters and the next initial's.
(String, String?) _meet(int f, int n, int nm) {
  if (f == 0) return ('', null);
  // Liaison: the consonant moves on to the vowel (음악 eumak); ㄷ and ㅌ
  // before 이 soften to j / ch (같이 gachi).
  if (n == _silentIni) {
    if (f == _fNG) return ('ng', null);
    if (nm == _iMedial && f == _fD) return ('', 'j');
    if (nm == _iMedial && f == _fT) return ('', 'ch');
    final (stay, move) = _liaison[f]!;
    return (stay, move);
  }
  // ㅎ makes the next ㄱ ㄷ ㅈ aspirated (좋다 jota), and the one before it
  // (축하 chuka).
  if (f == _fH || f == _fNH || f == _fLH) {
    final rest = f == _fNH ? 'n' : (f == _fLH ? 'l' : '');
    if (n == _gIni) return (rest, 'k');
    if (n == _dIni) return (rest, 't');
    if (n == _jIni) return (rest, 'ch');
    if (n == _sIni) return (rest, 'ss');
  }
  if (n == _hIni) {
    if (f == _fG) return ('', 'k');
    if (f == _fD) return ('', 't');
    if (f == _fB) return ('', 'p');
    if (f == _fJ) return ('', 'ch');
  }
  // Nasalization before ㄴ ㅁ (합니다 hamnida).
  if (n == _nIni || n == _mIni) {
    if (f == _fL && n == _nIni) return ('l', 'l');
    if (_kFinals.contains(f)) return ('ng', null);
    if (_tFinals.contains(f)) return ('n', null);
    if (_pFinals.contains(f)) return ('m', null);
  }
  // ㄹ: ㄴㄹ / ㄹㄹ are ll (신라 silla); after ㅁ ㅇ it is n (종로 jongno),
  // and after ㄱ ㅂ both change (백리 baengni).
  if (n == _rIni) {
    if (f == _fN || f == _fL) return ('l', 'l');
    if (f == _fM || f == _fNG) return (_finals[f], 'n');
    if (_kFinals.contains(f)) return ('ng', 'n');
    if (_pFinals.contains(f)) return ('m', 'n');
  }
  return (_finals[f], null);
}

// ── Cyrillic and Greek ─────────────────────────────────────────────────

const _cyrillic = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo',
  'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
  'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
  'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
  'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
  // Ukrainian and Belarusian.
  'є': 'ye', 'і': 'i', 'ї': 'yi', 'ґ': 'g', 'ў': 'u',
  // Serbian and Macedonian.
  'ђ': 'dj', 'ј': 'j', 'љ': 'lj', 'њ': 'nj', 'ћ': 'c', 'џ': 'dz',
  'ѓ': 'gj', 'ќ': 'kj', 'ѕ': 'dz',
  // Kazakh and neighbours.
  'ә': 'a', 'ғ': 'gh', 'қ': 'q', 'ң': 'ng', 'ө': 'o', 'ұ': 'u', 'ү': 'u',
  'һ': 'h',
};

const _greekPairs = {
  'ου': 'ou',
  'ού': 'ou',
  'αυ': 'av',
  'αύ': 'av',
  'ευ': 'ev',
  'εύ': 'ev',
  'γγ': 'ng',
};

const _greek = {
  'α': 'a',
  'ά': 'a',
  'β': 'v',
  'γ': 'g',
  'δ': 'd',
  'ε': 'e',
  'έ': 'e',
  'ζ': 'z',
  'η': 'i',
  'ή': 'i',
  'θ': 'th',
  'ι': 'i',
  'ί': 'i',
  'ϊ': 'i',
  'ΐ': 'i',
  'κ': 'k',
  'λ': 'l',
  'μ': 'm',
  'ν': 'n',
  'ξ': 'x',
  'ο': 'o',
  'ό': 'o',
  'π': 'p',
  'ρ': 'r',
  'σ': 's',
  'ς': 's',
  'τ': 't',
  'υ': 'y',
  'ύ': 'y',
  'ϋ': 'y',
  'ΰ': 'y',
  'φ': 'f',
  'χ': 'ch',
  'ψ': 'ps',
  'ω': 'o',
  'ώ': 'o',
};

bool _isUpper(String s) => s != s.toLowerCase();

/// Writes the Latin for the Cyrillic or Greek letter at [i] (or a Greek
/// letter pair), in its case; returns where the next letter starts.
int _writeLetter(StringBuffer out, List<int> runes, int i) {
  final char = String.fromCharCode(runes[i]);
  final lower = char.toLowerCase();
  var used = 1;
  String? latin;
  if (_isGreek(runes[i]) && i + 1 < runes.length) {
    final pair = (char + String.fromCharCode(runes[i + 1])).toLowerCase();
    latin = _greekPairs[pair];
    if (latin != null) used = 2;
  }
  latin ??= _cyrillic[lower] ?? _greek[lower];
  if (latin == null) {
    out.write(char);
    return i + 1;
  }
  if (_isUpper(char) && latin.isNotEmpty) {
    // A word in capitals stays in capitals; otherwise just the first.
    final next =
        i + used < runes.length ? String.fromCharCode(runes[i + used]) : '';
    latin = next.isNotEmpty && _isUpper(next)
        ? latin.toUpperCase()
        : latin[0].toUpperCase() + latin.substring(1);
  }
  out.write(latin);
  return i + used;
}
