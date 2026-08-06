import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import '../utils/helper.dart';

/// Spotify sign-in using the official Authorization Code + PKCE flow.
///
/// PKCE is the flow Spotify documents for mobile/desktop clients: there is no
/// client secret, so nothing confidential ships in the APK. The client id is a
/// public identifier and is supplied by the user in plugin settings rather than
/// baked in — a single embedded id would put every install under one Spotify
/// app, which is capped at 25 users in development mode.
///
/// This talks only to `accounts.spotify.com` and `api.spotify.com`, the
/// documented public endpoints. It does not read session cookies or call
/// private endpoints.
class SpotifyAuthService {
  SpotifyAuthService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              responseType: ResponseType.plain,
            ));

  final Dio _dio;

  static const authorizeEndpoint = 'https://accounts.spotify.com/authorize';
  static const tokenEndpoint = 'https://accounts.spotify.com/api/token';

  /// Registered in the user's Spotify app dashboard.
  static const redirectUri = 'com.aimdi.riff://spotify-callback';

  /// Read-only scopes. Deliberately minimal: Riff reads a library, it never
  /// writes to the account.
  static const scopes = <String>[
    'playlist-read-private',
    'playlist-read-collaborative',
    'user-library-read',
    'user-follow-read',
    'user-top-read',
  ];

  // ---- stored settings -------------------------------------------------

  static const _kClientId = 'spotifyClientId';
  static const _kAccessToken = 'spotifyAccessToken';
  static const _kRefreshToken = 'spotifyRefreshToken';
  static const _kExpiresAt = 'spotifyTokenExpiresAt';
  static const _kVerifier = 'spotifyPkceVerifier';

  static Box get _box => Hive.box('AppPrefs');

  static String? get clientId {
    final v = _box.get(_kClientId);
    if (v is! String || v.trim().isEmpty) return null;
    return v.trim();
  }

  static Future<void> setClientId(String? id) async {
    final v = id?.trim();
    if (v == null || v.isEmpty) {
      await _box.delete(_kClientId);
    } else {
      await _box.put(_kClientId, v);
    }
  }

  static bool get isConfigured => clientId != null;

  static String? get accessToken => _box.get(_kAccessToken) as String?;
  static String? get refreshToken => _box.get(_kRefreshToken) as String?;
  static int get expiresAtMs => (_box.get(_kExpiresAt) as int?) ?? 0;

  static bool get isConnected =>
      (accessToken?.isNotEmpty ?? false) && (refreshToken?.isNotEmpty ?? false);

  /// Treats a token as expired slightly early so a request started right on the
  /// boundary does not land after it lapses.
  static bool isExpired(int expiresAtMs, int nowMs, {int skewMs = 60 * 1000}) =>
      nowMs >= (expiresAtMs - skewMs);

  static Future<void> disconnect() async {
    await _box.delete(_kAccessToken);
    await _box.delete(_kRefreshToken);
    await _box.delete(_kExpiresAt);
    await _box.delete(_kVerifier);
  }

  // ---- PKCE ------------------------------------------------------------

  static const _verifierAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// RFC 7636 code verifier: 43-128 chars from the unreserved set.
  static String generateCodeVerifier({int length = 64, Random? random}) {
    final r = random ?? Random.secure();
    final len = length.clamp(43, 128);
    return List.generate(
            len, (_) => _verifierAlphabet[r.nextInt(_verifierAlphabet.length)])
        .join();
  }

  /// S256 challenge: base64url(sha256(verifier)) with padding stripped.
  /// Spotify rejects padded challenges, so the `=` removal is load-bearing.
  static String codeChallengeS256(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier)).bytes;
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  /// Builds the URL to open in a WebView. [state] is echoed back by Spotify and
  /// must be checked on return to reject a response we did not initiate.
  static Uri buildAuthUrl({
    required String clientId,
    required String codeChallenge,
    required String state,
    String redirect = redirectUri,
    List<String> scopeList = scopes,
  }) =>
      Uri.parse(authorizeEndpoint).replace(queryParameters: {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirect,
        'code_challenge_method': 'S256',
        'code_challenge': codeChallenge,
        'state': state,
        'scope': scopeList.join(' '),
      });

  /// Whether [url] is the redirect we are waiting for.
  static bool isRedirect(String url, {String redirect = redirectUri}) =>
      url.startsWith(redirect);

  /// Result of interpreting the redirect Spotify sends back.
  static SpotifyRedirectResult parseRedirect(String url,
      {required String expectedState}) {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return const SpotifyRedirectResult.failure('Malformed redirect');
    }
    final q = uri.queryParameters;
    final error = q['error'];
    if (error != null && error.isNotEmpty) {
      // The user tapping "Cancel" lands here; it is not a fault condition.
      return SpotifyRedirectResult.failure(
          error == 'access_denied' ? 'Sign-in cancelled' : error);
    }
    // Checked before the code is used: a mismatched state means the response
    // did not come from the request we started.
    if (q['state'] != expectedState) {
      return const SpotifyRedirectResult.failure('State mismatch');
    }
    final code = q['code'];
    if (code == null || code.isEmpty) {
      return const SpotifyRedirectResult.failure('No authorization code');
    }
    return SpotifyRedirectResult.success(code);
  }

  // ---- token exchange --------------------------------------------------

  Future<void> _storeTokens(Map<String, dynamic> json, int nowMs) async {
    final access = json['access_token']?.toString();
    if (access == null || access.isEmpty) {
      throw StateError('Spotify returned no access token');
    }
    await _box.put(_kAccessToken, access);
    // A refresh response may omit refresh_token, which means keep the old one.
    final refresh = json['refresh_token']?.toString();
    if (refresh != null && refresh.isNotEmpty) {
      await _box.put(_kRefreshToken, refresh);
    }
    final expiresIn = json['expires_in'];
    final ttlMs = (expiresIn is num ? expiresIn.toInt() : 3600) * 1000;
    await _box.put(_kExpiresAt, nowMs + ttlMs);
  }

  Map<String, dynamic> _decode(dynamic body) {
    final decoded = jsonDecode(body.toString());
    if (decoded is! Map) throw StateError('Unexpected token response');
    return Map<String, dynamic>.from(decoded);
  }

  /// Exchange the authorization code for tokens. [verifier] must be the same
  /// one whose challenge was sent to /authorize.
  Future<void> exchangeCode({
    required String code,
    required String verifier,
    String? clientIdOverride,
    int? nowMsOverride,
  }) async {
    final id = clientIdOverride ?? clientId;
    if (id == null) throw StateError('No Spotify client id configured');
    final res = await _dio.post(
      tokenEndpoint,
      options: Options(
          contentType: Headers.formUrlEncodedContentType,
          validateStatus: (_) => true),
      data: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'client_id': id,
        'code_verifier': verifier,
      },
    );
    if (res.statusCode != 200) {
      throw StateError('Spotify token exchange failed (${res.statusCode})');
    }
    await _storeTokens(_decode(res.data),
        nowMsOverride ?? DateTime.now().millisecondsSinceEpoch);
  }

  /// Refresh the access token. Returns false when the refresh token is gone or
  /// rejected, which means the user must sign in again.
  Future<bool> refresh({int? nowMsOverride}) async {
    final id = clientId;
    final rt = refreshToken;
    if (id == null || rt == null || rt.isEmpty) return false;
    try {
      final res = await _dio.post(
        tokenEndpoint,
        options: Options(
            contentType: Headers.formUrlEncodedContentType,
            validateStatus: (_) => true),
        data: {
          'grant_type': 'refresh_token',
          'refresh_token': rt,
          'client_id': id,
        },
      );
      if (res.statusCode != 200) {
        printINFO('Spotify refresh rejected (${res.statusCode})');
        return false;
      }
      await _storeTokens(_decode(res.data),
          nowMsOverride ?? DateTime.now().millisecondsSinceEpoch);
      return true;
    } catch (e) {
      printINFO('Spotify refresh failed: $e');
      return false;
    }
  }

  /// A valid access token, refreshing first when needed. Null when the user is
  /// not signed in or the session can no longer be renewed.
  Future<String?> validAccessToken({int? nowMsOverride}) async {
    if (!isConnected) return null;
    final now = nowMsOverride ?? DateTime.now().millisecondsSinceEpoch;
    if (!isExpired(expiresAtMs, now)) return accessToken;
    final ok = await refresh(nowMsOverride: now);
    return ok ? accessToken : null;
  }

  /// Persist the verifier across the WebView round trip — the app can be
  /// backgrounded or recreated while the user is on Spotify's login page.
  static Future<void> stashVerifier(String v) => _box.put(_kVerifier, v);
  static String? takeStashedVerifier() {
    final v = _box.get(_kVerifier) as String?;
    _box.delete(_kVerifier);
    return v;
  }
}

/// Outcome of the OAuth redirect.
class SpotifyRedirectResult {
  const SpotifyRedirectResult.success(this.code)
      : error = null,
        ok = true;
  const SpotifyRedirectResult.failure(this.error)
      : code = null,
        ok = false;

  final bool ok;
  final String? code;
  final String? error;
}
