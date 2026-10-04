import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/plugin_service.dart';
import '/ui/navigator.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/snackbar.dart';
import '../../utils/riff_tokens.dart';
import '../Home/home_layout.dart';

/// Catalog of optional plugins that extend Riff.
///
/// Offered plugins can be installed (enabled) from this screen.
/// Bundled plugins: Torrent Search, SoulSync, and Soulseek.
class PluginsScreen extends StatelessWidget {
  const PluginsScreen({super.key});

  static const List<_PluginOffer> _offers = [
    _PluginOffer(
      id: PluginIds.torrentSearch,
      nameKey: 'torrentSearch',
      desKey: 'torrentSearchPluginDes',
      sourceUrl: 'https://torrents-csv.com',
    ),
    _PluginOffer(
      id: PluginIds.soulSync,
      nameKey: 'soulSync',
      desKey: 'soulSyncPluginDes',
      sourceUrl: 'https://github.com/Nezreka/SoulSync',
    ),
    _PluginOffer(
      id: PluginIds.spotify,
      nameKey: 'spotifyBridge',
      desKey: 'spotifyBridgePluginDes',
      sourceUrl: 'https://developer.spotify.com/documentation/web-api',
    ),
    _PluginOffer(
      id: PluginIds.seeker,
      nameKey: 'soulseek',
      desKey: 'soulseekPluginDes',
      sourceUrl: 'https://github.com/nicotine-plus/nicotine-plus',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = Get.find<ThemeController>().accentColor.value;
    final theme = Theme.of(context);
    final plugins = Get.find<PluginService>();

    return Scaffold(
      backgroundColor: theme.canvasColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiffPageHeader('plugins'.tr,
              onBack: () => Get.back(id: ScreenNavigationSetup.id)),
          Padding(
            padding: const EdgeInsets.only(
                left: HomeLayout.gutter,
                right: HomeLayout.gutter,
                bottom: RiffSpacing.lg),
            child: Text('pluginsDes'.tr, style: homeCardSubtitleStyle(context)),
          ),
          Expanded(
            child: Obx(() {
              // Touch obs so the list rebuilds on install/uninstall.
              final _ = plugins.installed.length;
              if (_offers.isEmpty) {
                return _EmptyPluginsState(accent: accent);
              }
              return ListView.separated(
                padding: const EdgeInsets.only(
                    left: HomeLayout.gutter,
                    right: HomeLayout.gutter,
                    bottom: RiffSpacing.unit * 30),
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
    final isSoulseek = offer.id == PluginIds.seeker;
    if (isSoulseek && context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text('soulseekInstalling'.tr)),
            ],
          ),
        ),
      );
      // Brief pause so the “install engine” moment is visible — the client
      // ships in-app; install still just enables the plugin.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    await Get.find<PluginService>().install(offer.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(
        context,
        isSoulseek ? 'soulseekInstalled'.tr : 'pluginInstalled'.tr,
        size: SanckBarSize.MEDIUM,
      ),
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
    if (offer.id == PluginIds.torrentSearch) {
      Get.toNamed(
        ScreenNavigationSetup.torrentSearchScreen,
        id: ScreenNavigationSetup.id,
      );
    } else if (offer.id == PluginIds.soulSync) {
      Get.toNamed(
        ScreenNavigationSetup.soulSyncScreen,
        id: ScreenNavigationSetup.id,
      );
    } else if (offer.id == PluginIds.spotify) {
      Get.toNamed(
        ScreenNavigationSetup.spotifyBridgeScreen,
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
    final fg = Theme.of(context).textTheme.titleMedium?.color;
    return Container(
      padding: const EdgeInsets.only(
          left: RiffSpacing.lg,
          top: RiffSpacing.lg,
          right: RiffSpacing.lg,
          bottom: RiffSpacing.md),
      decoration: BoxDecoration(
        color: homeTileColor(context),
        borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
                ),
                child: Icon(
                  installed ? Icons.extension : Icons.extension_outlined,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(offer.nameKey.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: fg)),
              ),
              if (installed)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('installed'.tr,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: accent)),
                ),
            ],
          ),
          // A description without a translation would show its raw key.
          if (offer.desKey.tr != offer.desKey) ...[
            const SizedBox(height: 10),
            Text(offer.desKey.tr, style: homeCardSubtitleStyle(context)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (installed) ...[
                FilledButton.icon(
                  onPressed: _open,
                  style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text('openPlugin'.tr),
                ),
                OutlinedButton(
                  onPressed: () => _uninstall(context),
                  style: OutlinedButton.styleFrom(foregroundColor: fg),
                  child: Text('uninstallPlugin'.tr),
                ),
              ] else
                FilledButton.icon(
                  onPressed: () => _install(context),
                  style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text('downloadPlugin'.tr),
                ),
              if (offer.sourceUrl != null)
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(offer.sourceUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                  style: TextButton.styleFrom(foregroundColor: accent),
                  child: Text('pluginSource'.tr),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
