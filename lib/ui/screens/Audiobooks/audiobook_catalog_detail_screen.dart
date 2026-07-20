import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/audiobook_catalog_service.dart';

/// Details for a commercial audiobook. Browse-only: it can't play in Riff
/// (Audible/DRM), so the action opens Audible to listen or buy.
class AudiobookCatalogDetailScreen extends StatelessWidget {
  const AudiobookCatalogDetailScreen({super.key, required this.book});
  final AudiobookItem book;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(book.title, maxLines: 1)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: book.cover,
                width: 190,
                height: 190,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.menu_book, size: 120),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(book.title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          if (book.author.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(book.author,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge),
            ),
          if (book.genre.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(book.genre,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(book.audibleUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.headphones),
            label: Text('listenOnAudible'.tr),
          ),
          const SizedBox(height: 8),
          Text('audiobookBrowseOnly'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
          if (book.description.isNotEmpty) ...[
            const Divider(height: 32),
            Text(book.description,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
