import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/utils/theme_controller.dart';

/// Catalog of optional plugins that extend Riff.
///
/// The marketplace UI is shipped now so Settings can offer downloads;
/// the offered list is empty until plugins are published.
class PluginsScreen extends StatelessWidget {
  const PluginsScreen({super.key});

  /// Placeholder catalog — populate when plugins are released.
  static const List<_PluginOffer> _offers = <_PluginOffer>[];

  @override
  Widget build(BuildContext context) {
    final accent = Get.find<ThemeController>().accentColor.value;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.canvasColor,
      body: Padding(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 70),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("plugins".tr, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              "pluginsDes".tr,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _offers.isEmpty
                  ? _EmptyPluginsState(accent: accent)
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: _offers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final offer = _offers[index];
                        return _PluginOfferTile(offer: offer, accent: accent);
                      },
                    ),
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
              "pluginsEmptyTitle".tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              "pluginsEmptyDes".tr,
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
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
}

class _PluginOfferTile extends StatelessWidget {
  const _PluginOfferTile({required this.offer, required this.accent});

  final _PluginOffer offer;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(Icons.extension, color: accent),
      title: Text(offer.name),
      subtitle: Text(offer.description, style: theme.textTheme.bodyMedium),
      trailing: TextButton(
        onPressed: () {
          // Download hook for when plugins ship.
        },
        child: Text("downloadPlugin".tr),
      ),
    );
  }
}
