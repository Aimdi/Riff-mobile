import 'package:audio_service/audio_service.dart';

import '/models/media_item_extras.dart';

/// Seconds of the Audiobookshelf book in [queue] (a book is queued track
/// by track); 0 when no Audiobookshelf track there carries a length.
double absQueuedBookSec(Iterable<MediaItem> queue) =>
    queue.fold<double>(0, (sum, m) {
      if (!m.isAudiobookshelf) return sum;
      return sum + (m.duration?.inMilliseconds ?? 0) / 1000.0;
    });

/// Book length to close an Audiobookshelf session with when playback
/// leaves one of its tracks: the queued book while it is still queued,
/// else the length last synced for that session, else the outgoing
/// track's own length — never the length of whatever plays next.
double absCloseBookSec({
  required double queuedBookSec,
  required double syncedBookSec,
  required Duration outgoingTotal,
}) {
  if (queuedBookSec > 0) return queuedBookSec;
  if (syncedBookSec > 0) return syncedBookSec;
  return outgoingTotal.inMilliseconds / 1000.0;
}
