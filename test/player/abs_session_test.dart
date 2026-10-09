import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/abs_session.dart';

MediaItem _track(String id, int minutes) => MediaItem(
      id: id,
      title: id,
      duration: Duration(minutes: minutes),
      extras: const {'streamSource': 'audiobookshelf'},
    );

void main() {
  test('the queued book is the Audiobookshelf tracks only', () {
    final queue = [
      _track('abs_b_0', 30),
      _track('abs_b_1', 30),
      const MediaItem(
          id: 'song', title: 'Song', duration: Duration(minutes: 4)),
      const MediaItem(id: 'abs_b_2', title: 'no length'),
    ];
    expect(absQueuedBookSec(queue), 3600);
    expect(absQueuedBookSec(const []), 0);
  });

  test('closing while the book is still queued uses the queued book', () {
    expect(
      absCloseBookSec(
        queuedBookSec: 3600,
        syncedBookSec: 1800,
        outgoingTotal: const Duration(minutes: 30),
      ),
      3600,
    );
  });

  test('leaving the book for music closes with the synced book length', () {
    // The queue is the music now (nothing to sum) and the shared progress
    // bar holds the incoming song's 3:20 — what the session used to be
    // closed with, against a book-absolute currentTime of an hour or more.
    expect(
      absCloseBookSec(
        queuedBookSec: 0,
        syncedBookSec: 3600,
        outgoingTotal: const Duration(minutes: 30),
      ),
      3600,
    );
  });

  test('with nothing known, the outgoing track\'s own length', () {
    expect(
      absCloseBookSec(
        queuedBookSec: 0,
        syncedBookSec: 0,
        outgoingTotal: const Duration(minutes: 30),
      ),
      1800,
    );
  });
}
