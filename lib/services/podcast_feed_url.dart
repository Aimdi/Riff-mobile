import 'package:xml/xml.dart';

/// The schemes podcast sites use for "subscribe" links (feed://…,
/// pcast://…); the address after them is the feed's.
final _subscribeScheme =
    RegExp(r'^(?:feed|pcast|itpc|podcast):(?://)?', caseSensitive: false);

/// The feed address in [input], when it is one, so a pasted RSS link opens
/// that show as in AntennaPod, Pocket Casts, Apple Podcasts and Overcast:
/// an http(s) link (not YouTube's, which opens as a channel), or a
/// feed:// / pcast:// / itpc:// / podcast:// subscribe link (read as
/// https). Null for anything else, words included.
String? podcastFeedUrlFrom(String input) {
  var s = input.trim();
  if (s.isEmpty || s.contains(RegExp(r'\s'))) return null;
  final scheme = _subscribeScheme.firstMatch(s);
  if (scheme != null) {
    s = s.substring(scheme.end);
    if (!s.toLowerCase().startsWith('http')) s = 'https://$s';
  }
  final uri = Uri.tryParse(s);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      !uri.host.contains('.')) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host == 'youtu.be' ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com')) {
    return null;
  }
  return uri.toString();
}

/// A feed's own name, host and cover ({title, author, artwork}), or null
/// when [body] isn't a podcast feed (no RSS channel with a title). Throws
/// on bad XML.
Map<String, String>? parsePodcastFeedInfo(String body) {
  final channel =
      XmlDocument.parse(body).findAllElements('channel').firstOrNull;
  if (channel == null) return null;
  String text(String name) => channel.getElement(name)?.innerText.trim() ?? '';
  final title = text('title');
  if (title.isEmpty) return null;
  final owner = channel.getElement('itunes:owner')?.getElement('itunes:name');
  final author = [
    text('itunes:author'),
    owner?.innerText.trim() ?? '',
    text('managingEditor'),
  ].firstWhere((a) => a.isNotEmpty, orElse: () => '');
  final artwork = [
    channel.getElement('itunes:image')?.getAttribute('href')?.trim() ?? '',
    channel.getElement('image')?.getElement('url')?.innerText.trim() ?? '',
  ].firstWhere((a) => a.isNotEmpty, orElse: () => '');
  return {'title': title, 'author': author, 'artwork': artwork};
}
