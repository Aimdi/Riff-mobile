import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/screens/Home/home_layout.dart';
import '/ui/screens/Home/home_screen_controller.dart';
import 'library.dart';

/// Phone Library tab (Echo Music's Library): one page with a title row and
/// filter chips for Songs, Playlists, Albums and Artists. The chips map to
/// the tab indices the side rail used, so everything else stays the same.
class LibraryShell extends StatelessWidget {
  const LibraryShell({super.key, required this.tabIndex});

  /// 1 Songs, 4 Playlists, 5 Albums, 6 Artists.
  final int tabIndex;

  static const segments = [
    (index: 1, labelKey: 'songs'),
    (index: 4, labelKey: 'playlists'),
    (index: 5, labelKey: 'albums'),
    (index: 6, labelKey: 'artists'),
  ];

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeScreenController>();
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final accent = theme.colorScheme.secondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(HomeLayout.gutter, top + 12, 2, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'library'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.1,
                    color: theme.textTheme.titleMedium?.color,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'settings'.tr,
                icon: const Icon(Icons.settings_outlined, size: 24),
                onPressed: () => home.onSideBarTabSelected(7),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
            itemCount: segments.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final seg = segments[i];
              final selected = seg.index == tabIndex;
              return Material(
                color: selected ? accent : homeTileColor(context),
                shape: StadiumBorder(
                    side: selected ? BorderSide.none : homeTileBorder(context)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    if (!selected) home.onSideBarTabSelected(seg.index);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: Text(
                        seg.labelKey.tr,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.black
                              : theme.textTheme.titleMedium?.color,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(child: _page()),
      ],
    );
  }

  Widget _page() {
    switch (tabIndex) {
      case 4:
        return const PlaylistNAlbumLibraryWidget(
            isAlbumContent: false, isBottomNavActive: true);
      case 5:
        return const PlaylistNAlbumLibraryWidget(isBottomNavActive: true);
      case 6:
        return const LibraryArtistWidget(isBottomNavActive: true);
      default:
        return const SongsLibraryWidget(isBottomNavActive: true);
    }
  }
}
