import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Side of a saved folder photo in pixels: sharp on the largest folder tile
/// at 3× density, and only tens of kilobytes as a JPEG.
const int kFolderCoverSide = 640;

/// JPEG quality for saved folder photos.
const int kFolderCoverQuality = 82;

/// A picked photo made ready for a folder tile: turned upright (EXIF),
/// centre-cropped to a square, shrunk to [kFolderCoverSide] (never
/// enlarged) and re-encoded as a JPEG. Null when [bytes] isn't an image.
Uint8List? processFolderCover(Uint8List bytes) {
  img.Image? decoded;
  try {
    // Some decoders throw on truncated or foreign data instead of
    // returning null.
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) return null;
  final upright = img.bakeOrientation(decoded);
  final side = math.min(upright.width, upright.height);
  final square = img.copyCrop(upright,
      x: (upright.width - side) ~/ 2,
      y: (upright.height - side) ~/ 2,
      width: side,
      height: side);
  final sized = side > kFolderCoverSide
      ? img.copyResize(square,
          width: kFolderCoverSide,
          height: kFolderCoverSide,
          interpolation: img.Interpolation.average)
      : square;
  return Uint8List.fromList(img.encodeJpg(sized, quality: kFolderCoverQuality));
}

/// Where folder photos live: one JPEG per folder in the app's support
/// directory (not backed up by the OS media scanner, removed with the app).
class FolderCoverStore {
  FolderCoverStore._();

  /// Overridable for tests.
  static Future<String> Function() baseDir =
      () async => (await getApplicationSupportDirectory()).path;

  /// Processes [original] off the UI thread and saves it for [folderId].
  /// Returns the new file's path, or null when it isn't a usable image.
  static Future<String?> save(String folderId, Uint8List original) async {
    final jpg = await Isolate.run(() => processFolderCover(original));
    if (jpg == null) return null;
    final dir = Directory('${await baseDir()}/folder_covers');
    await dir.create(recursive: true);
    // A new name per save, so image caches never show the old photo.
    final path =
        '${dir.path}/${folderId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(jpg, flush: true);
    return path;
  }

  static void delete(String? path) {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
