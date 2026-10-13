import 'dart:io';

import 'package:hive/hive.dart';

/// Files whose deletion waits on an Undo, by owner key, in AppPrefs: what a
/// closed app left behind is deleted on the next start
/// ([purgePendingFiles]). Library songs use their id, podcast downloads
/// `podcast:<episode id>`.
const pendingFileDeletesKey = 'pendingLibraryFileDeletes';

Map<String, dynamic> _pending(Box prefs) {
  final raw = prefs.get(pendingFileDeletesKey);
  return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
}

Future<void> markPendingFiles(Box prefs, String key, List<String> files) async {
  final next = _pending(prefs)..[key] = files;
  await prefs.put(pendingFileDeletesKey, next);
}

Future<void> clearPendingFiles(Box prefs, String key) async {
  final next = _pending(prefs);
  if (next.remove(key) == null) return;
  next.isEmpty
      ? await prefs.delete(pendingFileDeletesKey)
      : await prefs.put(pendingFileDeletesKey, next);
}

/// Deletes [files] that exist; one that can't be deleted is skipped.
Future<void> deleteFiles(Iterable<String> files) async {
  for (final path in files) {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Gone already, or not ours to delete: nothing to undo either way.
    }
  }
}

/// Start-up: deletes the files of removals an app closed before it could,
/// except for owners [keep] says are back (re-added, re-downloaded).
Future<void> purgePendingFiles(Box prefs,
    {required bool Function(String key) keep}) async {
  final pending = _pending(prefs);
  if (pending.isEmpty) return;
  for (final MapEntry(:key, :value) in pending.entries) {
    if (keep(key) || value is! List) continue;
    await deleteFiles(value.map((f) => '$f'));
  }
  await prefs.delete(pendingFileDeletesKey);
}
