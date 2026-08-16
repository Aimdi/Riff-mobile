import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/soul_sync_service.dart';
import '/ui/navigator.dart';
import '/ui/screens/Search/search_play_top.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/snackbar.dart';

/// Connect to a self-hosted SoulSync server and search / request downloads.
/// Based on https://www.ssync.net/ and https://github.com/Nezreka/SoulSync
class SoulSyncScreen extends StatelessWidget {
  const SoulSyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = Get.find<SoulSyncService>();
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.canvasColor,
      body: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 70),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new),
                  onPressed: () => Get.back(id: ScreenNavigationSetup.id),
                ),
                Text('soulSync'.tr, style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 4),
            Text('soulSyncDes'.tr, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(() => svc.isConnected.value
                  ? const _SoulSyncConnectedView()
                  : const _SoulSyncLoginForm()),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoulSyncLoginForm extends StatefulWidget {
  const _SoulSyncLoginForm();

  @override
  State<_SoulSyncLoginForm> createState() => _SoulSyncLoginFormState();
}

class _SoulSyncLoginFormState extends State<_SoulSyncLoginForm> {
  final _url = TextEditingController();
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
      await Get.find<SoulSyncService>().connect(
        serverUrl: _url.text,
        apiKey: _key.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'soulSyncConnected'.tr, size: SanckBarSize.MEDIUM),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'soulSyncConnectFailed'.tr, size: SanckBarSize.MEDIUM),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final svc = Get.find<SoulSyncService>();
    return ListView(
      padding: const EdgeInsets.only(bottom: 120, top: 4),
      children: [
        Text('soulSyncConnectTitle'.tr, style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('soulSyncConnectDes'.tr, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _url,
          decoration: InputDecoration(
            labelText: 'soulSyncServerUrl'.tr,
            hintText: 'https://soulsync.example.com:8008',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _key,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'soulSyncApiKey'.tr,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _submit(),
        ),
        const SizedBox(height: 8),
        Obx(() {
          final msg = svc.statusMessage.value;
          if (msg.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(msg, style: theme.textTheme.bodySmall),
          );
        }),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link),
          label: Text('soulSyncConnect'.tr),
        ),
        const SizedBox(height: 16),
        Text('soulSyncHint'.tr, style: theme.textTheme.bodySmall),
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse('https://www.ssync.net/'),
            mode: LaunchMode.externalApplication,
          ),
          child: Text('soulSyncWebsite'.tr),
        ),
      ],
    );
  }
}

class _SoulSyncConnectedView extends StatefulWidget {
  const _SoulSyncConnectedView();

  @override
  State<_SoulSyncConnectedView> createState() => _SoulSyncConnectedViewState();
}

class _SoulSyncConnectedViewState extends State<_SoulSyncConnectedView> {
  final _searchCtrl = TextEditingController();
  List<SoulSyncTrack> _results = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

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
      _searched = true;
    });
    try {
      final hits = await Get.find<SoulSyncService>().searchTracks(q);
      if (!mounted) return;
      setState(() {
        _results = hits;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'soulSyncSearchFailed'.tr;
        _results = [];
      });
    }
  }

  Future<void> _playThenRequest(SoulSyncTrack track) async {
    final played = await playTopSongResult(track.requestQuery);
    if (played) return;
    await _request(track);
  }

  Future<void> _request(SoulSyncTrack track) async {
    try {
      await Get.find<SoulSyncService>().requestDownload(track.requestQuery);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'soulSyncRequestQueued'.tr, size: SanckBarSize.MEDIUM),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'soulSyncRequestFailed'.tr, size: SanckBarSize.MEDIUM),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final svc = Get.find<SoulSyncService>();
    final accent = Get.find<ThemeController>().accentColor.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                svc.host.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(svc.host.value),
                mode: LaunchMode.externalApplication,
              ),
              child: Text('soulSyncOpenWeb'.tr),
            ),
            TextButton(
              onPressed: () async {
                await svc.disconnect();
              },
              child: Text('disconnect'.tr),
            ),
          ],
        ),
        TextField(
          controller: _searchCtrl,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'soulSyncSearchHint'.tr,
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
        Text('soulSyncSearchNote'.tr, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, textAlign: TextAlign.center))
                  : !_searched
                      ? Center(
                          child: Text(
                            'soulSyncSearchPrompt'.tr,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        )
                      : _results.isEmpty
                          ? Center(child: Text('noResults'.tr))
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 120),
                              itemCount: _results.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final t = _results[i];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  onTap: () => _playThenRequest(t),
                                  leading: t.imageUrl != null &&
                                          t.imageUrl!.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          child: CachedNetworkImage(
                                            imageUrl: t.imageUrl!,
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) =>
                                                Icon(Icons.album,
                                                    color: accent),
                                          ),
                                        )
                                      : Icon(Icons.music_note, color: accent),
                                  title: Text(t.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    [
                                      if (t.artistLabel.isNotEmpty)
                                        t.artistLabel,
                                      if (t.album != null &&
                                          t.album!.isNotEmpty)
                                        t.album!,
                                      if (t.source != null) t.source!,
                                    ].join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'soulSyncRequestDownload'.tr,
                                    icon: Icon(Icons.download_outlined,
                                        color: accent),
                                    onPressed: () => _request(t),
                                  ),
                                );
                              },
                            ),
        ),
      ],
    );
  }
}
