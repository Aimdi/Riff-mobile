import 'package:xml/xml.dart';

/// One show in an OPML subscription list.
class OpmlFeed {
  const OpmlFeed({required this.feedUrl, this.title = ''});
  final String feedUrl;
  final String title;
}

/// Feeds in an OPML document: every `<outline>` with an `xmlUrl` (any
/// case), nested folders included, duplicates dropped. Empty for anything
/// that isn't OPML.
List<OpmlFeed> parseOpml(String source) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(source.trim());
  } catch (_) {
    return const [];
  }
  final seen = <String>{};
  final out = <OpmlFeed>[];
  for (final o in doc.findAllElements('outline')) {
    String? attr(String name) {
      for (final a in o.attributes) {
        if (a.name.local.toLowerCase() == name) return a.value.trim();
      }
      return null;
    }

    final url = attr('xmlurl') ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      continue;
    }
    if (!seen.add(url)) continue;
    out.add(OpmlFeed(
        feedUrl: url, title: attr('text') ?? attr('title') ?? ''));
  }
  return out;
}

/// An OPML 2.0 document listing [feeds], for other podcast apps.
String buildOpml(List<OpmlFeed> feeds,
    {String title = 'Riff podcast subscriptions', DateTime? now}) {
  final b = XmlBuilder();
  b.processing('xml', 'version="1.0" encoding="UTF-8"');
  b.element('opml', attributes: {'version': '2.0'}, nest: () {
    b.element('head', nest: () {
      b.element('title', nest: title);
      b.element('dateCreated',
          nest: _rfc822((now ?? DateTime.now()).toUtc()));
    });
    b.element('body', nest: () {
      for (final f in feeds) {
        b.element('outline', attributes: {
          'type': 'rss',
          'text': f.title,
          'title': f.title,
          'xmlUrl': f.feedUrl,
        });
      }
    });
  });
  return b.buildDocument().toXmlString(pretty: true, indent: '  ');
}

String _rfc822(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[d.weekday - 1]}, ${two(d.day)} ${months[d.month - 1]} '
      '${d.year} ${two(d.hour)}:${two(d.minute)}:${two(d.second)} GMT';
}
