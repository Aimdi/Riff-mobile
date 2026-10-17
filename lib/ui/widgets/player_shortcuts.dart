import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '../navigator.dart';
import '../player/player_controller.dart';
import '../screens/Search/components/search_pill.dart';

/// One keyboard shortcut: its keys, its name (a translation key) and what
/// it does.
class PlayerShortcut {
  const PlayerShortcut(this.activator, this.labelKey, this.run,
      {this.repeats = false});

  final SingleActivator activator;
  final String labelKey;
  final void Function(PlayerController player) run;

  /// Goes on while the keys are held (seeking, volume).
  final bool repeats;
}

/// Ctrl, or ⌘ on macOS.
SingleActivator _command(LogicalKeyboardKey key) {
  final mac = defaultTargetPlatform == TargetPlatform.macOS;
  return SingleActivator(key, control: !mac, meta: mac);
}

/// Volume steps for Ctrl+↑ / Ctrl+↓.
const int _volumeStep = 10;

/// The shortcuts, much as in Spotify's desktop app.
List<PlayerShortcut> playerShortcuts() => [
      PlayerShortcut(const SingleActivator(LogicalKeyboardKey.space),
          'playPauseShortcut', (p) => p.playPause()),
      PlayerShortcut(
          _command(LogicalKeyboardKey.arrowRight), 'next', (p) => p.next()),
      PlayerShortcut(
          _command(LogicalKeyboardKey.arrowLeft), 'previous', (p) => p.prev()),
      PlayerShortcut(
          const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true),
          'seekForward10',
          (p) => p.seekBy(const Duration(seconds: 10)),
          repeats: true),
      PlayerShortcut(
          const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true),
          'seekBack10',
          (p) => p.seekBy(const Duration(seconds: -10)),
          repeats: true),
      PlayerShortcut(_command(LogicalKeyboardKey.arrowUp), 'volumeUp',
          (p) => p.setVolume((p.volume.value + _volumeStep).clamp(0, 100)),
          repeats: true),
      PlayerShortcut(_command(LogicalKeyboardKey.arrowDown), 'volumeDown',
          (p) => p.setVolume((p.volume.value - _volumeStep).clamp(0, 100)),
          repeats: true),
      PlayerShortcut(_command(LogicalKeyboardKey.keyS), 'shuffle',
          (p) => p.toggleShuffleMode()),
      PlayerShortcut(_command(LogicalKeyboardKey.keyR), 'repeat',
          (p) => p.cycleRepeatMode()),
      PlayerShortcut(
          _command(LogicalKeyboardKey.keyF), 'search', (_) => _openSearch()),
      PlayerShortcut(_command(LogicalKeyboardKey.slash), 'keyboardShortcuts',
          (_) => showKeyboardShortcuts()),
    ];

/// Search, where the screens' navigator is (not over a full-screen page).
void _openSearch() {
  if (Get.nestedKey(ScreenNavigationSetup.id)?.currentState == null) return;
  SearchLauncherField.openSearch();
}

/// The keys of [activator] as people read them: "Ctrl + →".
String describeShortcut(SingleActivator activator) {
  final key = activator.trigger;
  final name = switch (key) {
    LogicalKeyboardKey.space => 'Space',
    LogicalKeyboardKey.arrowRight => '→',
    LogicalKeyboardKey.arrowLeft => '←',
    LogicalKeyboardKey.arrowUp => '↑',
    LogicalKeyboardKey.arrowDown => '↓',
    _ => key.keyLabel.toUpperCase(),
  };
  return [
    if (activator.control) 'Ctrl',
    if (activator.meta) '⌘',
    if (activator.alt) 'Alt',
    if (activator.shift) 'Shift',
    name,
  ].join(' + ');
}

/// Whether the focus is in a text field, whose keys are its own.
bool _typing() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorStateOfType<EditableTextState>() != null;
}

/// Runs the shortcut [event] is for, if any.
KeyEventResult handlePlayerShortcut(
    KeyEvent event, List<PlayerShortcut> shortcuts) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  if (_typing() || !Get.isRegistered<PlayerController>()) {
    return KeyEventResult.ignored;
  }
  for (final shortcut in shortcuts) {
    if (!shortcut.activator.accepts(event, HardwareKeyboard.instance)) {
      continue;
    }
    if (event is KeyDownEvent || shortcut.repeats) {
      shortcut.run(Get.find<PlayerController>());
    }
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

/// Keyboard shortcuts for playback across the app, as in Spotify's desktop
/// app (see [playerShortcuts]; Ctrl+/ lists them). Above every screen, so
/// they work wherever the focus is, except while typing.
class PlayerShortcuts extends StatelessWidget {
  const PlayerShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shortcuts = playerShortcuts();
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => handlePlayerShortcut(event, shortcuts),
      child: child,
    );
  }
}

/// Lists the shortcuts in a dialog (Ctrl+/).
void showKeyboardShortcuts() {
  final context = Get.overlayContext ?? Get.context;
  if (context == null) return;
  showDialog<void>(
    context: context,
    builder: (_) => const KeyboardShortcutsDialog(),
  );
}

class KeyboardShortcutsDialog extends StatelessWidget {
  const KeyboardShortcutsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return AlertDialog(
      title: Text('keyboardShortcuts'.tr),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final shortcut in playerShortcuts())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: RiffSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(shortcut.labelKey.tr,
                          style: theme.textTheme.bodyLarge),
                    ),
                    const SizedBox(width: RiffSpacing.lg),
                    Text(describeShortcut(shortcut.activator),
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: muted)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('close'.tr),
        ),
      ],
    );
  }
}
