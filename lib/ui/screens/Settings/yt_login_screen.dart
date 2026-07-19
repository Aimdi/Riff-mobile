import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '/services/yt_auth_service.dart';

/// In-app Google sign-in for the optional YouTube connection. Once the
/// WebView lands back on music.youtube.com with an authenticated session,
/// the cookies are captured and the screen closes.
class YtLoginScreen extends StatefulWidget {
  const YtLoginScreen({super.key});

  @override
  State<YtLoginScreen> createState() => _YtLoginScreenState();
}

class _YtLoginScreenState extends State<YtLoginScreen> {
  late final WebViewController controller;
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) async {
          if (_captured || !url.startsWith('https://music.youtube.com')) {
            return;
          }
          final ok = await YtAuthService.captureFromWebView();
          if (ok && mounted) {
            _captured = true;
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
      appBar: AppBar(
        title: Text("connectYtAccount".tr),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Get.back(result: false),
        ),
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}
