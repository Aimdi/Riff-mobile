import 'dart:io';

/// A short log of what the app was doing, kept in a file across launches
/// so a crash report can say what happened right before the exit.
///
/// Lines go through a plain `write()` as they arrive: the kernel keeps
/// them even when the process dies a moment later, so no flush is needed.
/// [printINFO] / [printERROR] feed it in every build mode; the file is
/// trimmed on launch so it never grows past a few hundred lines.
class DiagLog {
  DiagLog._();

  static const fileName = 'riff_log.txt';
  static const _keepLines = 400;
  static const _lineMax = 600;

  static final List<String> _lines = <String>[];
  static List<String> _before = const <String>[];
  static RandomAccessFile? _file;

  /// Opens (and trims) the log in [dir], remembering what the previous
  /// launch wrote. Lines logged before this call are written now.
  static void init(String dir, {required String version}) {
    try {
      final file = File('$dir/$fileName');
      var old = <String>[];
      if (file.existsSync()) {
        old = file.readAsLinesSync();
        if (old.length > _keepLines) {
          old = old.sublist(old.length - _keepLines);
        }
        file.writeAsStringSync(old.isEmpty ? '' : '${old.join('\n')}\n');
      }
      _before = old;
      _file?.closeSync();
      _file = file.openSync(mode: FileMode.append);
      _write('=== Riff $version started ${DateTime.now().toIso8601String()} ===');
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
    if (_file != null) _write(entry);
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
  }
}
