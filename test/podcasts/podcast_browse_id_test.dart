import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/music_service.dart';

void main() {
  test('podcast browse id from every id form YouTube returns', () {
    expect(podcastBrowseId('PLabc'), 'MPSPPLabc');
    expect(podcastBrowseId('MPSPPLabc'), 'MPSPPLabc');
    // Search sometimes returns the show as a VL playlist id: asking for
    // MPSPVL… returned no episodes.
    expect(podcastBrowseId('VLPLabc'), 'MPSPPLabc');
    expect(podcastBrowseId(' PLabc '), 'MPSPPLabc');
  });
}
