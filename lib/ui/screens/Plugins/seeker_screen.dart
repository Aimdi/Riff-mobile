import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/soulseek_service.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/snackbar.dart';

/// In-app Soulseek client — login, search, and download like Seeker, without
/// connecting to a separate home server.
class SeekerScreen extends StatelessWidget {
  const SeekerScreen({super.key});

  static const seekerGithub = 'https://github.com/jackBonadies/SeekerAndroid';

  @override
  Widget build(BuildContext context) {
    final svc = Get.find<SoulseekService>();
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
                () => svc.isLoggedIn.value
                    ? const _SoulseekSearchView()
                    : const _SoulseekLoginForm(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoulseekLoginForm extends StatefulWidget {
  const _SoulseekLoginForm();

  @override
  State<_SoulseekLoginForm> createState() => _SoulseekLoginFormState();
}

class _SoulseekLoginFormState extends State<_SoulseekLoginForm> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _user.text = Get.find<SoulseekService>().username.value;
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    try {
      await Get.find<SoulseekService>().login(
        user: _user.text,
        pass: _pass.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'soulseekLoggedIn'.tr, size: SanckBarSize.MEDIUM),
      );
    } catch (_) {
      if (!mounted) return;
      final msg = Get.find<SoulseekService>().statusMessage.value;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(
          context,
          msg.isEmpty ? 'soulseekLoginFailed'.tr : msg,
          size: SanckBarSize.MEDIUM,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final svc = Get.find<SoulseekService>();
    return ListView(
      padding: const EdgeInsets.only(bottom: 120, top: 4),
      children: [
        Text('soulseekLoginTitle'.tr, style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('soulseekLoginDes'.tr, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _user,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'soulseekUsername'.tr,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pass,
          obscureText: _obscure,
          onSubmitted: (_) => svc.isBusy.value ? null : _submit(),
          decoration: InputDecoration(
            labelText: 'soulseekPassword'.tr,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Obx(
          () => FilledButton(
            onPressed: svc.isBusy.value ? null : _submit,
            child: svc.isBusy.value
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('soulseekLogin'.tr),
          ),
        ),
        const SizedBox(height: 16),
        Text('soulseekAccountHint'.tr, style: theme.textTheme.bodySmall),
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse('https://www.slsknet.org/news/node/1'),
            mode: LaunchMode.externalApplication,
          ),
          child: Text('soulseekCreateAccount'.tr),
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
  List<SoulseekFile> _hits = [];
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
      final hits = await Get.find<SoulseekService>().search(q);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'soulseekSearchFailed'.tr;
      });
    }
  }

  Future<void> _download(SoulseekFile hit) async {
    final key = '${hit.username}|${hit.filename}';
    setState(() => _downloadingKey = key);
    try {
      final file = await Get.find<SoulseekService>().download(hit);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(
          context,
          'soulseekDownloadSaved'.trParams({'path': file.path}),
          size: SanckBarSize.MEDIUM,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'soulseekDownloadFailed'.tr, size: SanckBarSize.MEDIUM),
      );
    } finally {
      if (mounted) setState(() => _downloadingKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Get.find<ThemeController>().accentColor.value;
    final svc = Get.find<SoulseekService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(
          () => Row(
            children: [
              Expanded(
                child: Text(
                  'soulseekLoggedInAs'.trParams({'user': svc.username.value}),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () => svc.logout(),
                child: Text('disconnect'.tr),
              ),
            ],
          ),
        ),
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
          title: Text(hit.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(hit.metaLabel, style: theme.textTheme.bodySmall),
          trailing: IconButton(
            tooltip: 'soulseekDownload'.tr,
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
