import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'diag_log.dart';

/// After Riff closed unexpectedly (crash, native crash, not responding),
/// offers the reason Android recorded so it can be copied and reported —
/// no adb or logcat needed. Android 11+ only; silent everywhere else.
class CrashReport {
  CrashReport._();

  static const _channel = MethodChannel('riff/apps');
  static const _seenKey = 'lastExitSeenMs';

  /// The record to show, or null when there is none or it was already
  /// shown. Pure so it can be tested.
  @visibleForTesting
  static Map<String, dynamic>? pick(Object? raw, int seenMs) {
    if (raw is! Map) return null;
    final ts = raw['timestamp'];
    if (ts is! int || ts <= seenMs) return null;
    if ('${raw['reason'] ?? ''}'.isEmpty) return null;
    return Map<String, dynamic>.from(raw);
  }

  /// Plain-text report for the clipboard; [log] is what the app logged
  /// before the exit.
  @visibleForTesting
  static String format(Map<String, dynamic> info, String version,
      {List<String> log = const []}) {
    final when = DateTime.fromMillisecondsSinceEpoch(info['timestamp'] as int);
    return [
      'Riff $version — ${info['reason']}',
      'When: ${when.toIso8601String()}',
      if ('${info['description'] ?? ''}'.isNotEmpty)
        'Details: ${info['description']}',
      if ('${info['trace'] ?? ''}'.isNotEmpty) '\n${info['trace']}',
      if (log.isNotEmpty) '\nLog before the exit:\n${log.join('\n')}',
    ].join('\n');
  }

  /// Everything a bug report needs, at any time: the version, the last
  /// unexpected exit Android recorded (shown before or not), what the
  /// previous launch logged and what this one has logged so far.
  static Future<String> diagnostics(String version) async {
    Object? raw;
    if (GetPlatform.isAndroid) {
      try {
        raw = await _channel.invokeMethod('lastExitInfo');
      } catch (_) {}
    }
    final out = StringBuffer('Riff $version diagnostics\n');
    if (raw is Map &&
        raw['timestamp'] is int &&
        '${raw['reason'] ?? ''}'.isNotEmpty) {
      out.writeln('\nLast unexpected exit:');
      out.writeln(format(Map<String, dynamic>.from(raw), version));
    } else {
      out.writeln('\nNo unexpected exit recorded.');
    }
    out.writeln('\nPrevious launch:\n${DiagLog.previousRun().join('\n')}');
    out.writeln('\nThis launch:\n${DiagLog.tail().join('\n')}');
    return out.toString();
  }

  static Future<void> checkAndOffer(String version) async {
    if (!GetPlatform.isAndroid) return;
    try {
      final raw = await _channel.invokeMethod('lastExitInfo');
      final prefs = Hive.box('AppPrefs');
      final seen = (prefs.get(_seenKey) as int?) ?? 0;
      final info = pick(raw, seen);
      if (info == null) {
        // First run with nothing to report (e.g. the last exit was the
        // update itself): start counting from now, or the first real crash
        // would be taken for an old record and skipped.
        if (seen == 0) {
          await prefs.put(_seenKey, DateTime.now().millisecondsSinceEpoch);
        }
        return;
      }
      await prefs.put(_seenKey, info['timestamp']);
      // First run after installing: an old record is not news.
      if (seen == 0) return;
      final ctx = Get.context;
      if (ctx == null || !ctx.mounted) return;
      final report = format(info, version, log: DiagLog.previousRun());
      unawaited(showDialog(
        context: ctx,
        builder: (context) => AlertDialog(
          title: Text('crashReportTitle'.tr),
          content:
              Text('crashReportDes'.trParams({'reason': '${info['reason']}'})),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('close'.tr),
            ),
            FilledButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: report));
                Navigator.of(context).pop();
              },
              child: Text('crashReportCopy'.tr),
            ),
          ],
        ),
      ));
    } catch (_) {
      // Missing channel / old Android: nothing to report.
    }
  }
}
