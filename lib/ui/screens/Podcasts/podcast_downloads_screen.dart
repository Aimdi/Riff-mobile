import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/podcast_download_service.dart';
import 'podcast_empty_state.dart';

/// AntennaPod-style Downloads hub: list offline episodes and remove them.
class PodcastDownloadsScreen extends StatefulWidget {
  const PodcastDownloadsScreen({
    super.key,
    this.embedded = false,
    this.onDiscover,
  });

  final bool embedded;
  final VoidCallback? onDiscover;

  @override
  State<PodcastDownloadsScreen> createState() => _PodcastDownloadsScreenState();
}

class _PodcastDownloadsScreenState extends State<PodcastDownloadsScreen> {
  List<String> _ids = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _ids = PodcastDownloadService.downloadedIds());
  }

  @override
  Widget build(BuildContext context) {
    final body = _ids.isEmpty
        ? PodcastEmptyState(
            icon: Icons.download_outlined,
            message: 'noDownloads'.tr,
            actionLabel: widget.onDiscover != null ? 'discover'.tr : null,
            onAction: widget.onDiscover,
          )
        : ListView.separated(
            padding: const EdgeInsets.only(bottom: 200),
            itemCount: _ids.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, i) {
              final id = _ids[i];
              final path = PodcastDownloadService.localPath(id) ?? '';
              final name = path.split('/').last;
              return ListTile(
                leading: const Icon(Icons.offline_pin_outlined),
                title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(id, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'removeDownload'.tr,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await PodcastDownloadService.delete(id);
                    _reload();
                  },
                ),
              );
            },
          );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text('downloads'.tr)),
      body: body,
    );
  }
}
