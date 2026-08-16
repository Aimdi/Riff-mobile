import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/soulseek/soulseek_client.dart';
import 'package:harmonymusic/ui/screens/Plugins/soulseek_play.dart';

SoulseekFile _hit({
  String user = 'alice',
  String filename = r'C:\music\Album\01 Track.flac',
  int? length,
}) =>
    SoulseekFile(
      username: user,
      filename: filename,
      size: 123456,
      hasFreeSlot: true,
      speed: 100,
      lengthSeconds: length,
    );

void main() {
  test('soulseek rows play on tap', () {
    expect(shouldPlaySoulseekOnTap(), isTrue);
  });

  test('soulseek media id is stable and not a YouTube video id', () {
    final a = soulseekMediaId(
      username: 'alice',
      filename: r'C:\music\Album\01 Track.flac',
    );
    final b = soulseekMediaId(
      username: 'alice',
      filename: r'C:\music\Album\01 Track.flac',
    );
    expect(a, b);
    expect(a.startsWith('slsk_'), isTrue);
    expect(a.contains('alice'), isTrue);
  });

  test('soulseekFileToMediaItem uses a local file url', () {
    final item = soulseekFileToMediaItem(
      _hit(length: 180),
      filePath: '/tmp/soulseek/01 Track.flac',
    );
    expect(item.id.startsWith('slsk_'), isTrue);
    expect(item.title, '01 Track');
    expect(item.extras?['url'], 'file:///tmp/soulseek/01 Track.flac');
    expect(item.extras?['streamSource'], 'soulseek');
    expect(item.duration, const Duration(seconds: 180));
  });
}
