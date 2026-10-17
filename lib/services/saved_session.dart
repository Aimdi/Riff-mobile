import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/utils/hive_boxes.dart';

/// What the player keeps each time Riff goes to the background
/// (MyAudioHandler.saveSessionData): the queue, the song playing in it and
/// where, and where the queue came from.
class SavedSession {
  const SavedSession({
    required this.queue,
    required this.index,
    required this.position,
    this.from,
  });

  final List<MediaItem> queue;

  /// The song that was playing, in [queue] (always one of its songs).
  final int index;

  /// Where in it.
  final Duration position;

  /// Where the queue came from (PlaylingFrom.toJson); null in a session
  /// saved before Riff kept it.
  final Object? from;

  MediaItem get song => queue[index];

  /// What [box] holds: null when nothing was saved, or nothing that plays.
  static SavedSession? read(Box box) {
    final raw = box.get('queue');
    if (raw is! List || raw.isEmpty) return null;
    final List<MediaItem> queue;
    try {
      queue = [for (final json in raw) MediaItemBuilder.fromJson(json)];
    } catch (_) {
      return null;
    }
    final index = box.get('index');
    final position = box.get('position');
    return SavedSession(
      queue: queue,
      index: index is int ? index.clamp(0, queue.length - 1) : 0,
      position: Duration(
          milliseconds: position is int && position > 0 ? position : 0),
      from: box.get('from'),
    );
  }

  /// The session saved last time, if there is one.
  static Future<SavedSession?> load() async =>
      read(await HiveBoxes.open(HiveBoxes.prevSessionData));
}

/// The saved session coming back into the player, one at a time: Riff
/// opening (paused) and Play pressed outside Riff (playing on) can both
/// ask at once, as when Android's media controls start Riff.
class SessionComeback {
  SessionComeback({
    required this.loaded,
    required this.bringBack,
    Future<SavedSession?> Function()? load,
  }) : load = load ?? SavedSession.load;

  /// Whether the player has a queue already: then nothing comes back.
  final bool Function() loaded;

  /// The session saved last time.
  final Future<SavedSession?> Function() load;

  /// Puts [session] in the player: paused, or [play]ing on from its place.
  final Future<void> Function(SavedSession session, {required bool play})
      bringBack;

  Future<bool>? _coming;

  /// It is coming back now.
  bool get coming => _coming != null;

  /// Brings the saved session back ([play]: playing on from its place);
  /// true once it's back. False with something in the player already, or
  /// nothing saved. While it is coming back, the same answer: the one
  /// already coming isn't brought back twice.
  Future<bool> call({required bool play}) {
    if (_coming case final coming?) return coming;
    if (loaded()) return Future.value(false);
    final coming = _comeBack(play);
    _coming = coming;
    return coming.whenComplete(() => _coming = null);
  }

  Future<bool> _comeBack(bool play) async {
    final session = await load();
    // Nothing saved, or something else went in meanwhile (the car, a link).
    if (session == null || loaded()) return false;
    await bringBack(session, play: play);
    return true;
  }
}
