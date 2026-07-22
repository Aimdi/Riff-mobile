import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/ui/utils/theme_controller.dart';
import '/ui/widgets/snackbar.dart';

/// Companion plugin for [Seeker](https://github.com/jackBonadies/SeekerAndroid),
/// the open-source Soulseek client for Android. Riff cannot embed the full
/// Soulseek protocol; this plugin opens Seeker (or its store page) so you can
/// search the network there. Pair with the SoulSync plugin for server-side
/// Soulseek automation via slskd.
class SeekerScreen extends StatelessWidget {
  const SeekerScreen({super.key});

  static const packageId = 'com.companyname.andriodapp1';
  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=$packageId';
  static const izzyUrl =
      'https://apt.izzysoft.de/fdroid/index/apk/$packageId';
  static const githubUrl = 'https://github.com/jackBonadies/SeekerAndroid';

  Future<void> _openSeeker(BuildContext context) async {
    // Try launching the installed app via an Android intent URI, then fall
    // back to the Play Store listing.
    final intentUri = Uri.parse(
      'intent:#Intent;package=$packageId;scheme=package;end',
    );
    try {
      final ok = await launchUrl(intentUri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {/* fall through */}
    final market = Uri.parse('market://details?id=$packageId');
    if (await canLaunchUrl(market)) {
      await launchUrl(market, mode: LaunchMode.externalApplication);
      return;
    }
    final web = Uri.parse(playStoreUrl);
    final launched =
        await launchUrl(web, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'seekerOpenFailed'.tr, size: SanckBarSize.MEDIUM),
      );
    }
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Get.find<ThemeController>().accentColor.value;

    return Scaffold(
      backgroundColor: theme.canvasColor,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 70, 20, 120),
        children: [
          Text('seeker'.tr, style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text('seekerDes'.tr, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          Center(
            child: Icon(Icons.cloud_download_outlined, size: 64, color: accent),
          ),
          const SizedBox(height: 16),
          Text(
            'seekerExplain'.tr,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _openSeeker(context),
            icon: const Icon(Icons.open_in_new),
            label: Text('seekerOpenApp'.tr),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _open(playStoreUrl),
            icon: const Icon(Icons.shop_outlined),
            label: Text('seekerGetPlay'.tr),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _open(izzyUrl),
            icon: const Icon(Icons.android),
            label: Text('seekerGetIzzy'.tr),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _open(githubUrl),
            child: Text('pluginSource'.tr),
          ),
          const SizedBox(height: 16),
          Text('seekerSoulSyncNote'.tr, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
