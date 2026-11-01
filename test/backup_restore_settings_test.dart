import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/components/lyrics_widget.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/widgets/backup_dialog.dart';
import 'package:harmonymusic/ui/widgets/restore_dialog.dart';

Archive _zip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, text) =>
      archive.addFile(ArchiveFile(name, text.length, text.codeUnits)));
  return archive;
}

void main() {
  group('restore checks the backup before anything is deleted', () {
    test("a Riff backup: its data, songs and covers", () {
      final files = backupFilesToRestore(_zip({
        'appprefs.hive': 'x',
        'libfav.hive': 'x',
        'Song (Artist).m4a': 'x',
        'abc123.png': 'x',
      }));
      expect(files.map((f) => f.name), hasLength(4));
    });

    test('another zip, or one without the settings: nothing', () {
      expect(backupFilesToRestore(_zip({'photo.jpg': 'x'})), isEmpty);
      expect(
          backupFilesToRestore(_zip({'appprefs.hive': 'x', 'notes.txt': 'x'})),
          isEmpty);
      expect(backupFilesToRestore(_zip({'libfav.hive': 'x'})), isEmpty);
      // A name reaching out of where it's put.
      expect(
          backupFilesToRestore(
              _zip({'appprefs.hive': 'x', '../evil.hive': 'x'})),
          isEmpty);
    });

    test('a file that is no zip at all throws before the restore wipes',
        () {
      expect(() => ZipDecoder().decodeBytes([1, 2, 3, 4]), throwsA(anything));
    });
  });

  test('a backup keeps each file under its own name when one is missing',
      () {
    final dir = Directory.systemTemp.createTempSync('backup_test');
    try {
      final a = File('${dir.path}/A.m4a')..writeAsStringSync('song A');
      final c = File('${dir.path}/C.m4a')..writeAsStringSync('song C');
      final files =
          filesForBackup([a.path, '${dir.path}/B-deleted.m4a', c.path]);
      expect([for (final (n, d) in files) '$n=${String.fromCharCodes(d)}'],
          ['A.m4a=song A', 'C.m4a=song C']);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('a new lyrics source keeps lyrics you picked and those for downloads',
      () {
    bool downloaded(String id) => id == 'dl';
    expect(lyricsCacheDroppable('a', {'synced': 'x'}, downloaded: downloaded),
        isTrue);
    expect(
        lyricsCacheDroppable('b', {'synced': 'x', 'chosen': true},
            downloaded: downloaded),
        isFalse);
    expect(lyricsCacheDroppable('plain:c', 'words', downloaded: downloaded),
        isFalse);
    expect(lyricsCacheDroppable('dl', {'synced': 'x'}, downloaded: downloaded),
        isFalse);
  });

  test('Reset to default resets settings, not accounts or your data', () {
    expect(resetsWithSettings('themeModeType'), isTrue);
    expect(resetsWithSettings('streamingQuality'), isTrue);
    for (final kept in [
      'cloudMusic',
      'audiobookshelf',
      'piped',
      'lyricsDelayMs',
      'collectionLastPlayed',
      'pinnedPlaylists',
      'searchRecentItems',
    ]) {
      expect(resetsWithSettings(kept), isFalse, reason: kept);
    }
  });

  test('plain lyrics from synced ones when there are no plain ones', () {
    expect(
        plainLyricsText({
          'plainLyrics': null,
          'synced': '[00:01.00]First line\n[00:05.50]Second line',
        }),
        'First line\nSecond line');
    expect(plainLyricsText({'plainLyrics': 'Own words', 'synced': '[00:01]x'}),
        'Own words');
  });
}
