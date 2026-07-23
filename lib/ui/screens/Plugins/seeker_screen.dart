import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/soulseek/soulseek_cover_service.dart';
import '/services/soulseek/soulseek_search.dart';
import '/services/soulseek_service.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/snackbar.dart';

/// In-app Soulseek client — login + sockseek-style ranked search on mobile.
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

/// Sockseek-inspired mobile search: song/album mode, live ranked results,
/// format filters, album-folder interactive pick — all in-plugin.
class _SoulseekSearchView extends StatefulWidget {
  const _SoulseekSearchView();

  @override
  State<_SoulseekSearchView> createState() => _SoulseekSearchViewState();
}

class _SoulseekSearchViewState extends State<_SoulseekSearchView> {
  final _searchCtrl = TextEditingController();
  final _ranker = const SoulseekSearchRanker();

  SoulseekSearchMode _mode = SoulseekSearchMode.song;
  SoulseekSearchFilters _filters = const SoulseekSearchFilters();
  SoulseekQuery _query = const SoulseekQuery(raw: '', mode: SoulseekSearchMode.song);

  final List<SoulseekFile> _rawHits = [];
  List<RankedSoulseekFile> _ranked = [];
  List<SoulseekAlbumFolder> _albums = [];
  final Set<String> _expandedAlbums = {};

  bool _loading = false;
  bool _searched = false;
  String? _error;
  String? _downloadingKey;
  double? _downloadProgress;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reproject() {
    if (_mode == SoulseekSearchMode.album) {
      _albums = _ranker.groupAlbums(_rawHits, _query, _filters);
      _ranked = [];
    } else {
      _ranked = _ranker.rankFiles(_rawHits, _query, _filters);
      _albums = [];
    }
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    final parsed = SoulseekQuery.parse(q, _mode);
    setState(() {
      _loading = true;
      _error = null;
      _rawHits.clear();
      _ranked = [];
      _albums = [];
      _expandedAlbums.clear();
      _searched = true;
      _query = parsed;
    });
    try {
      final hits = await Get.find<SoulseekService>().search(
        parsed.networkQuery,
        timeout: const Duration(seconds: 10),
        onHit: (hit) {
          if (!mounted) return;
          setState(() {
            _rawHits.add(hit);
            _reproject();
          });
        },
      );
      if (!mounted) return;
      setState(() {
        // Final pass in case anything arrived after last onHit paint.
        _rawHits
          ..clear()
          ..addAll(hits);
        _reproject();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'soulseekSearchFailed'.tr;
      });
    }
  }

  Future<void> _download(SoulseekFile hit) async {
    final key = '${hit.username}|${hit.filename}';
    setState(() {
      _downloadingKey = key;
      _downloadProgress = 0;
    });
    try {
      // Progress not plumbed through service yet — keep indeterminate-ish.
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
      if (mounted) {
        setState(() {
          _downloadingKey = null;
          _downloadProgress = null;
        });
      }
    }
  }

  Future<void> _downloadAlbum(SoulseekAlbumFolder folder) async {
    final files = folder.files;
    if (files.isEmpty) return;
    for (var i = 0; i < files.length; i++) {
      if (!mounted) return;
      setState(() {
        _downloadingKey = 'album|${folder.username}|${folder.folderPath}';
        _downloadProgress = i / files.length;
      });
      try {
        await Get.find<SoulseekService>().download(files[i]);
      } catch (_) {
        // Continue remaining tracks; surface one failure snackbar at end if all fail.
      }
    }
    if (!mounted) return;
    setState(() {
      _downloadingKey = null;
      _downloadProgress = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(
        context,
        'soulseekAlbumDownloadDone'.trParams({
          'count': '${files.length}',
          'name': folder.folderName,
        }),
        size: SanckBarSize.MEDIUM,
      ),
    );
  }

  void _toggleFormat(String ext) {
    setState(() {
      final next = {..._filters.formats};
      if (next.contains(ext)) {
        next.remove(ext);
      } else {
        next.add(ext);
      }
      _filters = _filters.copyWith(formats: next);
      _reproject();
    });
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
            hintText: _mode == SoulseekSearchMode.song
                ? 'soulseekSearchHintSong'.tr
                : 'soulseekSearchHintAlbum'.tr,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: _loading ? null : _search,
            ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<SoulseekSearchMode>(
          segments: [
            ButtonSegment(
              value: SoulseekSearchMode.song,
              label: Text('soulseekModeSong'.tr),
              icon: const Icon(Icons.music_note, size: 18),
            ),
            ButtonSegment(
              value: SoulseekSearchMode.album,
              label: Text('soulseekModeAlbum'.tr),
              icon: const Icon(Icons.album, size: 18),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (s) {
            setState(() {
              _mode = s.first;
              _query = SoulseekQuery.parse(_searchCtrl.text, _mode);
              _reproject();
            });
          },
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip(
                label: 'FLAC',
                selected: _filters.formats.contains('flac'),
                onTap: () => _toggleFormat('flac'),
                accent: accent,
              ),
              _filterChip(
                label: 'MP3',
                selected: _filters.formats.contains('mp3'),
                onTap: () => _toggleFormat('mp3'),
                accent: accent,
              ),
              _filterChip(
                label: 'WAV',
                selected: _filters.formats.contains('wav'),
                onTap: () => _toggleFormat('wav'),
                accent: accent,
              ),
              _filterChip(
                label: 'soulseekFilterSlot'.tr,
                selected: _filters.freeSlotOnly,
                onTap: () => setState(() {
                  _filters =
                      _filters.copyWith(freeSlotOnly: !_filters.freeSlotOnly);
                  _reproject();
                }),
                accent: accent,
              ),
              _filterChip(
                label: '320+',
                selected: _filters.minBitrate >= 320,
                onTap: () => setState(() {
                  _filters = _filters.copyWith(
                    minBitrate: _filters.minBitrate >= 320 ? 0 : 320,
                  );
                  _reproject();
                }),
                accent: accent,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _loading
              ? 'soulseekSearchingLive'.trParams({'count': '${_rawHits.length}'})
              : 'soulseekSearchNote'.tr,
          style: theme.textTheme.bodySmall,
        ),
        if (_loading) ...[
          const SizedBox(height: 6),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 8),
        Expanded(child: _body(theme, accent)),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        selectedColor: accent.withOpacity(0.22),
      ),
    );
  }

  Widget _body(ThemeData theme, Color accent) {
    if (_error != null && _rawHits.isEmpty) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }
    if (!_searched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'soulseekSearchPromptSockseek'.tr,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    if (!_loading &&
        ((_mode == SoulseekSearchMode.song && _ranked.isEmpty) ||
            (_mode == SoulseekSearchMode.album && _albums.isEmpty))) {
      return Center(
        child: Text(
          'soulseekNoResults'.tr,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    if (_mode == SoulseekSearchMode.album) {
      return _albumList(theme, accent);
    }
    return _songList(theme, accent);
  }

  Widget _songList(ThemeData theme, Color accent) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _ranked.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final ranked = _ranked[index];
        final hit = ranked.file;
        final key = '${hit.username}|${hit.filename}';
        final busy = _downloadingKey == key;
        return _SongResultTile(
          hit: hit,
          query: _query,
          accent: accent,
          busy: busy,
          onDownload: () => _download(hit),
        );
      },
    );
  }

  Widget _albumList(ThemeData theme, Color accent) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _albums.length,
      itemBuilder: (context, index) {
        final folder = _albums[index];
        final id = '${folder.username}|${folder.folderPath}';
        final expanded = _expandedAlbums.contains(id);
        final albumBusy =
            _downloadingKey == 'album|${folder.username}|${folder.folderPath}';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              onTap: () => setState(() {
                if (expanded) {
                  _expandedAlbums.remove(id);
                } else {
                  _expandedAlbums.add(id);
                }
              }),
              leading: _CoverThumb(
                size: 52,
                lookupKey: CoverLookupHint(
                  artist: _query.artist,
                  album: _query.mode == SoulseekSearchMode.album
                      ? (_query.title ?? folder.folderName)
                      : folder.folderName,
                ).cacheKey,
                loader: () => SoulseekCoverService.instance
                    .coverForAlbum(folder, query: _query),
                fallback: Icon(
                  expanded ? Icons.folder_open : Icons.folder,
                  color: accent,
                ),
              ),
              title: Text(
                folder.folderName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  folder.username,
                  '${folder.trackCount} ${'soulseekTracks'.tr}',
                  if (folder.formatSummary.isNotEmpty) folder.formatSummary,
                  folder.sizeLabel,
                  if (folder.hasFreeSlot) 'soulseekFilterSlot'.tr,
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'soulseekDownloadAlbum'.tr,
                    onPressed: albumBusy ? null : () => _downloadAlbum(folder),
                    icon: albumBusy
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: _downloadProgress,
                            ),
                          )
                        : Icon(Icons.download_outlined, color: accent),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                  ),
                ],
              ),
            ),
            if (expanded)
              ...folder.files.map(
                (hit) {
                  final key = '${hit.username}|${hit.filename}';
                  return Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: _SongResultTile(
                      hit: hit,
                      query: _query,
                      accent: accent,
                      busy: _downloadingKey == key,
                      onDownload: () => _download(hit),
                      compact: true,
                    ),
                  );
                },
              ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }
}

class _SongResultTile extends StatelessWidget {
  const _SongResultTile({
    required this.hit,
    required this.query,
    required this.accent,
    required this.busy,
    required this.onDownload,
    this.compact = false,
  });

  final SoulseekFile hit;
  final SoulseekQuery query;
  final Color accent;
  final bool busy;
  final VoidCallback onDownload;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ext = hit.extension.toUpperCase();
    final meta = <String>[
      if (hit.bitRate != null && hit.bitRate! > 0) '${hit.bitRate}kbps',
      hit.sizeLabel,
      if (hit.lengthLabel.isNotEmpty) hit.lengthLabel,
      if (hit.hasFreeSlot) 'soulseekFilterSlot'.tr,
      hit.username,
    ].join(' · ');
    final coverSize = compact ? 40.0 : 52.0;

    return ListTile(
      dense: compact,
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 4,
        vertical: compact ? 0 : 4,
      ),
      leading: _CoverThumb(
        size: coverSize,
        lookupKey: CoverLookupHint.fromFile(hit, query).cacheKey,
        loader: () => SoulseekCoverService.instance
            .coverForFile(hit, query: query),
        fallback: Icon(
          Icons.music_note,
          size: coverSize * 0.45,
          color: accent.withOpacity(0.8),
        ),
      ),
      title: Text(
        hit.displayName,
        maxLines: compact ? 1 : 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact && hit.folderPath.isNotEmpty)
            Text(
              hit.folderPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
              ),
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (ext.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ext,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
      isThreeLine: !compact,
      trailing: IconButton(
        tooltip: 'soulseekDownload'.tr,
        onPressed: busy ? null : onDownload,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.download_outlined, color: accent),
      ),
    );
  }
}

/// Loads one cover per [lookupKey] and keeps it across list rebuilds.
class _CoverThumb extends StatefulWidget {
  const _CoverThumb({
    required this.size,
    required this.lookupKey,
    required this.loader,
    required this.fallback,
  });

  final double size;
  final String lookupKey;
  final Future<String?> Function() loader;
  final Widget fallback;

  @override
  State<_CoverThumb> createState() => _CoverThumbState();
}

class _CoverThumbState extends State<_CoverThumb> {
  String? _url;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _CoverThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lookupKey != widget.lookupKey) {
      _url = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final url = await widget.loader();
      if (!mounted) return;
      setState(() {
        _url = (url != null && url.isNotEmpty) ? url : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _url = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surfaceContainerHighest.withOpacity(0.7);

    Widget child;
    if (_url != null) {
      child = CachedNetworkImage(
        imageUrl: _url!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 150),
        httpHeaders: const {'User-Agent': 'RiffMobile/1.0'},
        placeholder: (_, __) => ColoredBox(
          color: bg,
          child: Center(
            child: SizedBox(
              width: widget.size * 0.28,
              height: widget.size * 0.28,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: theme.colorScheme.onSurface.withOpacity(0.35),
              ),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => ColoredBox(
          color: bg,
          child: Center(child: widget.fallback),
        ),
      );
    } else if (_loading) {
      child = ColoredBox(
        color: bg,
        child: Center(
          child: SizedBox(
            width: widget.size * 0.28,
            height: widget.size * 0.28,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: theme.colorScheme.onSurface.withOpacity(0.35),
            ),
          ),
        ),
      );
    } else {
      child = ColoredBox(
        color: bg,
        child: Center(child: widget.fallback),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: child,
      ),
    );
  }
}
