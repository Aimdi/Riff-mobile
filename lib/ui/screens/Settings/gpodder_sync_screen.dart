import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/sync/gpodder_sync.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '../Home/home_layout.dart';

/// Localisation key of the message for [e].
String gpodderErrorKey(GpodderError e) => switch (e) {
      GpodderError.auth => 'syncErrAuth',
      GpodderError.notFound => 'gpodderErrNotFound',
      GpodderError.network => 'syncErrNetwork',
      GpodderError.server => 'syncErrServer',
    };

String _when(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// Settings › Podcast sync (gpodder): the shows you follow and where you
/// are in each episode, in step with AntennaPod, Kasts and the other gpodder
/// apps, through a Nextcloud server (the GPodder Sync app) or gpodder.net.
/// The password stays in secure storage.
class GpodderSyncScreen extends StatefulWidget {
  const GpodderSyncScreen({super.key});

  @override
  State<GpodderSyncScreen> createState() => _GpodderSyncScreenState();
}

class _GpodderSyncScreenState extends State<GpodderSyncScreen> {
  GpodderKind _kind = GpodderSync.kind;
  late final _server = TextEditingController(
      text: GpodderSync.server.isNotEmpty
          ? GpodderSync.server
          : _kind == GpodderKind.gpodderNet
              ? GpodderSync.gpodderNetServer
              : '');
  final _user = TextEditingController(text: GpodderSync.user);
  final _pass = TextEditingController(text: GpodderSync.password);
  bool _obscure = true;
  bool _testing = false;
  bool _auto = GpodderSync.autoSync;
  bool _saved = GpodderSync.configured;

  /// Result of the last test: null untested, '' fine, else an error key.
  String? _test;

  @override
  void initState() {
    super.initState();
    GpodderSync.loadStatus();
  }

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  bool get _complete {
    final server = Uri.tryParse(_server.text.trim());
    return server != null &&
        (server.isScheme('https') || server.isScheme('http')) &&
        server.host.isNotEmpty &&
        _user.text.trim().isNotEmpty;
  }

  void _choose(GpodderKind kind) {
    if (kind == _kind) return;
    setState(() {
      // gpodder.net's own address, unless one was typed.
      if (kind == GpodderKind.gpodderNet && _server.text.trim().isEmpty) {
        _server.text = GpodderSync.gpodderNetServer;
      } else if (kind == GpodderKind.nextcloud &&
          _server.text.trim() == GpodderSync.gpodderNetServer) {
        _server.clear();
      }
      _kind = kind;
      _test = null;
    });
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _test = null;
    });
    final err = await GpodderSync.testConnection(
        kind: _kind,
        server: _server.text.trim(),
        user: _user.text.trim(),
        password: _pass.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _test = err == null ? '' : gpodderErrorKey(err);
    });
  }

  Future<void> _save() async {
    await GpodderSync.saveAccount(
        kind: _kind,
        server: _server.text,
        user: _user.text,
        password: _pass.text);
    if (!mounted) return;
    setState(() {
      _saved = true;
      _auto = GpodderSync.autoSync;
    });
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text('syncAccountSaved'.tr)));
  }

  Future<void> _syncNow() async {
    final out = await GpodderSync.syncNow();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(out.ok
          ? 'gpodderDone'.trParams({
              'shows': '${out.followed + out.unfollowed}',
              'episodes': '${out.episodes}',
              'sent': '${out.sent}',
            })
          : gpodderErrorKey(out.error!).tr),
    ));
  }

  Future<void> _forget() async {
    await GpodderSync.forget();
    if (!mounted) return;
    _server.text =
        _kind == GpodderKind.gpodderNet ? GpodderSync.gpodderNetServer : '';
    _user.clear();
    _pass.clear();
    setState(() {
      _saved = false;
      _auto = false;
      _test = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Border, label and focus ring come from the theme (§5.8).
    InputDecoration deco(String label, {String? hint, Widget? suffix}) =>
        InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix);
    const spinner = SizedBox.square(
        dimension: RiffComponentSizes.buttonSpinner,
        child: CircularProgressIndicator(
            strokeWidth: RiffComponentSizes.spinnerStroke));

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiffPageHeader('gpodderSync'.tr, subtitle: 'gpodderSyncDes'.tr),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(
                  left: HomeLayout.gutter,
                  top: RiffSpacing.sm,
                  right: HomeLayout.gutter,
                  bottom: RiffSpacing.listEnd),
              children: [
                Wrap(
                  spacing: RiffSpacing.sm,
                  runSpacing: RiffSpacing.sm,
                  children: [
                    for (final kind in GpodderKind.values)
                      ChoiceChip(
                        label: Text(kind == GpodderKind.nextcloud
                            ? 'gpodderNextcloud'.tr
                            : 'gpodderNet'.tr),
                        selected: _kind == kind,
                        onSelected: (_) => _choose(kind),
                      ),
                  ],
                ),
                const SizedBox(height: RiffSpacing.md),
                TextField(
                  controller: _server,
                  decoration: deco('gpodderServer'.tr,
                      hint: _kind == GpodderKind.nextcloud
                          ? 'https://cloud.example.com'
                          : GpodderSync.gpodderNetServer),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _test = null),
                ),
                const SizedBox(height: RiffSpacing.sm),
                TextField(
                  controller: _user,
                  decoration: deco('username'.tr),
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _test = null),
                ),
                const SizedBox(height: RiffSpacing.sm),
                TextField(
                  controller: _pass,
                  obscureText: _obscure,
                  autocorrect: false,
                  decoration: deco('password'.tr,
                      suffix: IconButton(
                        tooltip: _obscure
                            ? 'syncShowPassword'.tr
                            : 'syncHidePassword'.tr,
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      )),
                  onChanged: (_) => setState(() => _test = null),
                ),
                const SizedBox(height: RiffSpacing.xs),
                Text(
                    _kind == GpodderKind.nextcloud
                        ? 'gpodderNextcloudHint'.tr
                        : 'gpodderNetHint'.tr,
                    style: homeCardSubtitleStyle(context)),
                const SizedBox(height: RiffSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _complete && !_testing ? _runTest : null,
                        icon: _testing
                            ? spinner
                            : const Icon(Icons.wifi_tethering_rounded),
                        label: Text('syncTest'.tr),
                      ),
                    ),
                    const SizedBox(width: RiffSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _complete ? _save : null,
                        icon: const Icon(Icons.check_rounded),
                        label: Text('syncSave'.tr),
                      ),
                    ),
                  ],
                ),
                if (_test != null)
                  Padding(
                    padding: const EdgeInsets.only(top: RiffSpacing.sm),
                    child: Row(
                      children: [
                        Icon(
                            _test!.isEmpty
                                ? Icons.check_circle_rounded
                                : Icons.error_outline_rounded,
                            size: RiffComponentSizes.inlineIcon,
                            color: _test!.isEmpty
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.error),
                        const SizedBox(width: RiffSpacing.sm),
                        Expanded(
                          child: Text(
                              _test!.isEmpty ? 'syncTestOk'.tr : _test!.tr,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: _test!.isEmpty
                                      ? null
                                      : theme.colorScheme.error)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: RiffSpacing.lg),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('syncAuto'.tr, style: theme.textTheme.bodyLarge),
                  subtitle: Text('syncAutoDes'.tr,
                      style: homeCardSubtitleStyle(context)),
                  value: _auto,
                  onChanged: _saved
                      ? (v) async {
                          await GpodderSync.setAutoSync(v);
                          if (mounted) setState(() => _auto = v);
                        }
                      : null,
                ),
                const SizedBox(height: RiffSpacing.xs),
                Obx(() {
                  final busy = GpodderSync.syncing.value;
                  return FilledButton.tonalIcon(
                    onPressed: _saved && !busy ? _syncNow : null,
                    icon: busy ? spinner : const Icon(Icons.sync_rounded),
                    label: Text(busy ? 'syncRunning'.tr : 'syncNow'.tr),
                  );
                }),
                const SizedBox(height: RiffSpacing.sm),
                Obx(() {
                  final at = GpodderSync.lastSyncAt.value;
                  final err = GpodderSync.lastError.value;
                  final parts = <String>[
                    if (at > 0) 'syncLast'.trParams({'time': _when(at)}),
                    if (err.isNotEmpty)
                      gpodderErrorKey(GpodderError.values.firstWhere(
                          (e) => e.name == err,
                          orElse: () => GpodderError.server)).tr,
                  ];
                  if (parts.isEmpty) return const SizedBox.shrink();
                  return Text(parts.join('\n'),
                      textAlign: TextAlign.center,
                      style: homeCardSubtitleStyle(context).copyWith(
                          color:
                              err.isNotEmpty ? theme.colorScheme.error : null));
                }),
                const SizedBox(height: RiffSpacing.xl),
                Text('syncWhat'.tr, style: homeSectionTitleStyle(context)),
                const SizedBox(height: RiffSpacing.xs),
                Text('gpodderWhatDes'.tr,
                    style: homeCardSubtitleStyle(context)),
                if (_saved) ...[
                  const SizedBox(height: RiffSpacing.xl),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _forget,
                      icon: const Icon(Icons.link_off_rounded),
                      label: Text('syncForget'.tr),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
