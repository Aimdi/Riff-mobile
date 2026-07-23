/// Parse YouTube / YouTube Music channel URLs and bare channel ids.
class YoutubeChannelUrl {
  YoutubeChannelUrl._();

  /// Returns a `UC…` channel id when [input] is a channel URL or bare id.
  static String? tryChannelId(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    if (RegExp(r'^UC[\w-]{20,}$').hasMatch(s)) return s;

    final uri = Uri.tryParse(s.contains('://') ? s : 'https://$s');
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (!(host.contains('youtube.com') ||
        host.contains('youtu.be') ||
        host.contains('music.youtube.com'))) {
      // Still allow path-only "/channel/UC…"
      if (!s.contains('/channel/')) return null;
    }

    final segs = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    final idx = segs.indexOf('channel');
    if (idx >= 0 && idx + 1 < segs.length) {
      final id = segs[idx + 1];
      if (RegExp(r'^UC[\w-]{20,}$').hasMatch(id)) return id;
    }
    return null;
  }

  /// Returns a handle without `@` when [input] is `@name` or `/@name` URL.
  static String? tryHandle(String input) {
    final s = input.trim();
    if (s.startsWith('@') && s.length > 1) {
      return s.substring(1).split(RegExp(r'[/?#]')).first;
    }
    final uri = Uri.tryParse(s.contains('://') ? s : 'https://$s');
    if (uri == null) return null;
    for (final seg in uri.pathSegments) {
      if (seg.startsWith('@') && seg.length > 1) {
        return seg.substring(1);
      }
    }
    return null;
  }

  static bool looksLikeYoutubeInput(String input) {
    final s = input.trim().toLowerCase();
    return tryChannelId(input) != null ||
        tryHandle(input) != null ||
        s.contains('youtube.com') ||
        s.contains('youtu.be') ||
        s.startsWith('uc');
  }
}
