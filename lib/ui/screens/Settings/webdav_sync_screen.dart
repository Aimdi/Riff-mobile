import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/sync/webdav_client.dart';
import '/services/sync/webdav_sync_service.dart';
import '/ui/theme/riff_spacing.dart';
import '../Home/home_layout.dart';

/// Localisation key of the message for [e].
String webDavErrorKey(WebDavError e) => switch (e) {
      WebDavError.auth => 'syncErrAuth',
      WebDavError.notFound => 'syncErrNotFound',
      WebDavError.network => 'syncErrNetwork',
      WebDavError.conflict => 'syncErrConflict',
      WebDavError.badFile => 'syncErrBadFile',
      WebDavError.tooNew => 'syncErrTooNew',
      WebDavError.server => 'syncErrServer',
    };

String _when(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// Settings › Sync: a WebDAV folder (Nextcloud, a NAS, …) that keeps
/// podcast subscriptions, progress, bookmarks, segment marks and playlists
/// the same on every device. The password stays in secure storage.
class WebDavSyncScreen extends StatefulWidget {
  const WebDavSyncScreen({super.key});

  @override
  State<WebDavSyncScreen> createState() => _WebDavSyncScreenState();
}

class _WebDavSyncScreenState extends State<WebDavSyncScreen> {
  final _url = TextEditingController(text: WebDavSyncService.serverUrl);
  final _user = TextEditingController(text: WebDavSyncService.user);
  final _pass = TextEditingController(text: WebDavSyncService.password);
  bool _obscure = true;
  bool _testing = false;
  bool _auto = WebDavSyncService.autoSync;
  bool _saved = WebDavSyncService.configured;

  /// Result of the last test: null untested, '' fine, else an error key.
  String? _test;

  @override
  void initState() {
    super.initState();
    WebDavSyncService.loadStatus();
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  bool get _complete =>
      validWebDavBase(_url.text) && _user.text.trim().isNotEmpty;

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _test = null;
    });
    final err = await WebDavSyncService.testConnection(
        _url.text.trim(), _user.text.trim(), _pass.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _test = err == null ? '' : webDavErrorKey(err);
    });
  }

  Future<void> _save() async {
    await WebDavSyncService.saveAccount(
        url: _url.text, user: _user.text, password: _pass.text);
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('syncAccountSaved'.tr)));
  }

  Future<void> _syncNow() async {
    final out = await WebDavSyncService.syncNow();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(out.ok
          ? 'syncDone'
              .trParams({'received': '${out.received}', 'sent': '${out.sent}'})
          : webDavErrorKey(out.error!).tr),
    ));
  }

  Future<void> _forget() async {
    await WebDavSyncService.forget();
    if (!mounted) return;
    _url.clear();
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
    InputDecoration deco(String label, {String? hint, Widget? suffix}) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        );

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiffPageHeader('syncTitle'.tr, subtitle: 'syncDes'.tr),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(
                  left: HomeLayout.gutter,
                  top: RiffSpacing.sm,
                  right: HomeLayout.gutter,
                  bottom: RiffSpacing.listEnd),
              children: [
                TextField(
                  controller: _url,
                  decoration: deco('syncServerUrl'.tr,
                      hint:
                          'https://cloud.example.com/remote.php/dav/files/me/'),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _test = null),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _user,
                  decoration: deco('username'.tr),
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _test = null),
                ),
                const SizedBox(height: 10),
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
                const SizedBox(height: 6),
                Text('syncAppPasswordHint'.tr,
                    style: homeCardSubtitleStyle(context)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _complete && !_testing ? _runTest : null,
                        icon: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi_tethering_rounded),
                        label: Text('syncTest'.tr),
                      ),
                    ),
                    const SizedBox(width: 10),
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
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Icon(
                            _test!.isEmpty
                                ? Icons.check_circle_rounded
                                : Icons.error_outline_rounded,
                            size: 18,
                            color: _test!.isEmpty
                                ? theme.colorScheme.secondary
                                : theme.colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              _test!.isEmpty ? 'syncTestOk'.tr : _test!.tr,
                              style: TextStyle(
                                  color: _test!.isEmpty
                                      ? null
                                      : theme.colorScheme.error)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('syncAuto'.tr),
                  subtitle: Text('syncAutoDes'.tr,
                      style: homeCardSubtitleStyle(context)),
                  value: _auto,
                  onChanged: _saved
                      ? (v) async {
                          await WebDavSyncService.setAutoSync(v);
                          setState(() => _auto = v);
                        }
                      : null,
                ),
                const SizedBox(height: 6),
                Obx(() {
                  final busy = WebDavSyncService.syncing.value;
                  return FilledButton.tonalIcon(
                    onPressed: _saved && !busy ? _syncNow : null,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync_rounded),
                    label: Text(busy ? 'syncRunning'.tr : 'syncNow'.tr),
                  );
                }),
                const SizedBox(height: 8),
                Obx(() {
                  final at = WebDavSyncService.lastSyncAt.value;
                  final err = WebDavSyncService.lastError.value;
                  final parts = <String>[
                    if (at > 0) 'syncLast'.trParams({'time': _when(at)}),
                    if (err.isNotEmpty)
                      webDavErrorKey(WebDavError.values.firstWhere(
                          (e) => e.name == err,
                          orElse: () => WebDavError.server)).tr,
                  ];
                  if (parts.isEmpty) return const SizedBox.shrink();
                  return Text(parts.join('\n'),
                      textAlign: TextAlign.center,
                      style: homeCardSubtitleStyle(context).copyWith(
                          color:
                              err.isNotEmpty ? theme.colorScheme.error : null));
                }),
                const SizedBox(height: 22),
                Text('syncWhat'.tr, style: homeSectionTitleStyle(context)),
                const SizedBox(height: 6),
                Text('syncWhatDes'.tr, style: homeCardSubtitleStyle(context)),
                if (_saved) ...[
                  const SizedBox(height: 22),
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
