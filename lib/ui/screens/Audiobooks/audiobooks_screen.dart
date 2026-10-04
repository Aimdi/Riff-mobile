import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '/services/audiobook_catalog_service.dart';
import '/services/audiobook_progress_service.dart';
import '/services/audiobookshelf_service.dart';
import '/services/free_audiobook_service.dart';
import '/services/plugin_service.dart';
import '/ui/navigator.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/utils/theme_controller.dart';
import '../Home/home_layout.dart';
import '../Library/library.dart' show libraryGridMetrics;
import '../Podcasts/podcast_empty_state.dart';
import '../Podcasts/podcast_layout.dart';
import 'audiobook_detail_screen.dart';
import 'audiobook_library_controller.dart';
import 'audiobook_play.dart';
import 'audiobook_upload_sheet.dart';
import 'audiobook_widgets.dart';
import 'free_audiobook_list_screen.dart';
import '/ui/widgets/riff_header_bar.dart';

Future<void> _playOrOpenAudiobook(String bookId) async {
  if (shouldPlayAudiobookOnTap()) {
    final ok = await playAudiobook(bookId: bookId);
    if (ok) return;
  }
  Get.to(
    () => AudiobookDetailScreen(bookId: bookId),
    transition: Transition.rightToLeft,
  );
}

/// Resume a free book from its "Continue listening" card (here and on
/// Home); opens the book when the chapter list can't be loaded. False only
/// when the record names no book.
Future<bool> resumeFreeAudiobook(Map<String, dynamic> record) async {
  final id = '${record['bookId'] ?? ''}';
  if (id.isEmpty) return false;
  final detail = await FreeAudiobookService.detail(id);
  if (detail != null && await playFreeAudiobook(detail)) return true;
  openFreeAudiobook(FreeAudiobook(
    id: id,
    title: '${record['album'] ?? ''}',
    author: '${record['artist'] ?? ''}',
  ));
  return true;
}

/// Audiobooks: free LibriVox classics and store bestsellers (Discover), an
/// Audiobookshelf server (Library) and bookmarks (Saved).
class AudiobooksScreen extends StatefulWidget {
  const AudiobooksScreen({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  State<AudiobooksScreen> createState() => _AudiobooksScreenState();
}

class _AudiobooksScreenState extends State<AudiobooksScreen> {
  // 0 = Discover, 1 = Library (Audiobookshelf server), 2 = Saved.
  // Prefer Library when already connected to a server.
  late int _mode;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    final abs = Get.find<AudiobookshelfService>();
    _mode = abs.isConnected.value ? 1 : 0;
  }

  void _select(int mode) {
    if (mode == 3) {
      // Full search screen (same as Plugins → Open).
      Get.toNamed(
        ScreenNavigationSetup.torrentSearchScreen,
        id: ScreenNavigationSetup.id,
      );
      return;
    }
    setState(() {
      _mode = mode;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final abs = Get.find<AudiobookshelfService>();
    final topPadding = context.isLandscape ? 50.0 : 90.0;

    return Padding(
      padding: widget.isBottomNavActive
          ? const EdgeInsets.only(top: 10)
          : EdgeInsets.only(top: topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isBottomNavActive) _header(context),
          _tabs(context),
          const SizedBox(height: 4),
          Expanded(
            child: RiffScrollUnder(
                child: _mode == 0
                    ? _DiscoverView(
                        searching: _searching,
                        onCloseSearch: () => setState(() => _searching = false),
                      )
                    : _mode == 1
                        ? Obx(() => abs.isConnected.value
                            ? const _AbsLibraryView()
                            : const _AbsLoginForm())
                        : _SavedView(onDiscover: () => _select(0))),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return RiffHeaderBar(
        hairline: false,
        child: Padding(
          padding: const EdgeInsets.only(
              left: HomeLayout.gutter,
              right: RiffSpacing.xs,
              bottom: RiffSpacing.sm),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'audiobooks'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (!(_mode == 0 && _searching))
                  IconButton(
                    tooltip: 'searchAudiobooks'.tr,
                    icon: const Icon(Icons.search_rounded),
                    onPressed: () => setState(() {
                      _mode = 0;
                      _searching = true;
                    }),
                  ),
              ],
            ),
          ),
        ));
  }

  /// Discover · Library · Saved (· Torrents when the plugin is installed).
  Widget _tabs(BuildContext context) {
    final plugins = Get.find<PluginService>();
    return Obx(() {
      final tabs = <(int, String)>[
        (0, 'discover'.tr),
        (1, 'library'.tr),
        (2, 'saved'.tr),
        if (plugins.isInstalled(PluginIds.torrentSearch)) (3, 'torrents'.tr),
      ];
      return SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
          itemCount: tabs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final (mode, label) = tabs[i];
            final active = _mode == mode;
            final accent = Theme.of(context).colorScheme.secondary;
            return Material(
              color: active ? accent : homeTileColor(context),
              shape: StadiumBorder(
                  side: active ? BorderSide.none : homeTileBorder(context)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _select(mode),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: active
                                ? RiffSurfaces.voidBlack
                                : Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.color,
                          ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────── Discover ──

class _DiscoverView extends StatefulWidget {
  const _DiscoverView({required this.searching, required this.onCloseSearch});
  final bool searching;
  final VoidCallback onCloseSearch;

  @override
  State<_DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<_DiscoverView> {
  List<FreeAudiobook> _free = const [];
  List<AudiobookItem> _store = const [];
  bool _loading = true;

  final _search = TextEditingController();
  String _query = '';
  bool _searchLoading = false;
  List<FreeAudiobook> _freeResults = const [];
  List<AudiobookItem> _storeResults = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await Future.wait([
      FreeAudiobookService.popular(),
      AudiobookCatalogService.browse(),
    ]);
    if (!mounted) return;
    setState(() {
      _free = res[0] as List<FreeAudiobook>;
      _store = res[1] as List<AudiobookItem>;
      _loading = false;
    });
  }

  Future<void> _runSearch(String q) async {
    final text = q.trim();
    setState(() {
      _query = text;
      _searchLoading = text.isNotEmpty;
    });
    if (text.isEmpty) return;
    final res = await Future.wait([
      FreeAudiobookService.search(text),
      AudiobookCatalogService.search(text),
    ]);
    if (!mounted || _query != text) return;
    setState(() {
      _freeResults = res[0] as List<FreeAudiobook>;
      _storeResults = res[1] as List<AudiobookItem>;
      _searchLoading = false;
    });
  }

  void _openGenre(FreeAudiobookGenre g) => Get.to(
        () => FreeAudiobookListScreen(
          title: g.labelKey.tr,
          load: () => FreeAudiobookService.byGenre(g.subject),
        ),
        transition: Transition.rightToLeft,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.searching) {
      return Column(
        children: [
          AudiobookSearchField(
            controller: _search,
            hint: 'audiobookSearchHint'.tr,
            autofocus: true,
            onSubmitted: _runSearch,
            onClear: () {
              _search.clear();
              setState(() => _query = '');
              widget.onCloseSearch();
            },
          ),
          Expanded(child: _searchBody(context)),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          const SliverToBoxAdapter(child: _ContinueFreeShelf()),
          if (_loading)
            const SliverToBoxAdapter(child: _ShelfPlaceholder())
          else if (_free.isEmpty && _store.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 60),
                child: PodcastEmptyState(
                  icon: Icons.wifi_off_rounded,
                  message: 'freeLibraryOffline'.tr,
                  actionLabel: 'retry'.tr,
                  actionIcon: Icons.refresh_rounded,
                  onAction: _load,
                ),
              ),
            ),
          if (_free.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: HomeSectionHeader(
                'freeClassics'.tr,
                badge: 'freeBadge'.tr,
                trailing: _SeeAll(
                  onTap: () => Get.to(
                    () => FreeAudiobookListScreen(
                      title: 'freeClassics'.tr,
                      load: () => FreeAudiobookService.popular(rows: 60),
                    ),
                    transition: Transition.rightToLeft,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: HomeShelf(
                cardSize: HomeLayout.shelfCard,
                itemCount: _free.length,
                itemBuilder: (context, i) => FreeAudiobookCard(
                    book: _free[i], size: HomeLayout.shelfCard),
              ),
            ),
          ],
          if (!_loading) ...[
            SliverToBoxAdapter(child: HomeSectionHeader('browseByGenre'.tr)),
            _genreGrid(context),
          ],
          if (_store.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: HomeSectionHeader(
                'storeBestsellers'.tr,
                trailing: Padding(
                  padding: const EdgeInsets.only(right: HomeLayout.gutter),
                  child: Text('storeBookNote'.tr,
                      style: homeCardSubtitleStyle(context)),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: HomeShelf(
                cardSize: HomeLayout.shelfCard,
                itemCount: _store.length,
                itemBuilder: (context, i) => StoreAudiobookCard(
                    book: _store[i], size: HomeLayout.shelfCard),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 200)),
        ],
      ),
    );
  }

  Widget _genreGrid(BuildContext context) {
    const genres = FreeAudiobookService.genres;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 4 : 2,
          mainAxisSpacing: HomeLayout.tileGap,
          crossAxisSpacing: HomeLayout.tileGap,
          mainAxisExtent:
              MediaQuery.textScalerOf(context).scale(HomeLayout.tileHeight),
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => AudiobookGenreTile(
            label: genres[i].labelKey.tr,
            index: i,
            onTap: () => _openGenre(genres[i]),
          ),
          childCount: genres.length,
        ),
      ),
    );
  }

  Widget _searchBody(BuildContext context) {
    if (_query.isEmpty) {
      // Nothing typed yet: offer genres as a starting point.
      return CustomScrollView(slivers: [
        SliverToBoxAdapter(
            child: HomeSectionHeader('browseByGenre'.tr, top: 8)),
        _genreGrid(context),
        const SliverToBoxAdapter(child: SizedBox(height: 200)),
      ]);
    }
    if (_searchLoading) {
      return const Align(
        alignment: Alignment(0, -0.6),
        child: SizedBox.square(
            dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    if (_freeResults.isEmpty && _storeResults.isEmpty) {
      return PodcastEmptyState(
          icon: Icons.search_off_rounded, message: 'noResults'.tr);
    }
    final muted = homeMutedColor(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 200),
      children: [
        if (_freeResults.isNotEmpty) ...[
          AudiobookGroupLabel('freeToListen'.tr, badge: 'freeBadge'.tr),
          for (final b in _freeResults)
            AudiobookRow(
              key: ValueKey('free_${b.id}'),
              cover: b.cover,
              title: b.title,
              subtitle: b.author,
              onTap: () => openFreeAudiobook(b),
              trailing: Icon(Icons.chevron_right_rounded, color: muted),
            ),
        ],
        if (_storeResults.isNotEmpty) ...[
          AudiobookGroupLabel('inStores'.tr),
          for (final b in _storeResults)
            AudiobookRow(
              key: ValueKey('store_${b.id}'),
              cover: b.cover,
              title: b.title,
              subtitle: [b.author, 'storeBookNote'.tr]
                  .where((s) => s.isNotEmpty)
                  .join(' · '),
              onTap: () => openStoreAudiobook(b),
              trailing: Icon(Icons.chevron_right_rounded, color: muted),
            ),
        ],
      ],
    );
  }
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: homeMutedColor(context),
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      // Style on the Text, not the button: a button textStyle replaces the
      // theme font instead of merging with it.
      child: Text('seeAll'.tr,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: homeMutedColor(context))),
    );
  }
}

/// Grey card outlines while the first shelf loads.
class _ShelfPlaceholder extends StatelessWidget {
  const _ShelfPlaceholder();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurface.withOpacity(0.06);
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration:
              BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
        );
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter, top: HomeLayout.sectionTop),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(150, 20),
          const SizedBox(height: HomeLayout.headerBottom + 4),
          SizedBox(
            height: HomeLayout.shelfCard + 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: HomeLayout.cardGap),
              itemBuilder: (_, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(HomeLayout.shelfCard, HomeLayout.shelfCard),
                  const SizedBox(height: 8),
                  bar(96, 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Free books with a saved position, newest first. Hidden when empty.
class _ContinueFreeShelf extends StatelessWidget {
  const _ContinueFreeShelf();

  @override
  Widget build(BuildContext context) {
    if (!Hive.isBoxOpen(AudiobookProgressService.boxName)) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder(
      valueListenable: Hive.box(AudiobookProgressService.boxName).listenable(),
      builder: (context, _, __) {
        final records = AudiobookProgressService.freeBooksInProgress();
        if (records.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeSectionHeader('continueListening'.tr, top: 12),
            SizedBox(
              height: PodcastContinueCard.heightFor(context),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
                itemCount: records.length.clamp(0, 10),
                separatorBuilder: (_, __) =>
                    const SizedBox(width: HomeLayout.cardGap),
                itemBuilder: (context, i) => FreeAudiobookContinueCard(
                  key: ValueKey(records[i]['bookId']),
                  record: records[i],
                  onTap: () => resumeFreeAudiobook(records[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────── Saved ──

class _SavedView extends StatelessWidget {
  const _SavedView({required this.onDiscover});
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final lib = Get.find<AudiobookLibraryController>();
    return Obx(() {
      final free = lib.savedFree.toList();
      final store = lib.saved.toList();
      if (free.isEmpty && store.isEmpty) {
        return PodcastEmptyState(
          icon: Icons.bookmark_border_rounded,
          message: 'noSavedAudiobooks'.tr,
          actionLabel: 'discover'.tr,
          onAction: onDiscover,
        );
      }
      return LayoutBuilder(builder: (context, box) {
        final grid = libraryGridMetrics(box.maxWidth);
        SliverGridDelegate delegate() =>
            SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: grid.columns,
              crossAxisSpacing: HomeLayout.cardGap,
              mainAxisSpacing: 14,
              mainAxisExtent: grid.cover + HomeShelf.textBlockHeight(context),
            );
        return CustomScrollView(
          slivers: [
            if (free.isNotEmpty) ...[
              SliverToBoxAdapter(
                  child: HomeSectionHeader('freeToListen'.tr, top: 12)),
              SliverPadding(
                padding:
                    const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
                sliver: SliverGrid(
                  gridDelegate: delegate(),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) =>
                        FreeAudiobookCard(book: free[i], size: grid.cover),
                    childCount: free.length,
                  ),
                ),
              ),
            ],
            if (store.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: HomeSectionHeader(
                  'inStores'.tr,
                  top: free.isEmpty ? 12 : HomeLayout.sectionTop,
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: HomeLayout.gutter),
                    child: Text('storeBookNote'.tr,
                        style: homeCardSubtitleStyle(context)),
                  ),
                ),
              ),
              SliverPadding(
                padding:
                    const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
                sliver: SliverGrid(
                  gridDelegate: delegate(),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) =>
                        StoreAudiobookCard(book: store[i], size: grid.cover),
                    childCount: store.length,
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 200)),
          ],
        );
      });
    });
  }
}

// ──────────────────────────────────────────────── Library (Audiobookshelf) ──

InputDecoration _fieldDecoration(BuildContext context, String label,
        {String? hint, Widget? suffix}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: homeTileColor(context),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );

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
    final accent = theme.colorScheme.secondary;
    return ListView(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter,
          top: RiffSpacing.lg,
          right: HomeLayout.gutter,
          bottom: RiffSpacing.listEnd),
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.dns_rounded, color: accent, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('absConnectTitle'.tr,
                  style: homeSectionTitleStyle(context)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text('absConnectDes'.tr,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: homeMutedColor(context))),
        const SizedBox(height: 20),
        TextField(
          controller: _host,
          decoration: _fieldDecoration(context, 'absServerUrl'.tr,
              hint: 'https://abs.example.com'),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _user,
          decoration: _fieldDecoration(context, 'username'.tr),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _pass,
          obscureText: _obscure,
          decoration: _fieldDecoration(
            context,
            'password'.tr,
            suffix: IconButton(
              icon: Icon(_obscure
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 18),
        Obx(() => SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: RiffSurfaces.voidBlack,
                  shape: const StadiumBorder(),
                ),
                onPressed: abs.isLoading.value ? null : _submit,
                child: abs.isLoading.value
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('absConnect'.tr,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: RiffSurfaces.voidBlack)),
              ),
            )),
        Obx(() {
          final msg = abs.statusMessage.value;
          if (msg.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(msg, style: TextStyle(color: theme.colorScheme.error)),
          );
        }),
        const SizedBox(height: 18),
        Text('absDemoHint'.tr,
            style: homeCardSubtitleStyle(context).copyWith(height: 1.4)),
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
  void initState() {
    super.initState();
    final abs = Get.find<AudiobookshelfService>();
    if (abs.isConnected.value) {
      abs.fetchInProgress();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openDetail(String id) => Get.to(
        () => AudiobookDetailScreen(bookId: id),
        transition: Transition.rightToLeft,
      );

  @override
  Widget build(BuildContext context) {
    final abs = Get.find<AudiobookshelfService>();
    return Column(
      children: [
        _serverStrip(context, abs),
        AudiobookSearchField(
          controller: _search,
          hint: 'search'.tr,
          onSubmitted: (q) => abs.searchBooks(q),
          onClear: () {
            _search.clear();
            abs.fetchBooks();
          },
        ),
        Expanded(
          child: Obx(() {
            if (abs.isLoading.value && abs.books.isEmpty) {
              return const Center(
                  child: SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5)));
            }
            // A failed load is NOT an empty library. Saying "no books" when the
            // token expired or the server is unreachable sends the user
            // looking for a problem in Audiobookshelf that is not there.
            final loadErr = abs.loadError.value;
            if (loadErr != null && abs.books.isEmpty) {
              return PodcastEmptyState(
                icon: Icons.cloud_off_rounded,
                message: loadErr,
                actionLabel: 'retry'.tr,
                actionIcon: Icons.refresh_rounded,
                onAction: () => abs.fetchBooks(),
              );
            }
            if (abs.books.isEmpty) {
              return PodcastEmptyState(
                  icon: Icons.auto_stories_outlined, message: 'absNoBooks'.tr);
            }
            final continueBooks = abs.inProgressBooks.take(12).toList();
            final token = abs.token ?? '';
            return RefreshIndicator(
              onRefresh: () async {
                await abs.fetchBooks();
                await abs.fetchInProgress();
              },
              child: LayoutBuilder(builder: (context, box) {
                final grid = libraryGridMetrics(box.maxWidth);
                return CustomScrollView(
                  slivers: [
                    if (continueBooks.isNotEmpty) ...[
                      SliverToBoxAdapter(
                          child: HomeSectionHeader('continueListening'.tr,
                              top: 8)),
                      SliverToBoxAdapter(
                        child: HomeShelf(
                          cardSize: HomeLayout.shelfCard,
                          itemCount: continueBooks.length,
                          itemBuilder: (context, i) {
                            final b = continueBooks[i];
                            return HomeShelfCard(
                              key: ValueKey('c_${b.id}'),
                              size: HomeLayout.shelfCard,
                              art: AudiobookCover(
                                url: b.coverUrl(abs.host.value, token),
                                size: HomeLayout.shelfCard,
                                progress: b.progress,
                                radius: 0,
                              ),
                              title: b.title,
                              subtitle: b.author ?? '',
                              onTap: () => _playOrOpenAudiobook(b.id),
                              onLongPress: () => _openDetail(b.id),
                            );
                          },
                        ),
                      ),
                    ],
                    SliverToBoxAdapter(
                      child: HomeSectionHeader(
                        abs.selectedLibrary?.name ?? 'library'.tr,
                        top: continueBooks.isEmpty ? 8 : HomeLayout.sectionTop,
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.only(
                          left: HomeLayout.gutter,
                          right: HomeLayout.gutter,
                          bottom: RiffSpacing.listEnd),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: grid.columns,
                          crossAxisSpacing: HomeLayout.cardGap,
                          mainAxisSpacing: 14,
                          mainAxisExtent:
                              grid.cover + HomeShelf.textBlockHeight(context),
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final b = abs.books[i];
                            return HomeShelfCard(
                              key: ValueKey(b.id),
                              size: grid.cover,
                              art: AudiobookCover(
                                url: b.coverUrl(abs.host.value, token),
                                size: grid.cover,
                                progress: b.progress,
                                radius: 0,
                              ),
                              title: b.title,
                              subtitle: b.author ?? '',
                              onTap: () => _playOrOpenAudiobook(b.id),
                              onLongPress: () => _openDetail(b.id),
                            );
                          },
                          childCount: abs.books.length,
                        ),
                      ),
                    ),
                  ],
                );
              }),
            );
          }),
        ),
      ],
    );
  }

  /// Server, user and library picker on one row; upload and disconnect in
  /// the overflow menu.
  Widget _serverStrip(BuildContext context, AudiobookshelfService abs) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Obx(() {
      final libs = abs.libraries.toList();
      final selected = abs.selectedLibrary;
      return Padding(
        padding: const EdgeInsets.only(
            left: HomeLayout.gutter,
            top: RiffSpacing.sm,
            bottom: RiffSpacing.xs),
        child: Row(
          children: [
            Icon(Icons.dns_rounded, size: 20, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Uri.tryParse(abs.host.value)?.host.isNotEmpty == true
                        ? Uri.parse(abs.host.value).host
                        : abs.host.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: homeCardTitleStyle(context),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    abs.username.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: homeCardSubtitleStyle(context),
                  ),
                ],
              ),
            ),
            if (libs.length > 1)
              PopupMenuButton<String>(
                tooltip: 'absLibrary'.tr,
                onSelected: abs.selectLibrary,
                itemBuilder: (_) => [
                  for (final l in libs)
                    CheckedPopupMenuItem(
                      value: l.id,
                      checked: l.id == abs.selectedLibraryId.value,
                      child: Text(l.name),
                    ),
                ],
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: homeTileColor(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(
                          selected?.name ?? 'absLibrary'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      const Icon(Icons.expand_more_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) {
                if (v == 'upload') AudiobookUploadSheet.show(context);
                if (v == 'disconnect') abs.logout();
              },
              itemBuilder: (_) => [
                if (selected != null)
                  PopupMenuItem(
                    value: 'upload',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cloud_upload_outlined),
                      title: Text('uploadAudiobook'.tr),
                    ),
                  ),
                PopupMenuItem(
                  value: 'disconnect',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.logout_rounded),
                    title: Text('disconnect'.tr),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
