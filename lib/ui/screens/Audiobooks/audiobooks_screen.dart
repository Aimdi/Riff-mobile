import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/audiobook_catalog_service.dart';
import '/services/audiobookshelf_service.dart';
import 'audiobook_catalog_detail_screen.dart';
import 'audiobook_detail_screen.dart';
import 'audiobook_library_controller.dart';

/// Audiobooks: a free LibriVox "Discover" browser plus the Audiobookshelf
/// (Lissen-inspired) server view for those who self-host.
class AudiobooksScreen extends StatefulWidget {
  const AudiobooksScreen({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  State<AudiobooksScreen> createState() => _AudiobooksScreenState();
}

class _AudiobooksScreenState extends State<AudiobooksScreen> {
  // 0 = Discover, 1 = Library (Audiobookshelf server), 2 = Saved, 3 = Wish List
  int _mode = 0;

  @override
  Widget build(BuildContext context) {
    final abs = Get.find<AudiobookshelfService>();
    final topPadding = context.isLandscape ? 50.0 : 90.0;

    return Padding(
      padding: widget.isBottomNavActive
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(top: topPadding, left: 5, right: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isBottomNavActive)
            Text('audiobooks'.tr, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          // Audible-style bar: icon + label items with a hairline below.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.only(left: 2, right: 8),
              child: Row(
                children: [
                  _audibleTab(
                      icon: Icons.play_circle_outline,
                      label: 'discover'.tr,
                      mode: 0),
                  const SizedBox(width: 16),
                  _audibleTab(
                      icon: Icons.library_books_outlined,
                      label: 'library'.tr,
                      mode: 1),
                  const SizedBox(width: 16),
                  _audibleTab(
                      icon: Icons.bookmark_border,
                      label: 'saved'.tr,
                      mode: 2),
                  const SizedBox(width: 16),
                  _audibleTab(
                      icon: Icons.favorite_border,
                      label: 'wishlist'.tr,
                      mode: 3),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 8),
          Expanded(
            child: _mode == 0
                ? const _CatalogDiscover()
                : _mode == 1
                    ? Obx(() => abs.isConnected.value
                        ? const _AbsLibraryView()
                        : const _AbsLoginForm())
                    : _mode == 2
                        ? const _SavedView()
                        : const _WishlistView(),
          ),
        ],
      ),
    );
  }

  Widget _audibleTab(
      {required IconData icon, required String label, required int mode}) {
    final theme = Theme.of(context);
    final active = _mode == mode;
    final color = active
        ? theme.colorScheme.secondary
        : theme.textTheme.bodyMedium?.color?.withOpacity(0.75);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _mode = mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Popular commercial audiobook browser (Apple catalog → Audible). Browse-only.
class _CatalogDiscover extends StatefulWidget {
  const _CatalogDiscover();

  @override
  State<_CatalogDiscover> createState() => _CatalogDiscoverState();
}

class _CatalogDiscoverState extends State<_CatalogDiscover> {
  final _search = TextEditingController();
  List<AudiobookItem> _books = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(() => AudiobookCatalogService.browse());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(Future<List<AudiobookItem>> Function() fetch) async {
    setState(() => _loading = true);
    final res = await fetch();
    if (mounted) {
      setState(() {
        _books = res;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (q) => q.trim().isEmpty
                ? _load(() => AudiobookCatalogService.browse())
                : _load(() => AudiobookCatalogService.search(q)),
            decoration: InputDecoration(
              hintText: 'searchAudiobooks'.tr,
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _search.clear();
                  _load(() => AudiobookCatalogService.browse());
                },
              ),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _books.isEmpty
                  ? Center(child: Text('noResults'.tr))
                  : GridView.builder(
                      padding: const EdgeInsets.only(bottom: 200, right: 8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.72,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _books.length,
                      itemBuilder: (context, i) {
                        final book = _books[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Get.to(
                            () => AudiobookCatalogDetailScreen(book: book),
                            transition: Transition.rightToLeft,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: CachedNetworkImage(
                                    imageUrl: book.cover,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: theme.primaryColorLight,
                                      child: const Icon(Icons.menu_book,
                                          size: 48),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                book.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                              if (book.author.isNotEmpty)
                                Text(
                                  book.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

/// Locally-saved (bookmarked) catalog audiobooks.
class _SavedView extends StatelessWidget {
  const _SavedView();

  @override
  Widget build(BuildContext context) {
    final lib = Get.find<AudiobookLibraryController>();
    return Obx(() => _CatalogBookGrid(
          books: lib.saved.toList(),
          emptyIcon: Icons.bookmark_border,
          emptyText: 'noSavedAudiobooks'.tr,
        ));
  }
}

/// Audible-style wish list of catalog audiobooks.
class _WishlistView extends StatelessWidget {
  const _WishlistView();

  @override
  Widget build(BuildContext context) {
    final lib = Get.find<AudiobookLibraryController>();
    return Obx(() => _CatalogBookGrid(
          books: lib.wishlist.toList(),
          emptyIcon: Icons.favorite_border,
          emptyText: 'noWishlistAudiobooks'.tr,
        ));
  }
}

/// Shared 2-column cover grid for locally stored catalog book lists.
class _CatalogBookGrid extends StatelessWidget {
  const _CatalogBookGrid(
      {required this.books, required this.emptyIcon, required this.emptyText});
  final List<AudiobookItem> books;
  final IconData emptyIcon;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (books.isEmpty) {
      final dim = theme.textTheme.bodySmall?.color;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(emptyIcon, size: 52, color: dim?.withOpacity(0.4)),
              const SizedBox(height: 12),
              Text(
                emptyText,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: dim?.withOpacity(0.8)),
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
        padding: const EdgeInsets.only(bottom: 200, right: 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.72,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: books.length,
        itemBuilder: (context, i) {
          final book = books[i];
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Get.to(
              () => AudiobookCatalogDetailScreen(book: book),
              transition: Transition.rightToLeft,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: book.cover,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: theme.primaryColorLight,
                        child: const Icon(Icons.menu_book, size: 48),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall),
                if (book.author.isNotEmpty)
                  Text(book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall),
              ],
            ),
          );
        },
      );
  }
}

class _AbsLoginForm extends StatefulWidget {
  const _AbsLoginForm();

  @override
  State<_AbsLoginForm> createState() => _AbsLoginFormState();
}

class _AbsLoginFormState extends State<_AbsLoginForm> {
  final _host = TextEditingController(text: 'https://demo.lissenapp.org');
  final _user = TextEditingController(text: 'demo');
  final _pass = TextEditingController(text: 'demo');
  bool _obscure = true;

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final abs = Get.find<AudiobookshelfService>();
    try {
      await abs.login(
        serverUrl: _host.text.trim(),
        user: _user.text.trim(),
        password: _pass.text,
      );
    } catch (_) {
      // statusMessage already set
    }
  }

  @override
  Widget build(BuildContext context) {
    final abs = Get.find<AudiobookshelfService>();
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(right: 10, bottom: 200, top: 8),
      children: [
        Text('absConnectTitle'.tr, style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('absConnectDes'.tr, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _host,
          decoration: InputDecoration(
            labelText: 'absServerUrl'.tr,
            hintText: 'https://abs.example.com',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _user,
          decoration: InputDecoration(
            labelText: 'username'.tr,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _pass,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'password'.tr,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        Obx(() => ElevatedButton.icon(
              onPressed: abs.isLoading.value ? null : _submit,
              icon: abs.isLoading.value
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text('absConnect'.tr),
            )),
        Obx(() {
          final msg = abs.statusMessage.value;
          if (msg.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(msg, style: TextStyle(color: theme.colorScheme.error)),
          );
        }),
        const SizedBox(height: 20),
        Text(
          'absDemoHint'.tr,
          style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _AbsLibraryView extends StatefulWidget {
  const _AbsLibraryView();

  @override
  State<_AbsLibraryView> createState() => _AbsLibraryViewState();
}

class _AbsLibraryViewState extends State<_AbsLibraryView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final abs = Get.find<AudiobookshelfService>();
    final theme = Theme.of(context);

    return Column(
      children: [
        // Connection strip
        Obx(() => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.cloud_done, size: 22),
              title: Text(
                abs.host.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              subtitle: Text(
                '${abs.username.value} · ${abs.libraries.length} ${'libraries'.tr}',
                style: theme.textTheme.bodySmall,
              ),
              trailing: TextButton(
                onPressed: () => abs.logout(),
                child: Text('disconnect'.tr),
              ),
            )),
        // Library picker
        Obx(() {
          if (abs.libraries.isEmpty) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.centerLeft,
            child: DropdownButton<String>(
              value: abs.selectedLibraryId.value.isEmpty
                  ? null
                  : abs.selectedLibraryId.value,
              hint: Text('absLibrary'.tr),
              underline: const SizedBox.shrink(),
              items: abs.libraries
                  .map((l) => DropdownMenuItem(
                        value: l.id,
                        child: Text('${l.name} (${l.mediaType})'),
                      ))
                  .toList(),
              onChanged: (id) {
                if (id != null) abs.selectLibrary(id);
              },
            ),
          );
        }),
        // Search
        Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'search'.tr,
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _search.clear();
                  abs.fetchBooks();
                },
              ),
            ),
            onSubmitted: (q) => abs.searchBooks(q),
          ),
        ),
        Expanded(
          child: Obx(() {
            if (abs.isLoading.value && abs.books.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (abs.books.isEmpty) {
              return Center(child: Text('absNoBooks'.tr));
            }
            return RefreshIndicator(
              onRefresh: () => abs.fetchBooks(),
              child: GridView.builder(
                padding: const EdgeInsets.only(bottom: 200, right: 8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.72,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: abs.books.length,
                itemBuilder: (context, i) {
                  final book = abs.books[i];
                  final token = abs.token ?? '';
                  final cover = book.coverUrl(abs.host.value, token);
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Get.to(
                      () => AudiobookDetailScreen(bookId: book.id),
                      transition: Transition.rightToLeft,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: cover,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                color: theme.primaryColorLight,
                                child: const Icon(Icons.menu_book, size: 48),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (book.author != null)
                          Text(
                            book.author!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  );
                },
              ),
            );
          }),
        ),
      ],
    );
  }
}
