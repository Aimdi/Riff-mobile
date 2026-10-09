import 'dart:convert';
import 'dart:io';

/// A short log of what the app was doing, kept in a file across launches
/// so a crash report can say what happened right before the exit.
///
/// Lines go through a plain `write()` as they arrive: the kernel keeps
/// them even when the process dies a moment later, so no flush is needed.
/// [printINFO] / [printERROR] feed it in every build mode; the file is
/// trimmed on launch, and rewritten from the in-memory tail every
/// [_compactEvery] lines, so it never grows past a few thousand lines.
class DiagLog {
  DiagLog._();

  static const fileName = 'riff_log.txt';
  static const _keepLines = 400;
  static const _lineMax = 600;

  /// Lines appended before the file is rewritten as this run's start
  /// marker plus its last [_keepLines] lines. A resident player logs for
  /// days between launches; without this the file only shrank on the next
  /// launch, which then read all of it on the UI isolate.
  static const _compactEvery = _keepLines * 4;

  static final List<String> _lines = <String>[];
  static List<String> _before = const <String>[];
  static RandomAccessFile? _file;
  static String _startMarker = '';
  static int _sinceCompact = 0;

  /// Opens (and trims) the log in [dir], remembering what the previous
  /// launch wrote. Lines logged before this call are written now.
  static void init(String dir, {required String version}) {
    try {
      final file = File('$dir/$fileName');
      var old = <String>[];
      if (file.existsSync()) {
        // Malformed UTF-8 (a write cut off by a crash) must not throw here:
        // that left the log off for good, since the bad bytes never went.
        final text = const Utf8Decoder(allowMalformed: true)
            .convert(file.readAsBytesSync());
        old = const LineSplitter().convert(text);
        if (old.length > _keepLines) {
          old = old.sublist(old.length - _keepLines);
        }
        file.writeAsStringSync(old.isEmpty ? '' : '${old.join('\n')}\n');
      }
      _before = old;
      _file?.closeSync();
      _file = file.openSync(mode: FileMode.append);
      _startMarker =
          '=== Riff $version started ${DateTime.now().toIso8601String()} ===';
      _sinceCompact = 0;
      _write(_startMarker);
      for (final l in _lines) {
        _write(l);
      }
    } catch (_) {
      _file = null;
    }
  }

  static void add(String line) {
    final now = DateTime.now().toIso8601String();
    var entry = '${now.substring(11, 23)} ${line.replaceAll('\n', ' ⏎ ')}';
    if (entry.length > _lineMax) entry = '${entry.substring(0, _lineMax)}…';
    _lines.add(entry);
    if (_lines.length > _keepLines) {
      _lines.removeRange(0, _lines.length - _keepLines);
    }
    if (_file != null) {
      _write(entry);
      if (++_sinceCompact >= _compactEvery) _compact();
    }
  }

  /// Rewrites the file as this run's start marker and its in-memory tail.
  /// The previous run's lines stay readable through [previousRun].
  static void _compact() {
    _sinceCompact = 0;
    final file = _file;
    if (file == null) return;
    try {
      file.truncateSync(0);
      // The file is open in append mode by position, not O_APPEND: rewind,
      // or the next write lands past a hole of zero bytes.
      file.setPositionSync(0);
      file.writeStringSync('$_startMarker\n${_lines.join('\n')}\n');
    } catch (_) {}
  }

  static void _write(String line) {
    try {
      _file?.writeStringSync('$line\n');
    } catch (_) {}
  }

  /// The last [n] lines of this launch.
  static List<String> tail([int n = 150]) =>
      _lines.length <= n ? List.of(_lines) : _lines.sublist(_lines.length - n);

  /// What the previous launch logged (from its start marker on), at most
  /// [n] lines — the part a crash report needs.
  static List<String> previousRun([int n = 150]) {
    var start = 0;
    for (var i = _before.length - 1; i >= 0; i--) {
      if (_before[i].startsWith('=== Riff ')) {
        start = i;
        break;
      }
    }
    final run = _before.sublist(start);
    return run.length <= n ? run : run.sublist(run.length - n);
  }

  /// Test hook: forget the file and buffers.
  static void reset() {
    _file?.closeSync();
    _file = null;
    _lines.clear();
    _before = const [];
    _startMarker = '';
    _sinceCompact = 0;
  }
}
