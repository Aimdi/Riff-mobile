import '../services/utils.dart';

const _qualityKeys = ['lowQualityAudio', 'highQualityAudio'];

/// True when a [SongsUrlCache] value has no remaining usable stream URL.
///
/// Current writes store an [HMStreamingData] map:
/// `{playable, statusMSG, lowQualityAudio: {url, ...}, highQualityAudio: {url, ...}}`.
/// Older builds used a quality list (`[low, high]`). Either shape is kept when
/// at least one quality URL is still fresh so housekeeping does not wipe good
/// cache. Unknown shapes are left alone.
bool songsUrlCacheEntryExpired(dynamic entry) {
  if (entry == null) return true;

  if (entry is Map) {
    final urls = _qualityUrlsFromMap(entry);
    if (urls.isEmpty) return true;
    return urls.every((url) => isExpired(url: url));
  }

  if (entry is List) {
    final urls = <String>[];
    for (final item in entry) {
      if (item is Map) {
        final url = item['url']?.toString();
        if (url != null && url.isNotEmpty) urls.add(url);
      } else if (item is String && item.isNotEmpty) {
        urls.add(item);
      }
    }
    if (urls.isEmpty) return true;
    return urls.every((url) => isExpired(url: url));
  }

  if (entry is String) {
    return entry.isEmpty || isExpired(url: entry);
  }

  // Don't delete entries we cannot interpret.
  return false;
}

/// Playback must use the selected quality URL, not "any quality is fresh".
bool songsUrlCacheQualityUsable(dynamic entry, {required int qualityIndex}) {
  if (entry is! Map) return false;
  final key = qualityIndex <= 0 ? 'lowQualityAudio' : 'highQualityAudio';
  final quality = entry[key];
  if (quality is! Map) return false;
  final url = quality['url']?.toString();
  if (url == null || url.isEmpty) return false;
  return !isExpired(url: url);
}

List<String> _qualityUrlsFromMap(Map entry) {
  final urls = <String>[];
  for (final key in _qualityKeys) {
    final quality = entry[key];
    if (quality is Map) {
      final url = quality['url']?.toString();
      if (url != null && url.isNotEmpty) urls.add(url);
    }
  }
  return urls;
}
