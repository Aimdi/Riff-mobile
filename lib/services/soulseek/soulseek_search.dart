import 'soulseek_client.dart';

/// Sockseek-style search mode (song file vs album folder).
enum SoulseekSearchMode { song, album }

/// Parsed search intent — mirrors sockseek `Artist - Title` shorthand.
class SoulseekQuery {
  const SoulseekQuery({
    required this.raw,
    required this.mode,
    this.artist,
    this.title,
  });

  final String raw;
  final SoulseekSearchMode mode;
  final String? artist;
  final String? title;

  /// Network search string (artist + title when both known).
  String get networkQuery {
    final a = artist?.trim() ?? '';
    final t = title?.trim() ?? '';
    if (a.isNotEmpty && t.isNotEmpty) return '$a $t';
    if (t.isNotEmpty) return t;
    if (a.isNotEmpty) return a;
    return raw.trim();
  }

  /// Parse sockseek-style input.
  ///
  /// `Artist - Title` → artist + title (song) or artist + album (album mode).
  /// Bare text stays as title/album hint.
  factory SoulseekQuery.parse(String input, SoulseekSearchMode mode) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return SoulseekQuery(raw: '', mode: mode);
    }

    // Keyed form: artist=X, title=Y
    if (raw.contains('=')) {
      String? artist;
      String? title;
      for (final part in raw.split(',')) {
        final eq = part.indexOf('=');
        if (eq <= 0) continue;
        final key = part.substring(0, eq).trim().toLowerCase();
        final val = part.substring(eq + 1).trim();
        if (val.isEmpty) continue;
        if (key == 'artist') artist = val;
        if (key == 'title' || key == 'album') title = val;
      }
      if (artist != null || title != null) {
        return SoulseekQuery(
          raw: raw,
          mode: mode,
          artist: artist,
          title: title ?? raw,
        );
      }
    }

    final split = RegExp(r'\s+-\s+').firstMatch(raw);
    if (split != null) {
      final artist = raw.substring(0, split.start).trim();
      final title = raw.substring(split.end).trim();
      if (artist.isNotEmpty && title.isNotEmpty) {
        return SoulseekQuery(
          raw: raw,
          mode: mode,
          artist: artist,
          title: title,
        );
      }
    }

    return SoulseekQuery(raw: raw, mode: mode, title: raw);
  }
}

/// Live filter / preference knobs (sockseek `--format` / `--pref-format` / slot).
class SoulseekSearchFilters {
  const SoulseekSearchFilters({
    this.formats = const {},
    this.freeSlotOnly = false,
    this.minBitrate = 0,
    this.preferredFormats = const ['flac', 'wav', 'alac', 'mp3'],
  });

  /// Required formats (empty = any audio). Like sockseek `--format`.
  final Set<String> formats;

  /// Only peers advertising a free slot.
  final bool freeSlotOnly;

  /// Minimum bitrate when known (0 = off). Unknown bitrate still accepted.
  final int minBitrate;

  /// Ranking preference order (first = best). Like sockseek `--pref-format`.
  final List<String> preferredFormats;

  SoulseekSearchFilters copyWith({
    Set<String>? formats,
    bool? freeSlotOnly,
    int? minBitrate,
    List<String>? preferredFormats,
  }) {
    return SoulseekSearchFilters(
      formats: formats ?? this.formats,
      freeSlotOnly: freeSlotOnly ?? this.freeSlotOnly,
      minBitrate: minBitrate ?? this.minBitrate,
      preferredFormats: preferredFormats ?? this.preferredFormats,
    );
  }

  bool accepts(SoulseekFile file) {
    if (formats.isNotEmpty && !formats.contains(file.extension)) return false;
    if (freeSlotOnly && !file.hasFreeSlot) return false;
    if (minBitrate > 0 &&
        file.bitRate != null &&
        file.bitRate! > 0 &&
        file.bitRate! < minBitrate) {
      return false;
    }
    return true;
  }
}

/// Ranked file with a sockseek-style score.
class RankedSoulseekFile {
  const RankedSoulseekFile({required this.file, required this.score});
  final SoulseekFile file;
  final int score;
}

/// Album/folder aggregate for album-mode interactive pick.
class SoulseekAlbumFolder {
  const SoulseekAlbumFolder({
    required this.username,
    required this.folderPath,
    required this.folderName,
    required this.files,
    required this.score,
  });

  final String username;
  final String folderPath;
  final String folderName;
  final List<SoulseekFile> files;
  final int score;

  int get trackCount => files.length;
  bool get hasFreeSlot => files.any((f) => f.hasFreeSlot);
  int get totalSize => files.fold(0, (a, b) => a + b.size);

  String get sizeLabel {
    final size = totalSize;
    if (size <= 0) return '—';
    const kb = 1000.0;
    const mb = kb * 1000;
    const gb = mb * 1000;
    if (size >= gb) return '${(size / gb).toStringAsFixed(2)} GB';
    if (size >= mb) return '${(size / mb).toStringAsFixed(1)} MB';
    return '${(size / kb).toStringAsFixed(0)} KB';
  }

  /// Dominant / preferred format among tracks.
  String get formatSummary {
    final counts = <String, int>{};
    for (final f in files) {
      final e = f.extension;
      if (e.isEmpty) continue;
      counts[e] = (counts[e] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key.toUpperCase()).take(2).join('/');
  }
}

/// Sockseek-inspired ranking & projection for mobile search results.
class SoulseekSearchRanker {
  const SoulseekSearchRanker();

  /// Score a single file (higher = better). Preferences never hard-filter.
  int scoreFile(
    SoulseekFile file,
    SoulseekQuery query,
    SoulseekSearchFilters filters,
  ) {
    var score = 0;
    final path = file.filename.toLowerCase();
    final name = file.displayName.toLowerCase();

    if (file.hasFreeSlot) score += 10000;

    final prefs = filters.preferredFormats;
    final ext = file.extension;
    final prefIdx = prefs.indexOf(ext);
    if (prefIdx >= 0) {
      score += 5000 - (prefIdx * 400);
    } else if (ext == 'flac' || ext == 'wav' || ext == 'alac') {
      score += 3500;
    } else if (ext == 'mp3' || ext == 'm4a' || ext == 'ogg' || ext == 'opus') {
      score += 2000;
    }

    final title = query.title?.toLowerCase().trim();
    final artist = query.artist?.toLowerCase().trim();
    if (title != null && title.isNotEmpty) {
      if (path.contains(title) || name.contains(title)) {
        score += 3000;
      } else {
        // Soft penalty when title clearly absent (sockseek strict-title pref).
        score -= 400;
      }
    }
    if (artist != null && artist.isNotEmpty) {
      if (path.contains(artist)) {
        score += 2000;
      } else {
        score -= 200;
      }
    }

    final br = file.bitRate ?? 0;
    if (br >= 200 && br <= 2500) {
      score += (br.clamp(0, 500) ~/ 2);
    } else if (br > 0 && br < 128) {
      score -= 800;
    }

    // Upload speed (bytes/s-ish from protocol) — gentle boost.
    if (file.speed > 0) {
      score += (file.speed ~/ 50000).clamp(0, 800);
    }

    return score;
  }

  List<RankedSoulseekFile> rankFiles(
    Iterable<SoulseekFile> files,
    SoulseekQuery query,
    SoulseekSearchFilters filters,
  ) {
    final ranked = <RankedSoulseekFile>[];
    for (final f in files) {
      if (!filters.accepts(f)) continue;
      ranked.add(
        RankedSoulseekFile(
          file: f,
          score: scoreFile(f, query, filters),
        ),
      );
    }
    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.file.size.compareTo(a.file.size);
    });
    return ranked;
  }

  /// Group into album folders (username + parent path), ranked like sockseek
  /// interactive album pick.
  List<SoulseekAlbumFolder> groupAlbums(
    Iterable<SoulseekFile> files,
    SoulseekQuery query,
    SoulseekSearchFilters filters,
  ) {
    final accepted = files.where(filters.accepts);
    final buckets = <String, List<SoulseekFile>>{};
    for (final f in accepted) {
      final key = '${f.username}|${f.folderPath}';
      (buckets[key] ??= []).add(f);
    }

    final folders = <SoulseekAlbumFolder>[];
    for (final entry in buckets.entries) {
      final list = entry.value
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
      if (list.isEmpty) continue;
      // Need enough audio tracks to look like an album folder.
      if (list.length < 2 && query.mode == SoulseekSearchMode.album) {
        // Still keep singles if folder name matches album hint strongly.
        final albumHint = query.title?.toLowerCase() ?? '';
        final folder = list.first.folderName.toLowerCase();
        if (albumHint.isEmpty || !folder.contains(albumHint)) continue;
      }

      var score = 0;
      for (final f in list) {
        score += scoreFile(f, query, filters);
      }
      // Prefer folders with more tracks (popular / complete albums).
      score += list.length * 150;
      if (list.any((f) => f.hasFreeSlot)) score += 2000;

      final first = list.first;
      folders.add(
        SoulseekAlbumFolder(
          username: first.username,
          folderPath: first.folderPath,
          folderName: first.folderName,
          files: List.unmodifiable(list),
          score: score,
        ),
      );
    }

    folders.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.trackCount.compareTo(a.trackCount);
    });
    return folders;
  }
}
