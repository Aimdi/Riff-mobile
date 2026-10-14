import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/riff_equalizer.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/utils/sheet_insets.dart';
import '/utils/helper.dart';
import 'riff_sheet.dart';

/// Riff's equalizer (Spotify's): on or off, the presets, a slider per band
/// of the phone's equalizer, and the phone's own equalizer for those who
/// prefer it.
Future<void> showEqualizerSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => const EqualizerSheet(),
    );

/// Half a dB a step.
const _stepMb = 50;

String _hz(int hz) {
  if (hz < 1000) return '$hz Hz';
  final k = hz / 1000;
  return '${k.toStringAsFixed(k >= 10 || hz % 1000 == 0 ? 0 : 1)} kHz';
}

String _db(int mb) {
  final db = (mb / 100).toStringAsFixed(1);
  return mb > 0 ? '+$db dB' : '$db dB';
}

/// A preset's name: 'bassBooster' reads 'eqPresetBassBooster'.
String equalizerPresetLabel(String preset) =>
    'eqPreset${preset[0].toUpperCase()}${preset.substring(1)}'.tr;

class EqualizerSheet extends StatefulWidget {
  const EqualizerSheet({super.key});

  @override
  State<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<EqualizerSheet> {
  late final Future<EqualizerLayout?> _layout =
      Get.find<PlayerController>().equalizerLayout();
  bool _on = RiffEqualizer.enabled;
  String _preset = RiffEqualizer.preset;
  List<int>? _levels;

  /// What the bands are at: the levels moved by hand, else the preset's.
  List<int> _levelsFor(EqualizerLayout layout) {
    final saved = RiffEqualizer.levelsMb;
    if (_preset == RiffEqualizer.custom &&
        saved.length == layout.centersHz.length) {
      return saved;
    }
    return equalizerLevelsFor(
        equalizerPresets[_preset] ?? equalizerPresets['flat']!, layout);
  }

  Future<void> _save() async {
    await RiffEqualizer.save(enabled: _on, preset: _preset, levelsMb: _levels);
    Get.find<PlayerController>().applyAudioFx();
  }

  void _pick(String preset, EqualizerLayout layout) {
    setState(() {
      _preset = preset;
      _levels = _levelsFor(layout);
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: RiffSpacing.sm +
                sheetBottomInset(context, liftAboveMiniPlayer: false)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const RiffSheetHandle(),
              RiffSheetTitle('equalizer'.tr),
              FutureBuilder<EqualizerLayout?>(
                future: _layout,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(RiffSpacing.xxl),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final layout = snap.data;
                  if (layout == null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: RiffSpacing.xl, vertical: RiffSpacing.lg),
                      child: Text('equalizerUnavailable'.tr,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: muted)),
                    );
                  }
                  final levels = _levels ??= _levelsFor(layout);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RiffSheetTile(
                        icon: Icons.equalizer_rounded,
                        title: 'equalizerOn'.tr,
                        trailing: Switch(
                          value: _on,
                          onChanged: (on) {
                            setState(() => _on = on);
                            _save();
                          },
                        ),
                        onTap: () {
                          setState(() => _on = !_on);
                          _save();
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: RiffSpacing.lg,
                            vertical: RiffSpacing.sm),
                        child: Wrap(
                          spacing: RiffSpacing.sm,
                          runSpacing: RiffSpacing.sm,
                          children: [
                            for (final preset in equalizerPresets.keys)
                              RiffChoiceChip(
                                label: equalizerPresetLabel(preset),
                                selected: preset == _preset,
                                onTap: () => _pick(preset, layout),
                              ),
                            if (_preset == RiffEqualizer.custom)
                              RiffChoiceChip(
                                label:
                                    equalizerPresetLabel(RiffEqualizer.custom),
                                selected: true,
                                onTap: () {},
                              ),
                          ],
                        ),
                      ),
                      for (var i = 0; i < layout.centersHz.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(
                              left: RiffSpacing.lg,
                              top: RiffSpacing.xs,
                              right: RiffSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_hz(layout.centersHz[i]),
                                      style: theme.textTheme.labelMedium),
                                  Text(_db(levels[i]),
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(color: muted)),
                                ],
                              ),
                              Slider(
                                min: layout.minMb.toDouble(),
                                max: layout.maxMb.toDouble(),
                                divisions:
                                    (layout.maxMb - layout.minMb) ~/ _stepMb,
                                value: levels[i]
                                    .clamp(layout.minMb, layout.maxMb)
                                    .toDouble(),
                                label: _db(levels[i]),
                                // Off: the bands wait as they are.
                                onChanged: !_on
                                    ? null
                                    : (v) => setState(() {
                                          levels[i] = v.round();
                                          _preset = RiffEqualizer.custom;
                                        }),
                                onChangeEnd: (_) => _save(),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: RiffSpacing.sm, vertical: RiffSpacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () async {
                        final layout = await _layout;
                        if (layout != null && mounted) _pick('flat', layout);
                      },
                      child: Text('resetToDefault'.tr),
                    ),
                    TextButton(
                      onPressed: () async {
                        try {
                          await Get.find<PlayerController>().openEqualizer();
                        } catch (e) {
                          printERROR(e);
                        }
                      },
                      child: Text('phoneEqualizer'.tr),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
