import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '/services/spotify_auth_service.dart';

/// Spotify sign-in (Authorization Code + PKCE).
///
/// The redirect uses a custom scheme, which the WebView cannot load. That is
/// the point: [NavigationDelegate.onNavigationRequest] intercepts it and
/// prevents navigation, so the authorization code is read in-process and no
/// Android intent-filter is needed to bounce back into the app.
class SpotifyLoginScreen extends StatefulWidget {
  const SpotifyLoginScreen({super.key});

  @override
  State<SpotifyLoginScreen> createState() => _SpotifyLoginScreenState();
}

class _SpotifyLoginScreenState extends State<SpotifyLoginScreen> {
  WebViewController? _controller;
  final _error = RxnString();
  final _busy = false.obs;

  late final String _verifier;
  late final String _state;

  @override
  void initState() {
    super.initState();
    final clientId = SpotifyAuthService.clientId;
    if (clientId == null) {
      // Guarded here too, not just at the call site: reaching Spotify's
      // /authorize without a client id returns an opaque error page.
      _error.value = 'spotifyNoClientId'.tr;
      return;
    }

    _verifier = SpotifyAuthService.generateCodeVerifier();
    // The app can be killed while the user is on Spotify's login page, so the
    // verifier is persisted rather than held only in memory.
    SpotifyAuthService.stashVerifier(_verifier);
    _state = SpotifyAuthService.generateCodeVerifier(length: 43);

    final url = SpotifyAuthService.buildAuthUrl(
      clientId: clientId,
      codeChallenge: SpotifyAuthService.codeChallengeS256(_verifier),
      state: _state,
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (!SpotifyAuthService.isRedirect(request.url)) {
            return NavigationDecision.navigate;
          }
          _handleRedirect(request.url);
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(url);
  }

  Future<void> _handleRedirect(String url) async {
    if (_busy.value) return;
    _busy.value = true;
    final result = SpotifyAuthService.parseRedirect(url, expectedState: _state);
    if (!result.ok) {
      _error.value = result.error;
      _busy.value = false;
      return;
    }
    try {
      await SpotifyAuthService().exchangeCode(
        code: result.code!,
        verifier: _verifier,
      );
      SpotifyAuthService.takeStashedVerifier();
      if (mounted) Get.back(result: true);
    } catch (e) {
      _error.value = e.toString().replaceFirst('Exception: ', '');
      _busy.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('spotifySignIn'.tr),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Get.back(result: false),
        ),
      ),
      body: Obx(() {
        final err = _error.value;
        if (err != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 12),
                  Text(err, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Get.back(result: false),
                    child: Text('close'.tr),
                  ),
                ],
              ),
            ),
          );
        }
        if (_controller == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Stack(
          children: [
            WebViewWidget(controller: _controller!),
            if (_busy.value) const LinearProgressIndicator(minHeight: 3),
          ],
        );
      }),
    );
  }
}
