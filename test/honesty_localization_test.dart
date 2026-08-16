import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/get_localization.dart';

/// Keys that used to render as their own name (GetX missing-key fallback).
void main() {
  late Map<String, String> en;
  late Map<String, dynamic> enJson;

  setUpAll(() {
    en = Languages().keys['en']!;
    enJson = jsonDecode(File('localization/en.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  const honestyKeys = <String>[
    'podcastInbox',
    'subsShort',
    'refreshInbox',
    'podcastAutoplayOn',
    'podcastAutoplayOff',
    'searchPodcastsOrYoutube',
    'youtubeChannels',
    'youtubeChannelsDes',
    'downloadSetupFailed',
    'soulseek',
    'soulseekDes',
    'soulseekPluginDes',
    'soulseekInstalling',
    'soulseekInstalled',
    'soulseekLoggedIn',
    'soulseekLoginFailed',
    'soulseekLoginTitle',
    'soulseekLoginDes',
    'soulseekUsername',
    'soulseekPassword',
    'soulseekLogin',
    'soulseekAccountHint',
    'soulseekCreateAccount',
    'soulseekSearchFailed',
    'soulseekDownloadSaved',
    'soulseekDownloadFailed',
    'soulseekAlbumDownloadDone',
    'soulseekLoggedInAs',
    'soulseekSearchHintSong',
    'soulseekSearchHintAlbum',
    'soulseekModeSong',
    'soulseekModeAlbum',
    'soulseekFilterSlot',
    'soulseekSearchingLive',
    'soulseekSearchNote',
    'soulseekSearchPromptSockseek',
    'soulseekNoResults',
    'soulseekTracks',
    'soulseekDownloadAlbum',
    'soulseekDownload',
    'soulseekNotLoggedIn',
    'songRemovedAlert',
    'operationFailed',
    'removedFromQueue',
    'enqueueSongs',
    'downloadPlaylist',
    'syncPlaylistSongs',
    'blacklistPipedPlaylist',
    'sharePlaylist',
    'mixSmartOrder',
    'mixSmartOrderDone',
    'permissionDenied',
    'newFolder',
    'folderEmpty',
  ];

  test('honesty keys exist in generated translations', () {
    final missing = honestyKeys.where((k) => !en.containsKey(k)).toList();
    expect(missing, isEmpty,
        reason: 'these would render as their own key name in the UI');
  });

  test('honesty keys exist in en.json and match generated text', () {
    final missingFromJson =
        honestyKeys.where((k) => !enJson.containsKey(k)).toList();
    expect(missingFromJson, isEmpty);
    final drifted = honestyKeys
        .where((k) => enJson[k] != null && enJson[k] != en[k])
        .toList();
    expect(drifted, isEmpty,
        reason: 'add the same English string to en.json and the en map');
  });

  test('no honesty key is blank', () {
    for (final k in honestyKeys) {
      expect(en[k]?.trim().isNotEmpty, isTrue, reason: '$k is blank');
    }
  });
}
