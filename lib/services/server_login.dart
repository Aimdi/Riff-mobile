/// Links to your own music server (a Subsonic server's /rest/ API) carry
/// your login in their query: your user name with a token and its salt,
/// or the password itself (hex-encoded, read as easily as written), or an
/// API key. These keep it out of what others may read (an exported
/// playlist), and sign such a link again for the server Riff is connected
/// to.
library;

const _loginParams = {'u', 'p', 't', 's', 'apiKey'};

/// [url] when it's a link to a music server's API.
Uri? _serverApi(String url) {
  if (!url.contains('/rest/')) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || !uri.path.contains('/rest/')) {
    return null;
  }
  return uri;
}

/// Whether [url], a link to a music server's API, carries a login.
bool hasServerLogin(String url) {
  final q = _serverApi(url)?.queryParameters;
  if (q == null) return false;
  return q.containsKey('p') ||
      q.containsKey('apiKey') ||
      (q.containsKey('t') && q.containsKey('s'));
}

/// [url] without the login it carries when it's a link to a music
/// server's API; any other link as it is.
String withoutServerLogin(String url) {
  final uri = _serverApi(url);
  if (uri == null) return url;
  final all = uri.queryParametersAll;
  if (!all.keys.any(_loginParams.contains)) return url;
  return uri.replace(queryParameters: {
    for (final e in all.entries)
      if (!_loginParams.contains(e.key)) e.key: e.value,
  }).toString();
}

/// [value] (an exported playlist's JSON) with every link to a music
/// server in it stripped of its login.
Object? withoutServerLogins(Object? value) => switch (value) {
      String s => withoutServerLogin(s),
      Map m => {for (final e in m.entries) e.key: withoutServerLogins(e.value)},
      List l => [for (final v in l) withoutServerLogins(v)],
      _ => value,
    };

/// [url], a link to the music server at [server] that has no login (as
/// exported playlists keep them), signed with [login]; any other link as
/// it is.
String signedServerUrl(String url,
    {required String server, required Map<String, String> login}) {
  final uri = _serverApi(url);
  final home = Uri.tryParse(server);
  if (uri == null ||
      home == null ||
      login.isEmpty ||
      uri.host != home.host ||
      hasServerLogin(url)) {
    return url;
  }
  return uri.replace(
      queryParameters: {...uri.queryParametersAll, ...login}).toString();
}

/// [value] (an imported playlist's JSON) with every link to the music
/// server at [server] in it signed with [login].
Object? withServerLogins(Object? value,
        {required String server, required Map<String, String> login}) =>
    switch (value) {
      String s => signedServerUrl(s, server: server, login: login),
      Map m => {
          for (final e in m.entries)
            e.key: withServerLogins(e.value, server: server, login: login)
        },
      List l => [
          for (final v in l) withServerLogins(v, server: server, login: login)
        ],
      _ => value,
    };
