/// `podcasts/subscriptions.opml` of the Riff sync format: an ordinary OPML
/// 2.0 subscription list (other podcast apps can import it) with Riff's
/// per-feed times and unsubscribe tombstones in the `urn:riff:sync:1`
/// namespace. See docs/sync-format.md.
library;

import 'package:xml/xml.dart';

import 'sync_merge.dart';

const riffSyncNs = 'urn:riff:sync:1';

/// Outline attributes the format defines; others are kept in `attrs`.
const _knownAttrs = {
  'type',
  'text',
  'title',
  'xmlUrl',
  'riff:updatedAt',
  'riff:device',
  'riff:author',
  'riff:artwork',
};

int _int(String? v) => int.tryParse(v ?? '') ?? 0;

String? _attr(XmlElement e, String name) {
  for (final a in e.attributes) {
    if (a.name.qualified == name) return a.value;
  }
  // `xmlUrl` in any case, as other apps write it.
  final lower = name.toLowerCase();
  for (final a in e.attributes) {
    if (a.name.qualified.toLowerCase() == lower) return a.value;
  }
  return null;
}

/// Subscription records from the OPML file, keyed by feed URL. Throws
/// [FormatException] for anything that isn't OPML.
Map<String, SyncRecord> decodeSubscriptionsOpml(String source) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(source.trim());
  } catch (_) {
    throw const FormatException('Not XML');
  }
  final opml = doc.rootElement;
  if (opml.name.local.toLowerCase() != 'opml') {
    throw const FormatException('Not OPML');
  }
  final out = <String, SyncRecord>{};
  final body = opml.getElement('body');
  if (body != null) {
    for (final o in body.findAllElements('outline')) {
      final url = (_attr(o, 'xmlUrl') ?? '').trim();
      if (url.isEmpty) continue;
      final title = _attr(o, 'title') ?? _attr(o, 'text') ?? '';
      final record = SyncRecord(
        updatedAt: _int(_attr(o, 'riff:updatedAt')),
        device: _attr(o, 'riff:device') ?? '',
        data: {
          'feedUrl': url,
          'title': title,
          if (_attr(o, 'riff:author') case final a?) 'author': a,
          if (_attr(o, 'riff:artwork') case final a?) 'artwork': a,
          if (_otherAttrs(o) case final attrs when attrs.isNotEmpty)
            'attrs': attrs,
        },
      );
      final prev = out[url];
      if (prev == null || compareRecords(record, prev) > 0) out[url] = record;
    }
  }
  final head = opml.getElement('head');
  if (head != null) {
    for (final t in head.childElements) {
      if (t.name.local != 'tombstone' || t.name.namespaceUri != riffSyncNs) {
        continue;
      }
      final url = (t.getAttribute('xmlUrl') ?? '').trim();
      if (url.isEmpty) continue;
      final record = SyncRecord.tombstone(
          updatedAt: _int(t.getAttribute('updatedAt')),
          device: t.getAttribute('device') ?? '');
      final prev = out[url];
      if (prev == null || compareRecords(record, prev) > 0) out[url] = record;
    }
  }
  return out;
}

Map<String, String> _otherAttrs(XmlElement o) => {
      for (final a in o.attributes)
        if (!_knownAttrs.contains(a.name.qualified) &&
            a.name.qualified.toLowerCase() != 'xmlurl' &&
            a.name.prefix != 'xmlns' &&
            a.name.qualified != 'xmlns')
          a.name.qualified: a.value
    };

/// The OPML file for [records].
String encodeSubscriptionsOpml(Map<String, SyncRecord> records,
    {required int nowMs, required String device}) {
  final ids = records.keys.toList()
    ..sort((a, b) {
      final ta = '${records[a]!.data?['title'] ?? ''}'.toLowerCase();
      final tb = '${records[b]!.data?['title'] ?? ''}'.toLowerCase();
      final c = ta.compareTo(tb);
      return c != 0 ? c : a.compareTo(b);
    });
  final b = XmlBuilder();
  b.processing('xml', 'version="1.0" encoding="UTF-8"');
  b.element('opml', attributes: {
    'version': '2.0',
    'xmlns:riff': riffSyncNs,
  }, nest: () {
    b.element('head', nest: () {
      b.element('title', nest: 'Riff podcast subscriptions');
      b.element('riff:sync', attributes: {
        'version': '$syncFormatVersion',
        'updatedAt': '$nowMs',
        'device': device,
      });
      for (final id in ids) {
        final r = records[id]!;
        if (!r.deleted) continue;
        b.element('riff:tombstone', attributes: {
          'xmlUrl': id,
          'updatedAt': '${r.updatedAt}',
          'device': r.device,
        });
      }
    });
    b.element('body', nest: () {
      for (final id in ids) {
        final r = records[id]!;
        if (r.deleted) continue;
        final d = r.data ?? const {};
        final title = '${d['title'] ?? ''}';
        final attrs = d['attrs'];
        b.element('outline', attributes: {
          if (attrs is Map)
            for (final e in attrs.entries) '${e.key}': '${e.value}',
          'type': 'rss',
          'text': title,
          'title': title,
          'xmlUrl': id,
          'riff:updatedAt': '${r.updatedAt}',
          'riff:device': r.device,
          if ('${d['author'] ?? ''}'.isNotEmpty)
            'riff:author': '${d['author']}',
          if ('${d['artwork'] ?? ''}'.isNotEmpty)
            'riff:artwork': '${d['artwork']}',
        });
      }
    });
  });
  return b.buildDocument().toXmlString(pretty: true, indent: '  ');
}
