import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/plugin_service.dart';
import '/ui/navigator.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/snackbar.dart';

/// Catalog of optional plugins that extend Riff.
///
/// Offered plugins can be installed (enabled) from this screen.
/// Bundled plugins: Torrent Search, SoulSync, and Seeker.
class PluginsScreen extends StatelessWidget {
  const PluginsScreen({super.key});

  static const List<_PluginOffer> _offers = [
    _PluginOffer(
      id: PluginIds.torrentsDigger,
      nameKey: 'torrentsDigger',
      desKey: 'torrentsDiggerPluginDes',
      sourceUrl: 'https://gitlab.com/ForTheCommunity/torrentsdigger',
    ),
    _PluginOffer(
      id: PluginIds.soulSync,
      nameKey: 'soulSync',
      desKey: 'soulSyncPluginDes',
      sourceUrl: 'https://github.com/Nezreka/SoulSync',
    ),
    _PluginOffer(
      id: PluginIds.seeker,
      nameKey: 'seeker',
      desKey: 'seekerPluginDes',
      sourceUrl: 'https://github.com/jackBonadies/SeekerAndroid',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = Get.find<ThemeController>().accentColor.value;
    final theme = Theme.of(context);
    final plugins = Get.find<PluginService>();

    return Scaffold(
      backgroundColor: theme.canvasColor,
      body: Padding(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 70),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('plugins'.tr, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('pluginsDes'.tr, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            Expanded(
              child: Obx(() {
                // Touch obs so the list rebuilds on install/uninstall.
                final _ = plugins.installed.length;
                if (_offers.isEmpty) {
                  return _EmptyPluginsState(accent: accent);
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: _offers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final offer = _offers[index];
                    return _PluginOfferTile(
                      offer: offer,
                      accent: accent,
                      installed: plugins.isInstalled(offer.id),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPluginsState extends StatelessWidget {
  const _EmptyPluginsState({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_outlined, size: 56, color: accent),
            const SizedBox(height: 16),
            Text(
              'pluginsEmptyTitle'.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'pluginsEmptyDes'.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _PluginOffer {
  const _PluginOffer({
    required this.id,
    required this.nameKey,
    required this.desKey,
    this.sourceUrl,
  });

  final String id;
  final String nameKey;
  final String desKey;
  final String? sourceUrl;
}

class _PluginOfferTile extends StatelessWidget {
  const _PluginOfferTile({
    required this.offer,
    required this.accent,
    required this.installed,
  });

  final _PluginOffer offer;
  final Color accent;
  final bool installed;

  Future<void> _install(BuildContext context) async {
    await Get.find<PluginService>().install(offer.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(context, 'pluginInstalled'.tr, size: SanckBarSize.MEDIUM),
    );
  }

  Future<void> _uninstall(BuildContext context) async {
    await Get.find<PluginService>().uninstall(offer.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(context, 'pluginUninstalled'.tr, size: SanckBarSize.MEDIUM),
    );
  }

  void _open() {
    if (offer.id == PluginIds.torrentsDigger) {
      Get.toNamed(
        ScreenNavigationSetup.torrentSearchScreen,
        id: ScreenNavigationSetup.id,
      );
    } else if (offer.id == PluginIds.soulSync) {
      Get.toNamed(
        ScreenNavigationSetup.soulSyncScreen,
        id: ScreenNavigationSetup.id,
      );
    } else if (offer.id == PluginIds.seeker) {
      Get.toNamed(
        ScreenNavigationSetup.seekerScreen,
        id: ScreenNavigationSetup.id,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(
            installed ? Icons.extension : Icons.extension_outlined,
            color: accent,
          ),
          title: Text(offer.nameKey.tr),
          subtitle: Text(offer.desKey.tr, style: theme.textTheme.bodyMedium),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
          child: Row(
            children: [
              if (installed) ...[
                FilledButton.icon(
                  onPressed: _open,
                  icon: const Icon(Icons.search, size: 18),
                  label: Text('openPlugin'.tr),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _uninstall(context),
                  child: Text('uninstallPlugin'.tr),
                ),
              ] else
                FilledButton.icon(
                  onPressed: () => _install(context),
                  icon: const Icon(Icons.download, size: 18),
                  label: Text('downloadPlugin'.tr),
                ),
              if (offer.sourceUrl != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(offer.sourceUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text('pluginSource'.tr),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
