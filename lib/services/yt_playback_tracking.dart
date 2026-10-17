import 'dart:math';

const _cpnAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/// A client playback nonce, as YouTube's players make one per playback:
/// 16 characters of its URL-safe alphabet.
String ytCpn([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes(List.generate(
      16, (_) => _cpnAlphabet.codeUnitAt(r.nextInt(_cpnAlphabet.length))));
}

/// The address that counts a play in the account's history, as YouTube
/// Music's web player asks it when a song starts: the player's playback
/// tracking address ([base], its videostatsPlaybackUrl) on
/// music.youtube.com, with the client's name, version 2 and the playback's
/// nonce [cpn] (as Metrolist and InnerTune ask it).
Uri ytPlaybackUrl(String base, {required String cpn}) {
  final url = Uri.parse(base);
  return url.replace(
    host: url.host == 's.youtube.com' ? 'music.youtube.com' : url.host,
    queryParameters: <String, List<String>>{
      ...url.queryParametersAll,
      'ver': ['2'],
      'c': ['WEB_REMIX'],
      'cpn': [cpn],
    },
  );
}
