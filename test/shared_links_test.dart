import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/app_link_controller.dart' show ProcessLink;

/// What [openLinkIn] would open.
class _Links with ProcessLink {
  final opened = <String?>[];

  @override
  Future<void> filterLinks(Uri uri, {String? written}) async =>
      opened.add(written);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shared text opens the link in it, as it was written', () async {
    final links = _Links();
    await links.openLinkIn('The Show https://podcasts.apple.com/x/id1 ');
    await links.openLinkIn('pcast://http://example.com/feed.xml');
    // No link in it: nothing opens.
    await links.openLinkIn('just some words');
    expect(links.opened, [
      'https://podcasts.apple.com/x/id1',
      'pcast://http://example.com/feed.xml',
    ]);
  });
}
