/// Request headers for a direct `googlevideo.com` stream url, the way
/// NewPipe sends them: the User-Agent of the client the url was issued to
/// (`c` / `cver` query parameters), plus the YouTube origin for web clients.
/// Any other url (podcast enclosure, local file, server) gets none.
///
/// Mirrors `YoutubeDataSource.userAgentFor` on the native side.
Map<String, String>? youtubeStreamHeaders(String url) {
  final Uri uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return null;
  }
  if (!uri.host.endsWith('googlevideo.com')) return null;
  final Map<String, String> query;
  try {
    query = uri.queryParameters;
  } catch (_) {
    return null;
  }
  final client = query['c'];
  final version = query['cver'] ?? '';
  final web = client == null ||
      client.startsWith('WEB') ||
      client.startsWith('MWEB') ||
      client.startsWith('TVHTML5');
  String ua = _desktopUserAgent;
  if (version.isNotEmpty && client != null) {
    if (client == 'ANDROID_VR') {
      ua = 'com.google.android.apps.youtube.vr.oculus/$version '
          '(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip';
    } else if (client.startsWith('ANDROID')) {
      ua = 'com.google.android.youtube/$version (Linux; U; Android 14) gzip';
    } else if (client.startsWith('IOS')) {
      ua = 'com.google.ios.youtube/$version '
          '(iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X;)';
    }
  }
  return {
    'User-Agent': ua,
    if (web) 'Origin': 'https://www.youtube.com',
    if (web) 'Referer': 'https://www.youtube.com/',
  };
}

const _desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';
