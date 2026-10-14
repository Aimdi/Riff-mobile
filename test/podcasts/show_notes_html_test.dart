import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_service.dart';

String notes(String html) => PodcastService.showNotesText(html);

void main() {
  test('paragraphs and line breaks stay apart', () {
    // Stripping the tags gave "OneTwo".
    expect(notes('<p>One</p><p>Two</p>'), 'One\n\nTwo');
    expect(notes('Line 1<br>Line 2<BR/>Line 3'), 'Line 1\nLine 2\nLine 3');
    expect(notes('<p>  Hello\n   <b>big</b>   world </p>'), 'Hello big world');
    expect(notes('<h2>Links</h2><div>One</div><div>Two</div>'),
        'Links\n\nOne\nTwo');
  });

  test('list items get lines of their own', () {
    expect(
        notes('<p>Topics:</p><ul><li>Intro</li><li>Interview</li></ul>'
            '<p>Bye</p>'),
        'Topics:\n\n• Intro\n• Interview\n\nBye');
    expect(notes('<ol><li>Intro</li><li>Interview</li></ol>'),
        '1. Intro\n2. Interview');
    // A paragraph inside an item is only a line.
    expect(notes('<ul><li><p>A</p></li><li><p>B</p></li></ul>'), '• A\n• B');
  });

  test("a link keeps its words and where it goes", () {
    expect(notes('Visit <a href="https://example.com/x">our site</a> today'),
        'Visit [our site](https://example.com/x) today');
    // Its address written out, or a timestamp: as they are.
    expect(notes('<a href="https://a.example">https://a.example</a>'),
        'https://a.example');
    expect(notes('<a href="https://a.example/ep#t=754">12:34</a> Interview'),
        '12:34 Interview');
    // Not a web address: the words.
    expect(notes('<a href="mailto:hi@a.example">Write in</a>'), 'Write in');
    expect(notes('<a href="/ep/1">Episode 1</a>'), 'Episode 1');
    // Brackets in the address don't end the link early.
    expect(notes("<a href='https://en.wikipedia.org/wiki/Foo_(bar)'>Foo</a>"),
        '[Foo](https://en.wikipedia.org/wiki/Foo_%28bar%29)');
    expect(notes('<a href="https://a.example/?a=1&amp;b=2">Q</a>'),
        '[Q](https://a.example/?a=1&b=2)');
    // An image-only link: nothing.
    expect(notes('<a href="https://a.example"><img src="x.png"></a>Hi'), 'Hi');
  });

  test('plain text keeps its own lines', () {
    expect(notes('Line one\nLine two\n\nNext paragraph'),
        'Line one\nLine two\n\nNext paragraph');
    expect(notes('Tom &amp; Jerry&#8217;s show'), 'Tom & Jerry’s show');
    expect(notes('   '), '');
  });

  test("a show's own description, the fuller of the two, as notes read", () {
    const feed = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel>
  <title>Show</title>
  <description>Short.</description>
  <itunes:summary><![CDATA[<p>A show about shows.</p><p>Every week.</p>]]></itunes:summary>
  <item>
    <title>Ep 1</title>
    <description>Not the show's.</description>
    <enclosure url="https://example.com/1.mp3"/>
  </item>
</channel>
</rss>''';
    final show = parsePodcastShow(feed, 'Show', '');
    expect(show.about, 'A show about shows.\n\nEvery week.');
    expect(show.episodes.single['description'], "Not the show's.");
  });

  test('scripts, styles and comments are left out', () {
    expect(
        notes('<style>p{color:red}</style><p>Kept</p><!-- not this -->'
            '<script>alert(1)</script>'),
        'Kept');
  });
}
