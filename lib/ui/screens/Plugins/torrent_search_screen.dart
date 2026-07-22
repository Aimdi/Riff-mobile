import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/torrents_digger_service.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/snackbar.dart';

/// General torrent search UI inspired by Torrents Digger.
///
/// User types any query; results come from the public Torrents.csv index
/// (same source Torrents Digger uses). Magnet links open in an external
/// torrent client — Riff does not download torrent payloads.
class TorrentSearchScreen extends StatefulWidget {
  const TorrentSearchScreen({super.key});

  @override
  State<TorrentSearchScreen> createState() => _TorrentSearchScreenState();
}

class _TorrentSearchScreenState extends State<TorrentSearchScreen> {
  final _searchCtrl = TextEditingController();
  final _service = TorrentsDiggerService();

  List<TorrentHit> _results = [];
  int? _next;
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search({bool loadMore = false}) async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      if (!loadMore) {
        _results = [];
        _next = null;
        _searched = true;
      }
    });
    try {
      final res = await _service.search(q, after: loadMore ? _next : null);
      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _results = [..._results, ...res.torrents];
        } else {
          _results = res.torrents;
        }
        _next = res.next;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'torrentSearchFailed'.tr;
      });
    }
  }

  Future<void> _openMagnet(TorrentHit hit) async {
    final uri = Uri.parse(hit.magnet);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'torrentOpenFailed'.tr, size: SanckBarSize.MEDIUM),
      );
    }
  }

  Future<void> _copyMagnet(TorrentHit hit) async {
    await Clipboard.setData(ClipboardData(text: hit.magnet));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(context, 'magnetCopied'.tr, size: SanckBarSize.SMALL),
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
            Text('torrentsDigger'.tr, style: theme.textTheme.titleLarge),
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
            const SizedBox(height: 8),
            Text(
              'torrentSearchDisclaimer'.tr,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
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
      return Center(
        child: Text(_error!, textAlign: TextAlign.center),
      );
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

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _results.length + (_next != null ? 1 : 0),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          title: Text(hit.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${hit.sizeLabel} · ${hit.dateLabel} · '
            '↑${hit.seeders} ↓${hit.leechers}',
            style: theme.textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'copyMagnet'.tr,
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () => _copyMagnet(hit),
              ),
              IconButton(
                tooltip: 'openMagnet'.tr,
                icon: Icon(Icons.download_outlined, color: accent),
                onPressed: () => _openMagnet(hit),
              ),
            ],
          ),
        );
      },
    );
  }
}
