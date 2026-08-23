import 'package:package_info_plus/package_info_plus.dart';

/// Compile-time fallback used before [AppVersion.load] resolves the real
/// package version (and on platforms/tests where the plugin is unavailable).
///
/// MUST stay in sync with `version:` in pubspec.yaml — `test/app_version_test.dart`
/// asserts this, so a bumped pubspec with a stale constant fails the suite.
const String kPubspecAppVersion = '1.7.106';

/// Splits any version-ish string into exactly three numeric parts.
///
/// Tolerates a leading `v`/`V` (git tag style), a `+build` suffix
/// (`1.7.95+115`), missing segments (`1.8` -> `[1, 8, 0]`) and trailing
/// non-numeric noise (`1.7.95-beta` -> `[1, 7, 95]`).
List<int> parseVersionParts(String raw) {
  var s = raw.trim();
  final plus = s.indexOf('+');
  if (plus != -1) s = s.substring(0, plus);
  if (s.isNotEmpty && (s[0] == 'v' || s[0] == 'V')) s = s.substring(1);
  final parts = <int>[];
  for (final segment in s.split('.')) {
    final match = RegExp(r'\d+').firstMatch(segment);
    parts.add(match == null ? 0 : int.parse(match.group(0)!));
    if (parts.length == 3) break;
  }
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts;
}

/// Display/comparison shape used across the app: `V<major>.<minor>.<patch>`.
///
/// The leading `V` is load-bearing — [newVersionCheck] compares against GitHub
/// tag names which carry it, and it is what Settings -> About has always shown.
String normalizeAppVersion(String raw) {
  final source = RegExp(r'\d').hasMatch(raw) ? raw : kPubspecAppVersion;
  return 'V${parseVersionParts(source).join('.')}';
}

/// True when [availableVersion] is strictly newer than [currentVersion].
/// Both sides accept any shape [parseVersionParts] understands.
bool isNewerVersion(String availableVersion, String currentVersion) {
  final available = parseVersionParts(availableVersion);
  final current = parseVersionParts(currentVersion);
  for (var i = 0; i < 3; i++) {
    if (available[i] != current[i]) return available[i] > current[i];
  }
  return false;
}

/// Runtime app version, sourced from the installed package rather than a
/// hardcoded literal.
class AppVersion {
  AppVersion._();

  static String _display = normalizeAppVersion(kPubspecAppVersion);

  /// Last resolved version, e.g. `V1.7.95`. Safe to read before [load].
  static String get display => _display;

  /// Reads the real version out of the package. Falls back to
  /// [kPubspecAppVersion] if the platform channel is unavailable (unit tests).
  static Future<String> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (RegExp(r'\d').hasMatch(info.version)) {
        _display = normalizeAppVersion(info.version);
      }
    } catch (_) {
      // Keep the pubspec-backed fallback.
    }
    return _display;
  }
}
