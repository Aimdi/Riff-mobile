/// While songs or episodes download, Android keeps Riff running and the
/// notification shade shows how far they've got, as with YouTube Music,
/// Spotify and AntennaPod. Android freezes an app a while after you leave
/// it, so a playlist's download used to stop there unless music played.
/// Android only.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:permission_handler/permission_handler.dart';

import '/utils/helper.dart';

/// How far one kind of download has got.
typedef DownloadProgress = ({int done, int total, String text});

class DownloadNotice {
  DownloadNotice._();

  static const channel = MethodChannel('riff/downloads');

  /// Song downloads (the download job).
  static const songs = 'songs';

  /// Podcast episode downloads.
  static const episodes = 'episodes';

  /// Audiobook downloads (AudiobookDownloads).
  static const books = 'books';

  /// AppPrefs: the notifications permission was asked for (once).
  static const askedKey = 'askedDownloadNotifications';

  static final _jobs = <String, DownloadProgress>{};

  /// [job] has [done] of its [total] done; [text]: what it's on now.
  static void update(String job,
      {required int done, required int total, required String text}) {
    _jobs[job] = (done: done, total: total, text: text);
    _send(show: true);
  }

  /// [job] is over (finished or called off).
  static void end(String job) {
    if (_jobs.remove(job) != null) _send(show: _jobs.isNotEmpty);
  }

  /// What the notification says: every job's counts together ("Downloading
  /// 3 of 25", the one going now among all of them) and the latest text.
  static Map<String, Object> shown() {
    var done = 0;
    var total = 0;
    var text = '';
    for (final job in _jobs.values) {
      done += job.done;
      total += job.total;
      text = job.text;
    }
    final current = done < total ? done + 1 : total;
    return {
      'title': 'downloadingCount'
          .trParams({'current': '$current', 'total': '$total'}),
      'text': text,
      'done': done,
      'total': total,
      'channel': 'downloads'.tr,
    };
  }

  static void _send({required bool show}) {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (show) _askOnce();
    channel
        .invokeMethod<bool>(show ? 'show' : 'stop', show ? shown() : null)
        .catchError((Object e) {
      printERROR('Download notice: $e');
      return false;
    });
  }

  /// Android 13+ shows the notification only with permission: asked for
  /// at the first download, never again.
  static void _askOnce() {
    final prefs = Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;
    if (prefs == null || prefs.get(askedKey) == true) return;
    prefs.put(askedKey, true);
    Permission.notification.request().catchError((Object e) {
      printERROR('Notifications permission: $e');
      return PermissionStatus.denied;
    });
  }

  @visibleForTesting
  static void resetForTest() => _jobs.clear();
}
