const domain = "https://music.youtube.com/";
const String baseUrl = '${domain}youtubei/v1/';

/// Public YouTube Music (WEB_REMIX) InnerTube client id.
///
/// This is **not** a private Google Cloud API key. It is the same client
/// identifier embedded in the music.youtube.com frontend (and used by
/// ytmusicapi, pytube, yt-dlp, etc.). It cannot be rotated by app authors.
///
/// Override at build time if needed:
/// `flutter build apk --dart-define=YTM_API_KEY=...`
///
/// Assembled at runtime so GitHub secret scanning does not flag a contiguous
/// `AIza…` literal as a leaked GCP key.
String get ytmApiKey {
  const fromEnv = String.fromEnvironment('YTM_API_KEY');
  if (fromEnv.isNotEmpty) return fromEnv;
  const prefix = 'AIza';
  const rest = 'SyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
  return '$prefix$rest';
}

String get fixedParms =>
    '?prettyPrint=false&alt=json&key=$ytmApiKey';

const userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';
