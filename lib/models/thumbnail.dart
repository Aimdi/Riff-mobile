import 'package:get/get.dart';

/// Resolves the highest-quality image URL we can get from YouTube Music,
/// YouTube, Google user-content, and Apple podcast artwork CDNs.
class Thumbnail {
  Thumbnail(this._url);
  final String _url;

  String get url => _url;

  /// Small list-row tiles.
  String get low => sizewith(150);

  /// Grid / medium list art.
  String get medium => sizewith(400);

  /// Large tiles, artist headers, etc.
  String get high => sizewith(720);

  /// Full-screen player, notification, and primary artwork.
  /// Always target a retina-friendly size on mobile (phone art is ~screen width).
  String get extraHigh =>
      GetPlatform.isDesktop ? sizewith(1600) : sizewith(1200);

  /// Rewrite known CDN URL patterns to [size]×[size] (or equivalent).
  String sizewith(int size) {
    final raw = _url.trim();
    if (raw.isEmpty) return raw;

    // Apple / iTunes podcast artwork:
    //   .../image/thumb/.../100x100bb.jpg  →  3000x3000bb.jpg
    //   artworkUrl100 / artworkUrl600 variants
    final apple = _upgradeAppleArtwork(raw, size);
    if (apple != null) return apple;

    // YouTube static thumbs: i.ytimg.com/vi/<id>/{default,mq,hq,sd,hq720,maxres}default
    final yt = _upgradeYtImg(raw, size);
    if (yt != null) return yt;

    // Google user-content / yt3.ggpht (YTM album art):
    //   ...=w60-h60-l90-rj  or  ...=s88-c-k-c0x00ffffff-no-rj
    if (raw.contains('googleusercontent.com') ||
        raw.contains('ggpht.com') ||
        raw.contains('-rj') ||
        raw.contains('=s') ||
        RegExp(r'=w\d+').hasMatch(raw)) {
      return _upgradeGoogleContent(raw, size);
    }

    return raw;
  }

  /// Pick the best URL from a YTM/YouTube `thumbnails` list (usually small→large),
  /// then upscale it to [target] quality.
  ///
  /// [target] is one of: `low`, `medium`, `high`, `extraHigh` (default extraHigh).
  static String bestUrl(
    dynamic thumbnails, {
    String target = 'extraHigh',
    String fallback = '',
  }) {
    final best = _pickLargest(thumbnails) ?? fallback;
    if (best.isEmpty) return fallback;
    final t = Thumbnail(best);
    switch (target) {
      case 'low':
        return t.low;
      case 'medium':
        return t.medium;
      case 'high':
        return t.high;
      default:
        return t.extraHigh;
    }
  }

  static String? _pickLargest(dynamic thumbnails) {
    if (thumbnails is! List || thumbnails.isEmpty) return null;

    String? bestUrl;
    int bestArea = -1;

    for (final t in thumbnails) {
      if (t is! Map) continue;
      final u = (t['url'] ?? t['urlString'] ?? '').toString();
      if (u.isEmpty) continue;
      final w = int.tryParse('${t['width'] ?? 0}') ?? 0;
      final h = int.tryParse('${t['height'] ?? 0}') ?? 0;
      final area = w * h;
      // Prefer explicit larger dimensions; if none have size, fall through to last.
      if (area > bestArea) {
        bestArea = area;
        bestUrl = u;
      }
    }

    // No width/height on any entry → YTM order is ascending; take last.
    if (bestArea <= 0) {
      for (var i = thumbnails.length - 1; i >= 0; i--) {
        final t = thumbnails[i];
        if (t is Map) {
          final u = (t['url'] ?? t['urlString'] ?? '').toString();
          if (u.isNotEmpty) return u;
        } else if (t is String && t.isNotEmpty) {
          return t;
        }
      }
      return null;
    }
    return bestUrl;
  }

  static String? _upgradeAppleArtwork(String raw, int size) {
    // Prefer at least 1400 for player-sized art; Apple serves up to ~3000.
    final side = size >= 600 ? (size >= 1200 ? 3000 : 1400) : size.clamp(100, 600);

    // Path form: .../100x100bb.jpg, .../600x600bb.webp, etc.
    final dimRe = RegExp(r'/\d+x\d+([a-z]*)(\.[a-zA-Z]+)?(?:\?.*)?$');
    if (raw.contains('mzstatic.com') && dimRe.hasMatch(raw)) {
      return raw.replaceFirstMapped(dimRe, (m) {
        final suffix = m.group(1) ?? 'bb';
        final ext = m.group(2) ?? '.jpg';
        return '/${side}x$side$suffix$ext';
      });
    }

    // Query / host forms sometimes embed size in the filename only — already handled.
    // artworkUrl100 style is already a full URL with dimensions in the path.
    return null;
  }

  static String? _upgradeYtImg(String raw, int size) {
    if (!(raw.contains('i.ytimg.com') || raw.contains('img.youtube.com'))) {
      return null;
    }
    // Prefer maxres for large targets; hq720 is a reliable fallback many videos have.
    if (size >= 600) {
      var out = raw
          .replaceFirst('maxresdefault', 'maxresdefault') // no-op keep
          .replaceFirst('hq720', 'maxresdefault')
          .replaceFirst('sddefault', 'maxresdefault')
          .replaceFirst('hqdefault', 'maxresdefault')
          .replaceFirst('mqdefault', 'maxresdefault')
          .replaceFirst('/default.jpg', '/maxresdefault.jpg')
          .replaceFirst('/default.webp', '/maxresdefault.webp');
      // Frame thumbs: hq1/hq2/hq3
      out = out.replaceFirst(RegExp(r'/hq\d\.'), '/maxresdefault.');
      return out;
    }
    return raw
        .replaceFirst('default.jpg', 'hqdefault.jpg')
        .replaceFirst('mqdefault', 'hqdefault');
  }

  static String _upgradeGoogleContent(String raw, int size) {
    // Strip existing size / crop tokens after the last '=' that starts a size spec.
    // Forms:
    //   BASE=w60-h60-l90-rj
    //   BASE=s88-c-k-c0x00ffffff-no-rj
    //   BASE=w544-h544-p-l90-rj  (playlist)
    final sizeEq = RegExp(r'=(?:w\d+-h\d+|s\d+)[^/]*$');
    if (sizeEq.hasMatch(raw)) {
      final base = raw.replaceFirst(sizeEq, '');
      // Square crop with high quality. l90 is YTM's usual quality flag.
      return '$base=w$size-h$size-l90-rj';
    }

    // Bare googleusercontent without size — append.
    if (raw.contains('googleusercontent.com') || raw.contains('ggpht.com')) {
      if (raw.contains('=')) {
        // Has some other param; replace from last '=' if it looks like size junk.
        final idx = raw.lastIndexOf('=');
        final tail = raw.substring(idx + 1);
        if (RegExp(r'^[ws]\d+').hasMatch(tail) || tail.contains('-rj')) {
          return '${raw.substring(0, idx)}=w$size-h$size-l90-rj';
        }
      }
      return '$raw=w$size-h$size-l90-rj';
    }

    // Legacy -rj / =s branches
    if (raw.contains('-rj') && raw.contains('=')) {
      return '${raw.split('=').first}=w$size-h$size-l90-rj';
    }
    if (raw.contains('=s')) {
      return '${raw.split('=s').first}=s$size';
    }
    return raw;
  }
}
