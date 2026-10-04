import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/free_audiobook_service.dart';
import '/ui/theme/riff_spacing.dart';
import '../Home/home_layout.dart';
import '../Library/library.dart' show libraryGridMetrics;
import 'audiobook_widgets.dart';

/// A full grid of free books: one genre, or "See all" for a shelf.
class FreeAudiobookListScreen extends StatefulWidget {
  const FreeAudiobookListScreen(
      {super.key, required this.title, required this.load});
  final String title;
  final Future<List<FreeAudiobook>> Function() load;

  @override
  State<FreeAudiobookListScreen> createState() =>
      _FreeAudiobookListScreenState();
}

class _FreeAudiobookListScreenState extends State<FreeAudiobookListScreen> {
  List<FreeAudiobook>? _books;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _books = null);
    final res = await widget.load();
    if (mounted) setState(() => _books = res);
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: books == null
          ? const Center(
              child: SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5)))
          : books.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('freeLibraryOffline'.tr,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: homeMutedColor(context))),
                      TextButton.icon(
                        onPressed: _fetch,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text('retry'.tr),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(builder: (context, box) {
                  final grid = libraryGridMetrics(box.maxWidth);
                  return GridView.builder(
                    padding: const EdgeInsets.only(
                        left: HomeLayout.gutter,
                        top: RiffSpacing.sm,
                        right: HomeLayout.gutter,
                        bottom: RiffSpacing.listEnd),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: grid.columns,
                      crossAxisSpacing: HomeLayout.cardGap,
                      mainAxisSpacing: 14,
                      mainAxisExtent:
                          grid.cover + HomeShelf.textBlockHeight(context),
                    ),
                    itemCount: books.length,
                    itemBuilder: (context, i) =>
                        FreeAudiobookCard(book: books[i], size: grid.cover),
                  );
                }),
    );
  }
}
