import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/torrent_extra_sources.dart';
import '/services/torrent_search_service.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/snackbar.dart';

/// qBittorrent-style torrent search: pick sources, search, open/copy/send.
///
/// Public: Torrents.csv, 1337x (Music), AudioBook Bay, RuTracker (music forums).
/// Private (API key / cookie): MyAnonamouse, Redacted, Orpheus.
/// Optional: send results to a qBittorrent WebUI.
class TorrentSearchScreen extends StatefulWidget {
  const TorrentSearchScreen({super.key});

  @override
  State<TorrentSearchScreen> createState() => _TorrentSearchScreenState();
}

class _TorrentSearchScreenState extends State<TorrentSearchScreen> {
  final _searchCtrl = TextEditingController();
  final _facade = TorrentSearchFacade();
  final _redacted = GazelleTorrentService.redacted();
  final _orpheus = GazelleTorrentService.orpheus();

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

  bool _sourceNeedsConfig(TorrentSourceId id) {
    switch (id) {
      case TorrentSourceId.myAnonamouse:
        return !MamTorrentService.isConfigured;
      case TorrentSourceId.redacted:
        return !_redacted.isConfigured;
      case TorrentSourceId.orpheus:
        return !_orpheus.isConfigured;
      case TorrentSourceId.ruTracker:
        // Cookie optional for browsing; prompt when enabling for better results.
        return false;
      default:
        return false;
    }
  }

  Future<bool> _ensureConfigured(TorrentSourceId id) async {
    switch (id) {
      case TorrentSourceId.myAnonamouse:
        if (MamTorrentService.isConfigured) return true;
        await _showMamSheet();
        return MamTorrentService.isConfigured;
      case TorrentSourceId.redacted:
        if (_redacted.isConfigured) return true;
        await _showGazelleSheet(_redacted);
        return _redacted.isConfigured;
      case TorrentSourceId.orpheus:
        if (_orpheus.isConfigured) return true;
        await _showGazelleSheet(_orpheus);
        return _orpheus.isConfigured;
      case TorrentSourceId.ruTracker:
        // Optional cookie — enable either way; offer sheet once if missing.
        if (!RuTrackerTorrentService.isConfigured) {
          await _showRuTrackerSheet();
        }
        return true;
      default:
        return true;
    }
  }

  Future<void> _toggleSource(TorrentSourceId id) async {
    if (!_sources.contains(id) && _sourceNeedsConfig(id)) {
      final ok = await _ensureConfigured(id);
      if (!ok) return;
    } else if (!_sources.contains(id) &&
        (id == TorrentSourceId.ruTracker ||
            id == TorrentSourceId.redacted ||
            id == TorrentSourceId.orpheus ||
            id == TorrentSourceId.myAnonamouse)) {
      await _ensureConfigured(id);
      if (id == TorrentSourceId.myAnonamouse &&
          !MamTorrentService.isConfigured) {
        return;
      }
      if (id == TorrentSourceId.redacted && !_redacted.isConfigured) return;
      if (id == TorrentSourceId.orpheus && !_orpheus.isConfigured) return;
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
    try {
      final resolved = await _facade.resolve(hit);
      final url = resolved.openUrl;
      if (url.isEmpty) {
        if (!mounted) return;
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'torrentOpenFailed'.tr, size: SanckBarSize.MEDIUM),
      );
    }
  }

  Future<void> _copyHit(TorrentHit hit) async {
    try {
      final resolved = await _facade.resolve(hit);
      final text = resolved.openUrl;
      if (text.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(
          context,
          resolved.hasMagnet ? 'magnetCopied'.tr : 'downloadLinkCopied'.tr,
          size: SanckBarSize.SMALL,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'torrentOpenFailed'.tr, size: SanckBarSize.MEDIUM),
      );
    }
  }

  Future<void> _sendToQbit(TorrentHit hit) async {
    if (!QBittorrentService.isConfigured) {
      await _showQbitSheet();
      if (!QBittorrentService.isConfigured) return;
    }
    try {
      await _facade.sendToQbit(hit);
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

  double _sheetBottomPadding(BuildContext ctx) {
    return MediaQuery.viewInsetsOf(ctx).bottom + 24;
  }

  InputDecoration _cookieFieldDecoration(
    BuildContext ctx, {
    required String label,
    required bool obscure,
    required VoidCallback onToggleObscure,
  }) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
      suffixIcon: IconButton(
        icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
        onPressed: onToggleObscure,
      ),
    );
  }

  Future<void> _showMamSheet() async {
    final ctrl = TextEditingController(text: MamTorrentService.mamId ?? '');
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

  Future<void> _showGazelleSheet(GazelleTorrentService service) async {
    final ctrl = TextEditingController(text: service.apiKey ?? '');
    final isRed = service.source == TorrentSourceId.redacted;
    final titleKey = isRed ? 'redactedConfigure' : 'orpheusConfigure';
    final desKey = isRed ? 'redactedConfigureDes' : 'orpheusConfigureDes';
    final connectedKey = isRed ? 'redactedConnected' : 'orpheusConnected';
    final failedKey =
        isRed ? 'redactedConnectFailed' : 'orpheusConnectFailed';
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
                  Text(titleKey.tr,
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(desKey.tr, style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    obscureText: obscure,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    style: Theme.of(ctx).textTheme.bodyLarge,
                    decoration: _cookieFieldDecoration(
                      ctx,
                      label: 'torrentApiKey'.tr,
                      obscure: obscure,
                      onToggleObscure: () =>
                          setLocal(() => obscure = !obscure),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (service.isConfigured)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  await service.clearApiKey();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  setState(() {
                                    _sources = {..._sources}
                                      ..remove(service.source);
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
                                  await service.saveApiKey(ctrl.text);
                                  await service.verify();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  setState(() {
                                    _sources = {..._sources, service.source};
                                  });
                                  await TorrentSearchFacade.setEnabledSources(
                                      _sources);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      snackbar(context, connectedKey.tr,
                                          size: SanckBarSize.MEDIUM),
                                    );
                                  }
                                } catch (_) {
                                  setLocal(() => busy = false);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      snackbar(ctx, failedKey.tr,
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

  Future<void> _showRuTrackerSheet() async {
    final ctrl =
        TextEditingController(text: RuTrackerTorrentService.cookie ?? '');
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
                  Text('rutrackerConfigure'.tr,
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('rutrackerConfigureDes'.tr,
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
                      label: 'rutrackerCookie'.tr,
                      obscure: obscure,
                      onToggleObscure: () =>
                          setLocal(() => obscure = !obscure),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: busy ? null : () => Navigator.pop(ctx),
                        child: Text('torrentSkipCookie'.tr),
                      ),
                      if (RuTrackerTorrentService.isConfigured)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  await RuTrackerTorrentService.clearCookie();
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
                                if (ctrl.text.trim().isEmpty) {
                                  Navigator.pop(ctx);
                                  return;
                                }
                                setLocal(() => busy = true);
                                try {
                                  await RuTrackerTorrentService.saveCookie(
                                      ctrl.text);
                                  await RuTrackerTorrentService().verify();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  setState(() {});
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      snackbar(context, 'rutrackerConnected'.tr,
                                          size: SanckBarSize.MEDIUM),
                                    );
                                  }
                                } catch (_) {
                                  setLocal(() => busy = false);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      snackbar(ctx, 'rutrackerConnectFailed'.tr,
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
    final user = TextEditingController(text: QBittorrentService.username);
    final pass = TextEditingController(text: QBittorrentService.password);
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
                    decoration: InputDecoration(
                      labelText: 'qbitUrl'.tr,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      hintText: 'http://192.168.1.10:8080',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: user,
                    decoration: InputDecoration(
                      labelText: 'username'.tr,
                      border: const OutlineInputBorder(),
                      isDense: true,
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
                          onPressed: busy
                              ? null
                              : () async {
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

  bool get _anyPrivateConfigured =>
      MamTorrentService.isConfigured ||
      _redacted.isConfigured ||
      _orpheus.isConfigured ||
      RuTrackerTorrentService.isConfigured;

  String _sourceLabel(TorrentSourceId id) {
    switch (id) {
      case TorrentSourceId.torrentsCsv:
        return 'CSV';
      case TorrentSourceId.myAnonamouse:
        return 'MAM';
      case TorrentSourceId.redacted:
        return 'RED';
      case TorrentSourceId.orpheus:
        return 'OPS';
      case TorrentSourceId.x1337:
        return '1337x';
      case TorrentSourceId.ruTracker:
        return 'RT';
      case TorrentSourceId.audioBookBay:
        return 'ABB';
    }
  }

  Widget _sourceChip({
    required TorrentSourceId id,
    required String label,
  }) {
    return FilterChip(
      label: Text(label),
      selected: _sources.contains(id),
      onSelected: (_) => _toggleSource(id),
    );
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
                PopupMenuButton<String>(
                  tooltip: 'torrentConfigureSources'.tr,
                  icon: Icon(
                    Icons.vpn_key_outlined,
                    color: _anyPrivateConfigured ? accent : null,
                  ),
                  onSelected: (v) {
                    if (v == 'mam') {
                      _showMamSheet();
                    } else if (v == 'red') {
                      _showGazelleSheet(_redacted);
                    } else if (v == 'ops') {
                      _showGazelleSheet(_orpheus);
                    } else if (v == 'rt') {
                      _showRuTrackerSheet();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'mam', child: Text('mamConfigure'.tr)),
                    PopupMenuItem(
                        value: 'red', child: Text('redactedConfigure'.tr)),
                    PopupMenuItem(
                        value: 'ops', child: Text('orpheusConfigure'.tr)),
                    PopupMenuItem(
                        value: 'rt', child: Text('rutrackerConfigure'.tr)),
                  ],
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
            Text('torrentSources'.tr, style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _sourceChip(
                  id: TorrentSourceId.torrentsCsv,
                  label: 'torrentSourceTorrentsCsv'.tr,
                ),
                _sourceChip(
                  id: TorrentSourceId.myAnonamouse,
                  label: MamTorrentService.isConfigured
                      ? 'torrentSourceMam'.tr
                      : 'torrentSourceMamAdd'.tr,
                ),
                _sourceChip(
                  id: TorrentSourceId.redacted,
                  label: _redacted.isConfigured
                      ? 'torrentSourceRedacted'.tr
                      : 'torrentSourceRedactedAdd'.tr,
                ),
                _sourceChip(
                  id: TorrentSourceId.orpheus,
                  label: _orpheus.isConfigured
                      ? 'torrentSourceOrpheus'.tr
                      : 'torrentSourceOrpheusAdd'.tr,
                ),
                _sourceChip(
                  id: TorrentSourceId.x1337,
                  label: 'torrentSource1337x'.tr,
                ),
                _sourceChip(
                  id: TorrentSourceId.ruTracker,
                  label: 'torrentSourceRuTracker'.tr,
                ),
                _sourceChip(
                  id: TorrentSourceId.audioBookBay,
                  label: 'torrentSourceAbb'.tr,
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
