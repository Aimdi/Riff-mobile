import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_transcripts.dart';
import 'package:harmonymusic/services/youtube_captions.dart';

void main() {
  test("the player response's caption tracks: language, made by whom", () {
    final tracks = parseCaptionTracks({
      'captions': {
        'playerCaptionsTracklistRenderer': {
          'captionTracks': [
            {
              'baseUrl': 'https://www.youtube.com/api/timedtext?v=x&lang=de',
              'languageCode': 'de',
              'name': {'simpleText': 'German'},
            },
            {
              'baseUrl':
                  'https://www.youtube.com/api/timedtext?v=x&lang=en&kind=asr',
              'languageCode': 'en',
              'kind': 'asr',
            },
            // Without an address: left out.
            {'languageCode': 'fr'},
          ],
        },
      },
    });
    expect(tracks.map((t) => (t.lang, t.auto)), [('de', false), ('en', true)]);
    // The app's own pick: a person's track in the app language, else
    // YouTube's.
    final choices = [for (final t in tracks) (lang: t.lang, auto: t.auto)];
    expect(pickCaptionTrack(choices, 'en'), 1);
    expect(pickCaptionTrack(choices, 'de'), 0);
  });

  test('no captions, or a response in another shape: no tracks', () {
    expect(parseCaptionTracks(null), isEmpty);
    expect(parseCaptionTracks({'playabilityStatus': {}}), isEmpty);
    expect(
        parseCaptionTracks({
          'captions': {'playerCaptionsTracklistRenderer': {}}
        }),
        isEmpty);
  });

  test('a track is asked for as WebVTT, its other parameters kept', () {
    final url = withVttFormat(
        'https://www.youtube.com/api/timedtext?v=abc&lang=en&fmt=srv3&caps=asr');
    final q = Uri.parse(url).queryParameters;
    expect(q['fmt'], 'vtt');
    expect(q['v'], 'abc');
    expect(q['lang'], 'en');
    expect(q['caps'], 'asr');
  });

  test("the visitor id in YouTube's sw.js_data reply", () {
    const reply = ")]}'\n[[\"a\",1,[[[null,null,null,null,null,null,null,"
        "null,null,null,null,null,null,\"CgtWaXNpdG9y\"]]]]]";
    expect(parseVisitorData(reply), 'CgtWaXNpdG9y');
    expect(parseVisitorData('<html>'), isNull);
    expect(parseVisitorData(null), isNull);
  });

  test("a watch page's cookies, with a browser's consent ones", () {
    expect(
        watchPageCookies([
          'YSC=abc123; Domain=.youtube.com; Path=/; Secure; HttpOnly',
          'VISITOR_INFO1_LIVE=xyz; Domain=.youtube.com; Expires=Fri',
          'broken',
        ]),
        'YSC=abc123; VISITOR_INFO1_LIVE=xyz; PREF=hl=en; SOCS=CAI; GPS=1');
  });
}
