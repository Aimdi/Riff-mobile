import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/slskd_service.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/snackbar.dart';

/// In-app Soulseek search via a self-hosted [slskd](https://github.com/slskd/slskd)
/// server. Optionally opens the Seeker Android client as a companion.
class SeekerScreen extends StatelessWidget {
  const SeekerScreen({super.key});

  static const seekerPackageId = 'com.companyname.andriodapp1';
  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=$seekerPackageId';
  static const izzyUrl =
      'https://apt.izzysoft.de/fdroid/index/apk/$seekerPackageId';
  static const slskdUrl = 'https://github.com/slskd/slskd';
  static const seekerGithubUrl = 'https://github.com/jackBonadies/SeekerAndroid';

  @override
  Widget build(BuildContext context) {
    final svc = Get.find<SlskdService>();
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.canvasColor,
      body: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 70),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('soulseek'.tr, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('soulseekDes'.tr, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(
                () => svc.isConnected.value
                    ? const _SoulseekSearchView()
                    : const _SlskdLoginForm(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlskdLoginForm extends StatefulWidget {
  const _SlskdLoginForm();

  @override
  State<_SlskdLoginForm> createState() => _SlskdLoginFormState();
}

class _SlskdLoginFormState extends State<_SlskdLoginForm> {
  final _url = TextEditingController(text: 'http://127.0.0.1:5030');
  final _key = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await Get.find<SlskdService>().connect(
        serverUrl: _url.text,
        apiKey: _key.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'slskdConnected'.tr, size: SanckBarSize.MEDIUM),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'slskdConnectFailed'.tr, size: SanckBarSize.MEDIUM),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _openSeekerApp() async {
    final intentUri = Uri.parse(
      'intent:#Intent;package=${SeekerScreen.seekerPackageId};scheme=package;end',
    );
    try {
      final ok =
          await launchUrl(intentUri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {/* fall through */}
    await _open(SeekerScreen.playStoreUrl);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 120, top: 4),
      children: [
        Text('slskdConnectTitle'.tr, style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('slskdConnectDes'.tr, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'slskdServerUrl'.tr,
            hintText: 'http://192.168.1.10:5030',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'slskdApiKey'.tr,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('slskdConnect'.tr),
        ),
        const SizedBox(height: 20),
        Text('slskdHint'.tr, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => _open(SeekerScreen.slskdUrl),
          child: Text('slskdDocs'.tr),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Text('seekerCompanionTitle'.tr, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('seekerCompanionDes'.tr, style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _openSeekerApp,
          icon: const Icon(Icons.open_in_new),
          label: Text('seekerOpenApp'.tr),
        ),
        TextButton(
          onPressed: () => _open(SeekerScreen.seekerGithubUrl),
          child: Text('pluginSource'.tr),
        ),
      ],
    );
  }
}

class _SoulseekSearchView extends StatefulWidget {
  const _SoulseekSearchView();

  @override
  State<_SoulseekSearchView> createState() => _SoulseekSearchViewState();
}

class _SoulseekSearchViewState extends State<_SoulseekSearchView> {
  final _searchCtrl = TextEditingController();
  List<SoulseekHit> _hits = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  String? _downloadingKey;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _hits = [];
      _searched = true;
    });
    try {
      final hits = await Get.find<SlskdService>().search(q);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _mapError(e);
      });
    }
  }

  String _mapError(Object e) {
    final msg = e.toString();
    if (msg.contains('slskdAuthFailed')) return 'slskdAuthFailed'.tr;
    if (msg.contains('slskdNotLoggedIn')) return 'slskdNotLoggedIn'.tr;
    if (msg.contains('slskdBusy')) return 'slskdBusy'.tr;
    if (msg.contains('slskdNotConfigured')) return 'slskdNotConfigured'.tr;
    return 'slskdSearchFailed'.tr;
  }

  Future<void> _download(SoulseekHit hit) async {
    final key = '${hit.username}|${hit.filename}';
    setState(() => _downloadingKey = key);
    try {
      await Get.find<SlskdService>().enqueueDownload(hit);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'slskdDownloadQueued'.tr, size: SanckBarSize.MEDIUM),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'slskdDownloadFailed'.tr, size: SanckBarSize.MEDIUM),
      );
    } finally {
      if (mounted) setState(() => _downloadingKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Get.find<ThemeController>().accentColor.value;
    final svc = Get.find<SlskdService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(() {
          final host = svc.host.value;
          final user = svc.soulseekUser.value;
          final loggedIn = svc.soulseekLoggedIn.value;
          final status = loggedIn
              ? (user.isEmpty
                  ? 'slskdLoggedIn'.tr
                  : 'slskdLoggedInAs'.trParams({'user': user}))
              : 'slskdNotLoggedIn'.tr;
          return Row(
            children: [
              Expanded(
                child: Text(
                  '$host · $status',
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => svc.disconnect(),
                child: Text('disconnect'.tr),
              ),
            ],
          );
        }),
        const SizedBox(height: 8),
        TextField(
          controller: _searchCtrl,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _loading ? null : _search(),
          decoration: InputDecoration(
            hintText: 'soulseekSearchHint'.tr,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: _loading ? null : _search,
            ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Text('soulseekSearchNote'.tr, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        Expanded(child: _body(theme, accent)),
      ],
    );
  }

  Widget _body(ThemeData theme, Color accent) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text('soulseekSearching'.tr, style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }
    if (!_searched) {
      return Center(
        child: Text(
          'soulseekSearchPrompt'.tr,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    if (_hits.isEmpty) {
      return Center(
        child: Text(
          'soulseekNoResults'.tr,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _hits.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final hit = _hits[index];
        final key = '${hit.username}|${hit.filename}';
        final busy = _downloadingKey == key;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          title: Text(
            hit.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(hit.metaLabel, style: theme.textTheme.bodySmall),
          trailing: IconButton(
            tooltip: 'slskdQueueDownload'.tr,
            onPressed: busy ? null : () => _download(hit),
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.download_outlined, color: accent),
          ),
        );
      },
    );
  }
}
