import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:xml/xml.dart';

/// Shownotes are HTML *inside* XML, so a feed's `<description>` is
/// double-escaped (`&amp;#39;`) or wrapped in CDATA. The XML parser undoes
/// exactly one level, leaving entity codes in the text handed to stripHtml.
/// Without decoding, every episode's shownotes render as "Tom &amp; Jerry&#8217;s".
void main() {
  group('PodcastService.stripHtml', () {
    test('drops tags and decodes named entities', () {
      expect(
        PodcastService.stripHtml('<p>Tom &amp; Jerry&#8217;s show</p>'),
        'Tom & Jerry’s show',
      );
      expect(
        PodcastService.stripHtml(
            '&quot;Quoted&quot; &mdash; don&apos;t&nbsp;stop &hellip;'),
        '"Quoted" — don\'t stop …',
      );
      expect(
        PodcastService.stripHtml('&ldquo;a&rdquo; &ndash; &lsquo;b&rsquo;'),
        '“a” – ‘b’',
      );
    });

    test('decodes decimal and hex numeric references', () {
      expect(PodcastService.stripHtml('don&#39;t &#x26; can&#X2019;t'),
          "don't & can’t");
    });

    test('leaves unknown and malformed references untouched', () {
      expect(PodcastService.stripHtml('a &notarealentity; b &amp c &#; d'),
          'a &notarealentity; b &amp c &#; d');
    });

    test('decodes in a single pass so &amp;#39; stays literal', () {
      // One decode level only: a feed that really escaped an entity code for
      // display must keep showing that code, not collapse into an apostrophe.
      expect(PodcastService.stripHtml('&amp;#39;'), '&#39;');
    });

    test('decodes shownotes parsed out of a real RSS description', () {
      const feed = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><item>
<description>&lt;p&gt;Tom &amp;amp; Jerry&amp;#8217;s show&lt;/p&gt;</description>
</item></channel></rss>''';
      final raw = XmlDocument.parse(feed)
          .findAllElements('description')
          .first
          .innerText;
      // The XML parser undid one level only.
      expect(raw, '<p>Tom &amp; Jerry&#8217;s show</p>');
      expect(PodcastService.stripHtml(raw), 'Tom & Jerry’s show');
    });
  });

  group('parseTranscriptDocument (HTML)', () {
    test('untimed HTML transcript cues are entity-decoded', () {
      final cues = PodcastService.parseTranscriptDocument(
        '<p>Bob &amp; Alice don&#39;t&nbsp;agree</p>'
        '<p>&quot;Quoted&quot; &mdash; end</p>',
        type: 'text/html',
      );
      expect(cues.length, 2);
      expect(cues[0].startSec, -1);
      expect(cues[0].text, "Bob & Alice don't agree");
      expect(cues[1].text, '"Quoted" — end');
    });
  });
}
