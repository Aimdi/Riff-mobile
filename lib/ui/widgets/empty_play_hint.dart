import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../navigator.dart';
import '../player/player_controller.dart';
import 'snackbar.dart';

/// Actions offered when a list has nothing to play yet.
List<String> emptyPlayHintActionKeys() => const ['riffWave', 'search'];

/// Library / Explore / empty search lists: start Wave or open Search.
class EmptyPlayHint extends StatelessWidget {
  const EmptyPlayHint({super.key, required this.message});

  final String message;

  Future<void> _startWave(BuildContext context) async {
    if (!Get.isRegistered<PlayerController>()) return;
    try {
      final ok = await Get.find<PlayerController>().startRiffWave();
      if (!context.mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context,
          'riffWaveEmpty'.tr,
          size: SanckBarSize.MEDIUM,
        ));
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(snackbar(
        context,
        'networkError'.tr,
        size: SanckBarSize.MEDIUM,
      ));
    }
  }

  void _openSearch() {
    Get.toNamed(
      ScreenNavigationSetup.searchScreen,
      id: ScreenNavigationSetup.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _startWave(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                  label: Text('riffWave'.tr),
                ),
                OutlinedButton.icon(
                  onPressed: _openSearch,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.textTheme.titleMedium?.color,
                    side: BorderSide(
                      color: theme.dividerColor.withOpacity(0.8),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.search, size: 18),
                  label: Text('search'.tr),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
