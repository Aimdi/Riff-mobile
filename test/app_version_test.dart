import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/app_version.dart';

String _pubspecVersion() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match =
      RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
  expect(match, isNotNull, reason: 'pubspec.yaml has no version: line');
  return match!.group(1)!;
}

void main() {
  group('pubspec sync', () {
    test('kPubspecAppVersion matches pubspec.yaml version', () {
      // The build suffix (+115) is not part of the user-facing version.
      final pubspecVersion = _pubspecVersion().split('+').first;
      expect(kPubspecAppVersion, pubspecVersion,
          reason: 'lib/utils/app_version.dart drifted from pubspec.yaml');
    });

    test('AppVersion.display reflects pubspec before any platform load', () {
      expect(AppVersion.display, 'V${_pubspecVersion().split('+').first}');
    });

    test('no hardcoded version literal remains in the settings controller', () {
      final source = File('lib/ui/screens/Settings/settings_screen_controller.dart')
          .readAsStringSync();
      // Guards the original defect: `final currentVersion = "V1.7.79";`
      expect(RegExp(r'''["']V?\d+\.\d+\.\d+["']''').hasMatch(source), isFalse,
          reason: 'version must come from AppVersion, not a literal');
    });
  });

  group('parseVersionParts', () {
    test('parses a plain three-part version', () {
      expect(parseVersionParts('1.7.95'), [1, 7, 95]);
    });

    test('strips a leading V or v', () {
      expect(parseVersionParts('V1.7.95'), [1, 7, 95]);
      expect(parseVersionParts('v1.7.95'), [1, 7, 95]);
    });

    test('strips the +build suffix that pubspec carries', () {
      // PackageInfo/pubspec shapes must not leak "95+115" into int.parse.
      expect(parseVersionParts('1.7.95+115'), [1, 7, 95]);
      expect(parseVersionParts('V1.7.95+115'), [1, 7, 95]);
    });

    test('pads short versions and ignores extra segments', () {
      expect(parseVersionParts('1.8'), [1, 8, 0]);
      expect(parseVersionParts('2'), [2, 0, 0]);
      expect(parseVersionParts('1.2.3.4'), [1, 2, 3]);
    });

    test('tolerates non-numeric noise', () {
      expect(parseVersionParts('1.7.95-beta'), [1, 7, 95]);
      expect(parseVersionParts('   V1.7.95  '), [1, 7, 95]);
    });
  });

  group('normalizeAppVersion', () {
    test('always produces the V-prefixed display shape', () {
      expect(normalizeAppVersion('1.7.95'), 'V1.7.95');
      expect(normalizeAppVersion('V1.7.95'), 'V1.7.95');
      expect(normalizeAppVersion('1.7.95+115'), 'V1.7.95');
    });

    test('falls back to the pubspec constant for junk input', () {
      expect(normalizeAppVersion(''), 'V$kPubspecAppVersion');
      expect(normalizeAppVersion('unknown'), 'V$kPubspecAppVersion');
    });
  });

  group('isNewerVersion', () {
    test('detects newer major, minor and patch', () {
      expect(isNewerVersion('V2.0.0', 'V1.7.95'), isTrue);
      expect(isNewerVersion('V1.8.0', 'V1.7.95'), isTrue);
      expect(isNewerVersion('V1.7.96', 'V1.7.95'), isTrue);
    });

    test('equal or older versions are not newer', () {
      expect(isNewerVersion('V1.7.95', 'V1.7.95'), isFalse);
      expect(isNewerVersion('V1.7.94', 'V1.7.95'), isFalse);
      expect(isNewerVersion('V1.6.99', 'V1.7.0'), isFalse);
      expect(isNewerVersion('V0.9.9', 'V1.0.0'), isFalse);
    });

    test('numeric compare, not lexicographic string compare', () {
      expect(isNewerVersion('V1.7.100', 'V1.7.99'), isTrue);
      expect(isNewerVersion('V1.7.9', 'V1.7.79'), isFalse);
    });

    test('the stale literal would have reported a phantom update', () {
      // Regression: the shipped tag equals the real version, so no update.
      expect(isNewerVersion('V$kPubspecAppVersion', AppVersion.display), isFalse);
      // ...whereas the old hardcoded "V1.7.79" claimed one was available.
      expect(isNewerVersion('V$kPubspecAppVersion', 'V1.7.79'), isTrue);
    });

    test('mixed shapes still compare correctly', () {
      expect(isNewerVersion('1.7.96', 'V1.7.95+115'), isTrue);
      expect(isNewerVersion('V1.7.95', '1.7.95+115'), isFalse);
    });
  });
}
