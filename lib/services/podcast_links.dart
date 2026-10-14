/// Podcast links Riff opens, as AntennaPod and Pocket Casts take them: a
/// podcast site's subscribe link (feed://, pcast://, itpc://, podcast://,
/// antennapod-subscribe://, Subscribe on Android's and AntennaPod's own
/// pages), a show's page on Apple Podcasts or Overcast, an old Google
/// Podcasts link, or a feed's own address. Each names a show by its feed,
/// or by its id in Apple's directory (looked up there).
library;

import 'dart:convert';

import 'podcast_feed_url.dart';
import 'podcast_service.dart';

class PodcastLink {
  const PodcastLink.feed(String this.feedUrl, {this.schemeGuessed = false})
      : appleId = null;
  const PodcastLink.apple(String this.appleId)
      : feedUrl = null,
        schemeGuessed = false;

  /// The show's feed.
  final String? feedUrl;

  /// The show's id in Apple's directory.
  final String? appleId;

  /// The link didn't say http or https ([feedUrl] has https): http may
  /// still be the one that works.
  final bool schemeGuessed;
}

/// Schemes podcast sites use for "subscribe" links.
const podcastSubscribeSchemes = {
  'feed',
  'pcast',
  'itpc',
  'podcast',
  'antennapod-subscribe',
};

/// A link in shared text (apps share a title, then the link), or the text
/// itself when it's one link: http(s), riff:// and the subscribe schemes.
final _linkInText = RegExp(
    r'\b(?:https?|riff|feed|pcast|itpc|podcast|antennapod-subscribe):\S+',
    caseSensitive: false);

/// The link in [text] (shared to Riff or pasted into its search), as it
/// was written; null when there's none.
String? linkInText(String text) {
  final match = _linkInText.firstMatch(text.trim());
  if (match == null) return null;
  // Sentences end links with a full stop or a bracket.
  return match.group(0)!.replaceFirst(RegExp(r'[.,;:!?)\]}>"]+$'), '');
}

/// What podcast [link] names (as [linkInText] gives it), or null when it
/// isn't a podcast link.
PodcastLink? podcastLinkFrom(String link) {
  final s = link.trim();
  final colon = s.indexOf(':');
  if (colon <= 0) return null;
  final scheme = s.substring(0, colon).toLowerCase();
  if (podcastSubscribeSchemes.contains(scheme)) {
    var rest = s.substring(colon + 1);
    if (rest.startsWith('//')) rest = rest.substring(2);
    return _feed(rest);
  }
  if (scheme != 'http' && scheme != 'https') return null;
  final uri = Uri.tryParse(s);
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  switch (host) {
    // subscribeonandroid.com/feeds.example.com/show.xml
    case 'subscribeonandroid.com':
      final rest = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      return _feed(rest.replaceFirst(RegExp(r'^/+'), ''));
    case 'antennapod.org':
      final url = uri.path.startsWith('/deeplink/subscribe')
          ? uri.queryParameters['url']
          : null;
      return url == null ? null : _feed(url);
    // …/podcast/the-show/id1200361736 (?i=… names an episode of it)
    case 'podcasts.apple.com' || 'itunes.apple.com':
      final id = RegExp(r'/id(\d+)').firstMatch(uri.path)?.group(1);
      return id == null ? null : PodcastLink.apple(id);
    // overcast.fm/itunes1200361736/the-show
    case 'overcast.fm':
      final id = RegExp(r'^/itunes(\d+)').firstMatch(uri.path)?.group(1);
      return id == null ? null : PodcastLink.apple(id);
    // podcasts.google.com/feed/<the feed's address in base64>
    case 'podcasts.google.com':
      final segments = uri.pathSegments;
      final at = segments.indexOf('feed');
      if (at < 0 || at + 1 >= segments.length) return null;
      try {
        final url = utf8
            .decode(base64Url.decode(base64Url.normalize(segments[at + 1])));
        return _feed(url);
      } catch (_) {
        return null;
      }
  }
  return null;
}

PodcastLink? _feed(String address) {
  var a = address.trim();
  final guessed = !RegExp(r'^https?://', caseSensitive: false).hasMatch(a);
  if (guessed) a = 'https://$a';
  final url = podcastFeedUrlFrom(a);
  return url == null ? null : PodcastLink.feed(url, schemeGuessed: guessed);
}

/// The show [link] names ({title, author, artwork, feedUrl}): looked up in
/// Apple's directory, or read from its feed (over http when https fails,
/// for a link that didn't say which); null when there's none to be found.
Future<Map<String, dynamic>?> podcastShowFor(PodcastLink link) async {
  final id = link.appleId;
  if (id != null) return PodcastService.directoryShow(id);
  final feed = link.feedUrl!;
  final show = await PodcastService.feedInfo(feed);
  if (show != null || !link.schemeGuessed) return show;
  return PodcastService.feedInfo(feed.replaceFirst(RegExp('^https:'), 'http:'));
}
