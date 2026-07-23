import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/torrent_search_service.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/snackbar.dart';

/// qBittorrent-style torrent search: pick sources, search, open/copy/send.
///
/// Public: Torrents.csv. Optional private: MyAnonamouse (mam_id cookie).
/// Optional: send results to a qBittorrent WebUI.
class TorrentSearchScreen extends StatefulWidget {
  const TorrentSearchScreen({super.key});

  @override
  State<TorrentSearchScreen> createState() => _TorrentSearchScreenState();
}

class _TorrentSearchScreenState extends State<TorrentSearchScreen> {
  final _searchCtrl = TextEditingController();
  final _facade = TorrentSearchFacade();

  late Set<TorrentSourceId> _sources;
  List<TorrentHit> _results = [];
  int? _csvNext;
  bool _loading = false;
  bool _searched = false;
  String? _error;
  String? _partialError;

  @override
  void initState() {
    super.initState();
    _sources = TorrentSearchFacade.enabledSources();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleSource(TorrentSourceId id) async {
    if (id == TorrentSourceId.myAnonamouse &&
        !MamTorrentService.isConfigured) {
      await _showMamSheet();
      if (!MamTorrentService.isConfigured) return;
    }
    setState(() {
      if (_sources.contains(id)) {
        if (_sources.length == 1) return; // keep at least one
        _sources = {..._sources}..remove(id);
      } else {
        _sources = {..._sources, id};
      }
    });
    await TorrentSearchFacade.setEnabledSources(_sources);
  }

  Future<void> _search({bool loadMore = false}) async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _partialError = null;
      if (!loadMore) {
        _results = [];
        _csvNext = null;
        _searched = true;
      }
    });
    try {
      final res = await _facade.search(
        q,
        sources: loadMore
            ? {TorrentSourceId.torrentsCsv} // pagination only for CSV
            : _sources,
        csvAfter: loadMore ? _csvNext : null,
      );
      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _results = [..._results, ...res.torrents];
        } else {
          _results = res.torrents;
        }
        _csvNext = res.csvNext;
        _partialError = res.error;
        _loading = false;
        if (_results.isEmpty && res.error != null) {
          _error = 'torrentSearchFailed'.tr;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'torrentSearchFailed'.tr;
      });
    }
  }

  Future<void> _openHit(TorrentHit hit) async {
    final url = hit.openUrl;
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'torrentOpenFailed'.tr, size: SanckBarSize.MEDIUM),
      );
      return;
    }
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'torrentOpenFailed'.tr, size: SanckBarSize.MEDIUM),
      );
    }
  }

  Future<void> _copyHit(TorrentHit hit) async {
    final text = hit.openUrl;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(
        context,
        hit.hasMagnet ? 'magnetCopied'.tr : 'downloadLinkCopied'.tr,
        size: SanckBarSize.SMALL,
      ),
    );
  }

  Future<void> _sendToQbit(TorrentHit hit) async {
    if (!QBittorrentService.isConfigured) {
      await _showQbitSheet();
      if (!QBittorrentService.isConfigured) return;
    }
    final url = hit.openUrl;
    if (url.isEmpty) return;
    try {
      await QBittorrentService().addUrl(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'qbitAdded'.tr, size: SanckBarSize.MEDIUM),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'qbitAddFailed'.tr, size: SanckBarSize.MEDIUM),
      );
    }
  }

  Future<void> _showMamSheet() async {
    final ctrl = TextEditingController(text: MamTorrentService.mamId ?? '');
    await showModalBottomSheet<void>(
      context: context,
      // Nested navigator sits under the SlidingUpPanel mini-player; use the
      // root overlay so this sheet is actually tappable.
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor ??
          Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        var obscure = true;
        var busy = false;
        return StatefulBuilder(builder: (ctx, setLocal) {
          final bottomPad = _sheetBottomPadding(ctx);
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: bottomPad,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text('mamConfigure'.tr,
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('mamConfigureDes'.tr,
                      style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    obscureText: obscure,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    style: Theme.of(ctx).textTheme.bodyLarge,
                    decoration: _cookieFieldDecoration(
                      ctx,
                      label: 'mamId'.tr,
                      obscure: obscure,
                      onToggleObscure: () =>
                          setLocal(() => obscure = !obscure),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (MamTorrentService.isConfigured)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  await MamTorrentService.clearMamId();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  setState(() {
                                    _sources = {..._sources}
                                      ..remove(TorrentSourceId.myAnonamouse);
                                  });
                                  await TorrentSearchFacade.setEnabledSources(
                                      _sources);
                                },
                          child: Text('disconnect'.tr),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () async {
                                setLocal(() => busy = true);
                                try {
                                  await MamTorrentService.saveMamId(ctrl.text);
                                  await MamTorrentService().verify();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  setState(() {
                                    _sources = {
                                      ..._sources,
                                      TorrentSourceId.myAnonamouse
                                    };
                                  });
                                  await TorrentSearchFacade.setEnabledSources(
                                      _sources);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      snackbar(context, 'mamConnected'.tr,
                                          size: SanckBarSize.MEDIUM),
                                    );
                                  }
                                } catch (_) {
                                  setLocal(() => busy = false);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      snackbar(ctx, 'mamConnectFailed'.tr,
                                          size: SanckBarSize.MEDIUM),
                                    );
                                  }
                                }
                              },
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text('save'.tr),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
    ctrl.dispose();
  }

  Future<void> _showQbitSheet() async {
    final url = TextEditingController(text: QBittorrentService.baseUrl ?? '');
    final user =
        TextEditingController(text: QBittorrentService.username);
    final pass =
        TextEditingController(text: QBittorrentService.password);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor ??
          Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        var obscure = true;
        var busy = false;
        return StatefulBuilder(builder: (ctx, setLocal) {
          final bottomPad = _sheetBottomPadding(ctx);
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: bottomPad,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text('qbitConfigure'.tr,
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('qbitConfigureDes'.tr,
                      style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  TextField(
                    controller: url,
                    keyboardType: TextInputType.url,
                    autofocus: true,
                    decoration: _cookieFieldDecoration(
                      ctx,
                      label: 'qbitUrl'.tr,
                      hint: 'http://192.168.1.10:8080',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: user,
                    decoration: _cookieFieldDecoration(
                      ctx,
                      label: 'username'.tr,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pass,
                    obscureText: obscure,
                    decoration: _cookieFieldDecoration(
                      ctx,
                      label: 'password'.tr,
                      obscure: obscure,
                      onToggleObscure: () =>
                          setLocal(() => obscure = !obscure),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (QBittorrentService.isConfigured)
                        TextButton(
                          onPressed: () async {
                            await QBittorrentService.clear();
                            if (ctx.mounted) Navigator.pop(ctx);
                            setState(() {});
                          },
                          child: Text('disconnect'.tr),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () async {
                                setLocal(() => busy = true);
                                try {
                                  if (url.text.trim().isEmpty ||
                                      pass.text.isEmpty) {
                                    throw StateError('missing');
                                  }
                                  await QBittorrentService.save(
                                    url: url.text,
                                    username: user.text,
                                    password: pass.text,
                                  );
                                  await QBittorrentService().login();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  setState(() {});
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      snackbar(context, 'qbitSaved'.tr,
                                          size: SanckBarSize.MEDIUM),
                                    );
                                  }
                                } catch (_) {
                                  setLocal(() => busy = false);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      snackbar(ctx, 'qbitSaveFailed'.tr,
                                          size: SanckBarSize.MEDIUM),
                                    );
                                  }
                                }
                              },
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text('save'.tr),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
    url.dispose();
    user.dispose();
    pass.dispose();
  }

  /// Clear of the mini-player + keyboard so fields stay tappable.
  double _sheetBottomPadding(BuildContext ctx) {
    final keyboard = MediaQuery.viewInsetsOf(ctx).bottom;
    final safe = MediaQuery.paddingOf(ctx).bottom;
    // Sheet uses the root overlay (above mini-player); only need a cushion.
    return keyboard + safe + 16;
  }

  InputDecoration _cookieFieldDecoration(
    BuildContext ctx, {
    required String label,
    String? hint,
    bool? obscure,
    VoidCallback? onToggleObscure,
  }) {
    final theme = Theme.of(ctx);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: theme.dividerColor),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: theme.colorScheme.surface.withOpacity(0.9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.6),
      ),
      suffixIcon: onToggleObscure == null
          ? null
          : IconButton(
              icon: Icon(obscure == true
                  ? Icons.visibility
                  : Icons.visibility_off),
              onPressed: onToggleObscure,
            ),
    );
  }

  String _sourceLabel(TorrentSourceId id) {
    switch (id) {
      case TorrentSourceId.torrentsCsv:
        return 'CSV';
      case TorrentSourceId.myAnonamouse:
        return 'MAM';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Get.find<ThemeController>().accentColor.value;

    return Scaffold(
      backgroundColor: theme.canvasColor,
      body: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 70),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('torrentSearch'.tr,
                      style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: 'mamConfigure'.tr,
                  onPressed: _showMamSheet,
                  icon: Icon(
                    Icons.vpn_key_outlined,
                    color: MamTorrentService.isConfigured ? accent : null,
                  ),
                ),
                IconButton(
                  tooltip: 'qbitConfigure'.tr,
                  onPressed: _showQbitSheet,
                  icon: Icon(
                    Icons.cloud_download_outlined,
                    color: QBittorrentService.isConfigured ? accent : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('torrentSearchDes'.tr, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'torrentSearchHint'.tr,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _loading ? null : () => _search(),
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            // qBittorrent-style source picker
            Text('torrentSources'.tr,
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilterChip(
                  label: Text('torrentSourceTorrentsCsv'.tr),
                  selected: _sources.contains(TorrentSourceId.torrentsCsv),
                  onSelected: (_) =>
                      _toggleSource(TorrentSourceId.torrentsCsv),
                ),
                FilterChip(
                  label: Text(
                    MamTorrentService.isConfigured
                        ? 'torrentSourceMam'.tr
                        : 'torrentSourceMamAdd'.tr,
                  ),
                  selected:
                      _sources.contains(TorrentSourceId.myAnonamouse),
                  onSelected: (_) =>
                      _toggleSource(TorrentSourceId.myAnonamouse),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'torrentSearchDisclaimer'.tr,
              style: theme.textTheme.bodySmall,
            ),
            if (_partialError != null) ...[
              const SizedBox(height: 6),
              Text(
                '${'torrentPartialError'.tr}: $_partialError',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(child: _body(theme, accent)),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme, Color accent) {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _results.isEmpty) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }
    if (!_searched) {
      return Center(
        child: Text(
          'torrentSearchEmptyPrompt'.tr,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          'noTorrentResults'.tr,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final canLoadMore = _csvNext != null &&
        _sources.contains(TorrentSourceId.torrentsCsv);

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _results.length + (canLoadMore ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= _results.length) {
          return TextButton(
            onPressed: _loading ? null : () => _search(loadMore: true),
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('loadMore'.tr),
          );
        }
        final hit = _results[index];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          title: Text(hit.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${_sourceLabel(hit.source)} · ${hit.sizeLabel} · ${hit.dateLabel} · '
            '↑${hit.seeders} ↓${hit.leechers}',
            style: theme.textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: hit.hasMagnet ? 'copyMagnet'.tr : 'copyLink'.tr,
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () => _copyHit(hit),
              ),
              IconButton(
                tooltip: 'sendToQbit'.tr,
                icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                onPressed: () => _sendToQbit(hit),
              ),
              IconButton(
                tooltip: 'openMagnet'.tr,
                icon: Icon(Icons.download_outlined, color: accent),
                onPressed: () => _openHit(hit),
              ),
            ],
          ),
        );
      },
    );
  }
}
