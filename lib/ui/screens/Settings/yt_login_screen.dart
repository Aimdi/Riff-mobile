import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '/services/yt_auth_service.dart';
import '/ui/widgets/riff_header_bar.dart';

/// In-app Google sign-in for the optional YouTube connection. Once the
/// WebView lands back on music.youtube.com with an authenticated session,
/// the cookies are captured and the screen closes.
class YtLoginScreen extends StatefulWidget {
  const YtLoginScreen({super.key});

  @override
  State<YtLoginScreen> createState() => _YtLoginScreenState();
}

/// Decides when a finished page means the sign-in is done.
///
/// music.youtube.com can finish loading several times in a row (redirects),
/// and each finish used to capture the cookies and close the screen: two
/// successes closed the screen underneath as well.
class YtLoginCapture {
  YtLoginCapture({Future<bool> Function()? capture})
      : _capture = capture ?? YtAuthService.captureFromWebView;

  final Future<bool> Function() _capture;
  bool _done = false;

  /// True exactly once: for the first finished page whose cookies hold a
  /// signed-in session.
  Future<bool> onPageFinished(String url) async {
    if (_done || !url.startsWith('https://music.youtube.com')) return false;
    final bool ok;
    try {
      ok = await _capture();
    } catch (_) {
      // The cookie channel failed; the next finished page tries again.
      return false;
    }
    if (!ok || _done) return false;
    _done = true;
    return true;
  }
}

class _YtLoginScreenState extends State<YtLoginScreen> {
  late final WebViewController controller;
  final _capture = YtLoginCapture();

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) async {
          if (await _capture.onPageFinished(url) && mounted) {
            Get.back(result: true);
          }
        },
      ))
      ..loadRequest(Uri.parse(
          'https://accounts.google.com/ServiceLogin?service=youtube&continue=${Uri.encodeComponent("https://music.youtube.com")}'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RiffAppBar(AppBar(
        title: Text("connectYtAccount".tr),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Get.back(result: false),
        ),
      )),
      body: WebViewWidget(controller: controller),
    );
  }
}
