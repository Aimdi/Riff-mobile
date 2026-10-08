import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/artist.dart';
import '/models/thumbnail.dart';
import '/services/music_service.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/riff_sheet.dart';
import '../player_media_ids.dart';

/// Artist photos for the chooser: from the library when the artist is
/// saved there, else looked up once on YouTube Music and kept for the
/// session. Null (a letter avatar) when there is none or offline.
class ArtistPhotos {
  ArtistPhotos._();

  static final Map<String, String> _known = {};
  static final Map<String, Future<String?>> _pending = {};

  /// Looks an artist's photo up online. Overridable for tests.
  static Future<String?> Function(String id) fetch = _fromYouTube;

  static String? known(String id) => _known[id] ?? _fromLibrary(id);

  static Future<String?> of(String id) {
    final hit = known(id);
    if (hit != null) return Future.value(hit);
    return _pending[id] ??= () async {
      String? url;
      try {
        url = await fetch(id).timeout(const Duration(seconds: 10));
      } catch (_) {
        url = null;
      }
      _pending.remove(id);
      // Only hits are kept, so a lookup that failed offline runs again.
      if (url != null && url.isNotEmpty) _known[id] = url;
      return url;
    }();
  }

  @visibleForTesting
  static void clear() {
    _known.clear();
    _pending.clear();
  }

  static String? _fromLibrary(String id) {
    if (!Hive.isBoxOpen('LibraryArtists')) return null;
    final saved = Hive.box('LibraryArtists').get(id);
    if (saved is! Map) return null;
    final url = Thumbnail.bestUrl(saved['thumbnails'], target: 'high');
    return url.isEmpty ? null : url;
  }

  static Future<String?> _fromYouTube(String id) async {
    if (!Get.isRegistered<MusicServices>()) return null;
    final data = await Get.find<MusicServices>().getArtist(id);
    final url = Thumbnail.bestUrl(data['thumbnails'], target: 'high');
    return url.isEmpty ? null : url;
  }
}

/// "Choose artist": one row per artist of a song with several, like
/// Spotify. Picking one closes the sheet and calls [onPick] with its id.
Future<void> showArtistChooser(
  BuildContext context,
  List<SongArtistRef> artists, {
  required void Function(String id) onPick,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    constraints:
        const BoxConstraints(maxWidth: RiffComponentSizes.sheetMaxWidth),
    builder: (sheetContext) => ArtistChooserSheet(
      artists: artists,
      onPick: (id) {
        Navigator.of(sheetContext).pop();
        onPick(id);
      },
    ),
  );
}

class ArtistChooserSheet extends StatelessWidget {
  const ArtistChooserSheet(
      {super.key, required this.artists, required this.onPick});

  final List<SongArtistRef> artists;
  final void Function(String id) onPick;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RiffSheetHandle(),
          RiffSheetTitle('chooseArtist'.tr),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: RiffSpacing.md),
              children: [
                for (final a in artists)
                  _ArtistChoice(artist: a, onTap: () => onPick(a.id)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistChoice extends StatefulWidget {
  const _ArtistChoice({required this.artist, required this.onTap});
  final SongArtistRef artist;
  final VoidCallback onTap;

  @override
  State<_ArtistChoice> createState() => _ArtistChoiceState();
}

class _ArtistChoiceState extends State<_ArtistChoice> {
  String? _photo;

  @override
  void initState() {
    super.initState();
    _photo = ArtistPhotos.known(widget.artist.id);
    if (_photo == null) {
      unawaited(ArtistPhotos.of(widget.artist.id).then((url) {
        if (mounted && url != null) setState(() => _photo = url);
      }));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.artist;
    return InkWell(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: RiffSpacing.lg, vertical: RiffSpacing.sm),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: ImageWidget(
                key: ValueKey(_photo ?? ''),
                size: RiffComponentSizes.rowArt,
                artist: Artist(
                    name: a.name, browseId: a.id, thumbnailUrl: _photo ?? ''),
              ),
            ),
            const SizedBox(width: RiffSpacing.lg),
            Expanded(
              child: Text(
                a.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
