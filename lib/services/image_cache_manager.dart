import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Shared disk cache for cover art. The package default (`DefaultCacheManager`)
/// keeps only ~200 objects, so in a library with hundreds of thumbnails art
/// is constantly evicted and re-downloaded on scroll-back — one of the causes
/// of the app "always loading". This raises the cap and stale window so
/// recently-seen art stays on disk.
class RiffImageCache {
  RiffImageCache._();

  static const key = 'riffImageCache';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 1000,
    ),
  );
}
