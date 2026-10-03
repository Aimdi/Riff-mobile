/// The merge rules of the Riff sync format (docs/sync-format.md): records,
/// tombstones, last writer wins, and how local changes since the last sync
/// are found. Pure Dart, no I/O, so every rule is unit-tested.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

const syncFormatName = 'riff-sync';

/// Major version of docs/sync-format.md this app reads and writes.
const syncFormatVersion = 1;

/// Tombstones older than this are dropped when a file is written.
const syncTombstoneTtl = Duration(days: 180);

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

/// One version of a record: live (with [data]) or a tombstone.
class SyncRecord {
  const SyncRecord({
    required this.updatedAt,
    required this.device,
    this.deleted = false,
    this.data,
    this.extra = const {},
  });

  const SyncRecord.tombstone(
      {required this.updatedAt, required this.device, this.extra = const {}})
      : deleted = true,
        data = null;

  final int updatedAt;
  final String device;
  final bool deleted;
  final Map<String, dynamic>? data;

  /// Fields of the record this app doesn't know, kept as they were.
  final Map<String, dynamic> extra;

  static const _known = {'updatedAt', 'device', 'deleted', 'data'};

  Map<String, dynamic> toJson() => {
        ...extra,
        'updatedAt': updatedAt,
        'device': device,
        if (deleted) 'deleted': true,
        if (!deleted && data != null) 'data': data,
      };

  /// Null for anything that isn't a record.
  static SyncRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final deleted = j['deleted'] == true;
    final data = j['data'];
    if (!deleted && data is! Map) return null;
    return SyncRecord(
      updatedAt: _int(j['updatedAt']),
      device: '${j['device'] ?? ''}',
      deleted: deleted,
      data: deleted ? null : Map<String, dynamic>.from(data as Map),
      extra: {
        for (final e in j.entries)
          if (!_known.contains(e.key)) '${e.key}': e.value
      },
    );
  }

  /// Same time, writer and kind: the same write.
  bool sameVersion(SyncRecord o) =>
      updatedAt == o.updatedAt && device == o.device && deleted == o.deleted;

  /// Same version: same time, writer, kind and content.
  bool sameAs(SyncRecord o) =>
      updatedAt == o.updatedAt &&
      device == o.device &&
      deleted == o.deleted &&
      canonicalJson(data) == canonicalJson(o.data);

  @override
  String toString() =>
      'SyncRecord($updatedAt $device${deleted ? ' deleted' : ''})';
}

/// > 0 when [a] wins over [b], < 0 when [b] wins, 0 for the same write.
int compareRecords(SyncRecord a, SyncRecord b) {
  if (a.updatedAt != b.updatedAt) return a.updatedAt.compareTo(b.updatedAt);
  if (a.deleted != b.deleted) return a.deleted ? 1 : -1;
  return a.device.compareTo(b.device);
}

/// JSON with object keys sorted at every level, for comparing and hashing.
String canonicalJson(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _sorted(v[k])};
  }
  if (v is List) return [for (final x in v) _sorted(x)];
  return v;
}

/// Short content hash of a record's data.
String dataHash(Map<String, dynamic>? data) =>
    sha1.convert(utf8.encode(canonicalJson(data))).toString();

bool tombstoneExpired(SyncRecord r, int nowMs) =>
    r.deleted && nowMs - r.updatedAt > syncTombstoneTtl.inMilliseconds;

/// What merging local and remote records gives.
class SyncMerge {
  const SyncMerge(
      {required this.merged,
      required this.winners,
      required this.remoteChanged});

  /// What goes into the file (expired tombstones dropped).
  final Map<String, SyncRecord> merged;

  /// The winner for every id, expired tombstones included: what the app
  /// should hold now.
  final Map<String, SyncRecord> winners;

  /// The file needs writing.
  final bool remoteChanged;

  /// Ids where the app's data must change to [winners]. Compared by
  /// version only: the app's copy of a version can differ in fields it
  /// doesn't keep, and rewriting it each sync would be wasted work.
  Set<String> localChanges(Map<String, SyncRecord> local) {
    final out = <String>{};
    winners.forEach((id, w) {
      final l = local[id];
      if (l == null ? !w.deleted : !l.sameVersion(w)) out.add(id);
    });
    return out;
  }
}

/// Merge two sides record by record (last writer wins). On the same write
/// the remote copy is kept, so fields this app doesn't know survive.
SyncMerge mergeRecords(
    Map<String, SyncRecord> local, Map<String, SyncRecord> remote,
    {required int nowMs}) {
  final winners = <String, SyncRecord>{};
  for (final id in {...local.keys, ...remote.keys}) {
    final l = local[id], r = remote[id];
    if (l == null) {
      winners[id] = r!;
    } else if (r == null) {
      winners[id] = l;
    } else {
      winners[id] = compareRecords(l, r) > 0 ? l : r;
    }
  }
  final merged = <String, SyncRecord>{
    for (final e in winners.entries)
      if (!tombstoneExpired(e.value, nowMs)) e.key: e.value
  };
  var changed = merged.length != remote.length;
  if (!changed) {
    for (final e in merged.entries) {
      final r = remote[e.key];
      if (r == null || !identical(r, e.value) && !r.sameAs(e.value)) {
        changed = true;
        break;
      }
    }
  }
  return SyncMerge(merged: merged, winners: winners, remoteChanged: changed);
}

// ── What changed locally since the last sync ──────────────────────────

/// What this device wrote or applied for a record at the last sync.
class LedgerEntry {
  const LedgerEntry(
      {required this.updatedAt,
      required this.device,
      this.hash = '',
      this.deleted = false});

  final int updatedAt;
  final String device;

  /// [dataHash] of the app's own data for the record after that sync.
  final String hash;
  final bool deleted;

  Map<String, dynamic> toJson() => {
        't': updatedAt,
        'v': device,
        if (hash.isNotEmpty) 'h': hash,
        if (deleted) 'd': true,
      };

  static LedgerEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    return LedgerEntry(
      updatedAt: _int(j['t']),
      device: '${j['v'] ?? ''}',
      hash: '${j['h'] ?? ''}',
      deleted: j['d'] == true,
    );
  }
}

/// A record as the app holds it right now.
class LocalItem {
  const LocalItem(this.data, {this.editedAt});
  final Map<String, dynamic> data;

  /// When it was last changed, when the app knows.
  final int? editedAt;
}

/// Turn the app's current data into records, using the ledger of the last
/// sync to tell what changed since:
/// - unchanged since the last sync: the version from the ledger;
/// - changed or new: stamped with its edit time (or [nowMs] when unknown;
///   `0` when this collection was never synced), always later than the
///   ledger's version;
/// - gone since the last sync: a tombstone at [nowMs].
Map<String, SyncRecord> localRecords({
  required Map<String, LocalItem> items,
  required Map<String, LedgerEntry> ledger,
  required String device,
  required int nowMs,
}) {
  final neverSynced = ledger.isEmpty;
  final out = <String, SyncRecord>{};
  items.forEach((id, item) {
    final l = ledger[id];
    final h = dataHash(item.data);
    if (l != null && !l.deleted && l.hash == h) {
      out[id] =
          SyncRecord(updatedAt: l.updatedAt, device: l.device, data: item.data);
      return;
    }
    var t = item.editedAt ?? (neverSynced ? 0 : nowMs);
    if (l != null && t <= l.updatedAt) t = l.updatedAt + 1;
    out[id] = SyncRecord(updatedAt: t, device: device, data: item.data);
  });
  ledger.forEach((id, l) {
    if (items.containsKey(id)) return;
    out[id] = l.deleted
        ? SyncRecord.tombstone(updatedAt: l.updatedAt, device: l.device)
        : SyncRecord.tombstone(
            updatedAt: nowMs > l.updatedAt ? nowMs : l.updatedAt + 1,
            device: device);
  });
  return out;
}

/// The ledger after a sync: each winner's version, with the hash of what
/// the app now holds for it ([held], after applying). Records the app
/// couldn't take in are left out, so the next sync tries again.
Map<String, LedgerEntry> nextLedger(
    Map<String, SyncRecord> winners, Map<String, LocalItem> held,
    {required int nowMs}) {
  final out = <String, LedgerEntry>{};
  winners.forEach((id, w) {
    if (w.deleted) {
      if (held.containsKey(id)) return;
      if (tombstoneExpired(w, nowMs)) return;
      out[id] =
          LedgerEntry(updatedAt: w.updatedAt, device: w.device, deleted: true);
      return;
    }
    final item = held[id];
    if (item == null) return;
    out[id] = LedgerEntry(
        updatedAt: w.updatedAt, device: w.device, hash: dataHash(item.data));
  });
  return out;
}

// ── Collection files ──────────────────────────────────────────────────

/// A JSON collection file: its records and the top-level fields this app
/// doesn't know.
class SyncFile {
  const SyncFile(
      {required this.collection,
      required this.records,
      this.version = syncFormatVersion,
      this.extra = const {}});

  final String collection;
  final int version;
  final Map<String, SyncRecord> records;
  final Map<String, dynamic> extra;

  static const _known = {'format', 'version', 'collection', 'records'};

  String encode() => const JsonEncoder.withIndent(' ').convert({
        ...extra,
        'format': syncFormatName,
        'version': syncFormatVersion,
        'collection': collection,
        'records': {
          for (final id in records.keys.toList()..sort())
            id: records[id]!.toJson()
        },
      });

  /// Parse [text]; throws [FormatException] when it isn't a collection
  /// file (the file is then left alone).
  static SyncFile decode(String text, {required String collection}) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      throw const FormatException('Not JSON');
    }
    if (j is! Map || j['format'] != syncFormatName) {
      throw const FormatException('Not a riff-sync file');
    }
    final records = j['records'];
    if (records is! Map) throw const FormatException('No records');
    final out = <String, SyncRecord>{};
    records.forEach((k, v) {
      final r = SyncRecord.fromJson(v);
      if (r != null) out['$k'] = r;
    });
    return SyncFile(
      collection: '${j['collection'] ?? collection}',
      version: _int(j['version']),
      records: out,
      extra: {
        for (final e in j.entries)
          if (!_known.contains(e.key)) '${e.key}': e.value
      },
    );
  }
}

/// Whether this app may write files of [version].
bool syncVersionSupported(int version) => version <= syncFormatVersion;
