/// Android Auto browsing: keep every list Android Auto asks for small enough
/// for the binder transaction that carries it (the same idea as the 120-item
/// window for podcast queues, `prepareLongFormQueue`).
///
/// Android Auto may pass the Media Browser paging extras with `getChildren`;
/// then we return just that page. When it doesn't, a long list comes back
/// as browsable sections ("1–100", "101–200", …) instead of all at once.
library;

/// `MediaBrowserCompat.EXTRA_PAGE` / `EXTRA_PAGE_SIZE`.
const autoPageKey = 'android.media.browse.extra.PAGE';
const autoPageSizeKey = 'android.media.browse.extra.PAGE_SIZE';

/// Largest page we hand out, whatever size is asked for.
const autoMaxPageSize = 100;

/// Lists up to this long are sent whole when no page is asked for.
const autoMaxUnpaged = 120;

/// Items per section when a long list is split into sections.
const autoSectionSize = 100;

/// Show notes and other long text extras are cut to this many characters.
const autoTextMax = 300;

/// Section node ids: `aa_section:<start>:<parentId>`.
const autoSectionPrefix = 'aa_section:';

int? _int(Object? v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

/// What to return for a list of [total] items.
sealed class AutoBrowsePlan {
  const AutoBrowsePlan();
}

/// Return items [start] (inclusive) to [end] (exclusive).
class AutoRange extends AutoBrowsePlan {
  const AutoRange(this.start, this.end);
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is AutoRange && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(start, end);
  @override
  String toString() => 'AutoRange($start, $end)';
}

/// Return section nodes, each starting at one of [starts].
class AutoSections extends AutoBrowsePlan {
  const AutoSections(this.starts, this.total);
  final List<int> starts;
  final int total;
}

/// Decide how to answer a `getChildren` for a list of [total] items, given
/// Android Auto's [options].
AutoBrowsePlan planAutoBrowse(int total, Map<String, dynamic>? options) {
  final page = _int(options?[autoPageKey]);
  final size = _int(options?[autoPageSizeKey]);
  if (page != null && size != null && page >= 0 && size > 0) {
    final s = size.clamp(1, autoMaxPageSize);
    final start = (page * s).clamp(0, total);
    return AutoRange(start, (start + s).clamp(0, total));
  }
  if (total <= autoMaxUnpaged) return AutoRange(0, total);
  return AutoSections(
      [for (var i = 0; i < total; i += autoSectionSize) i], total);
}

/// `aa_section:200:LIBFAV` for the section starting at 200 of LIBFAV.
String autoSectionId(String parentId, int start) =>
    '$autoSectionPrefix$start:$parentId';

/// The parent list and start of a section id, or null.
({String parentId, int start})? parseAutoSectionId(String id) {
  if (!id.startsWith(autoSectionPrefix)) return null;
  final rest = id.substring(autoSectionPrefix.length);
  final colon = rest.indexOf(':');
  if (colon <= 0) return null;
  final start = int.tryParse(rest.substring(0, colon));
  final parent = rest.substring(colon + 1);
  if (start == null || start < 0 || parent.isEmpty) return null;
  return (parentId: parent, start: start);
}

/// "1–100" for the section starting at 0 of a list of [total].
String autoSectionLabel(int start, int total) {
  final end = (start + autoSectionSize).clamp(0, total);
  return '${start + 1}–$end';
}

/// Extras small enough for the car: long strings cut to [autoTextMax],
/// nested lists / maps (artists, album objects) dropped.
Map<String, dynamic> slimAutoExtras(Map<String, dynamic>? extras) {
  if (extras == null) return const {};
  final out = <String, dynamic>{};
  extras.forEach((k, v) {
    if (v is String) {
      out[k] = v.length > autoTextMax ? '${v.substring(0, autoTextMax)}…' : v;
    } else if (v is num || v is bool) {
      out[k] = v;
    }
  });
  return out;
}
