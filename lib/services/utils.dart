import 'nav_parser.dart';

int getDatestamp() {
  final DateTime now = DateTime.now();
  final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration difference = now.difference(epoch);
  final int days = difference.inDays;
  return days;
}

/// Seconds in a "h:mm:ss" / "m:ss" / "ss" duration, or null when [duration]
/// is missing or not of that shape (more than three parts, non-digits).
int? parseDuration(String? duration) {
  if (duration == null) {
    return null;
  }
  // Seconds, minutes, hours — read from the right (ytmusicapi's rule).
  const increments = [1, 60, 3600];
  final times = duration.trim().split(":").reversed.toList();
  if (times.length > increments.length) return null;
  int seconds = 0;
  for (var i = 0; i < times.length; i++) {
    final part = int.tryParse(times[i].trim());
    if (part == null) return null;
    seconds += increments[i] * part;
  }
  return seconds;
}

String validatePlaylistId(String playlistId) {
  return playlistId.startsWith('VL') ? playlistId.substring(2) : playlistId;
}

String? getItemText(Map<String, dynamic> item, int index,
    {int runIndex = 0, bool noneIfAbsent = false}) {
  // getFlexColumnItem never returns null: a missing column is an empty map,
  // and indexing into that used to throw and drop the whole page.
  final column = getFlexColumnItem(item, index);
  final runs = nav(column, ['text', 'runs']);
  if (runs is! List || runs.length <= runIndex) {
    return noneIfAbsent ? null : "";
  }
  final text = nav(runs, [runIndex, 'text']);
  return text is String ? text : (noneIfAbsent ? null : "");
}

/// Text of a list row's first fixed column (the duration), whether YouTube
/// sends it as `simpleText` or as `runs`; null when there is none.
String? getFixedColumnText(Map<String, dynamic> item) {
  final text = nav(item, [
    'fixedColumns',
    0,
    'musicResponsiveListItemFixedColumnRenderer',
    'text'
  ]);
  if (text is! Map) return null;
  final value = text['simpleText'] ?? nav(text, ['runs', 0, 'text']);
  return value is String ? value : null;
}

final _expireParam = RegExp(".expire=([0-9]+)?&");

///Check if Steam Url or given epoch is expired
bool isExpired({String? url, int? epoch}) {
  if (url != null) {
    final match = _expireParam.firstMatch(url);
    if (match != null) {
      // "expire=&" (no digits) counts as expired instead of throwing.
      epoch = int.tryParse(match[1] ?? '');
    }
  }

  if (epoch != null &&
      DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1800 < epoch) {
    return false;
  }
  return true;
}

/// The first map in [objectList] holding [key] (or that value, with
/// [isKey]). Tolerates a missing list and non-map entries.
dynamic findObjectByKey(dynamic objectList, dynamic key,
    {String? nested, bool isKey = false}) {
  if (objectList is! List) return null;
  for (var item in objectList) {
    if (nested != null && item is Map) {
      item = item[nested];
    }
    if (item is Map && item.containsKey(key)) {
      return isKey ? item[key] : item;
    }
  }
  return null;
}

String? getSearchParams(String? filter, String? scope, bool ignoreSpelling) {
  // Matches ytmusicapi: base "EgWKAQ" + two-char type codes (II, IQ, JQ, …)
  const filteredParam1 = 'EgWKAQ';
  String? params;
  String? param1;
  String? param2;
  String? param3;

  if (filter == null && scope == null && !ignoreSpelling) {
    return params;
  }

  if (scope == 'uploads') {
    params = 'agIYAw%3D%3D';
  }

  if (scope == 'library') {
    if (filter != null) {
      param1 = filteredParam1;
      param2 = _getParam2(filter);
      param3 = 'AWoKEAUQCRADEAoYBA%3D%3D';
    } else {
      params = 'agIYBA%3D%3D';
    }
  }

  if (scope == null && filter != null) {
    if (filter == 'playlists') {
      params = 'Eg-KAQwIABAAGAAgACgB';
      if (!ignoreSpelling) {
        params += 'MABqChAEEAMQCRAFEAo%3D';
      } else {
        params += 'MABCAggBagoQBBADEAkQBRAK';
      }
    } else if (filter.contains('playlists')) {
      param1 = 'EgeKAQQoA';
      if (filter == 'featured_playlists') {
        param2 = 'Dg';
      } else {
        param2 = 'EA';
      }
      if (!ignoreSpelling) {
        param3 = 'BagwQDhAKEAMQBBAJEAU%3D';
      } else {
        param3 = 'BQgIIAWoMEA4QChADEAQQCRAF';
      }
    } else {
      param1 = filteredParam1;
      param2 = _getParam2(filter);
      if (!ignoreSpelling) {
        param3 = 'AWoMEA4QChADEAQQCRAF';
      } else {
        param3 = 'AUICCAFqDBAOEAoQAxAEEAkQBQ%3D%3D';
      }
    }
  }

  if (scope == null && filter == null && ignoreSpelling) {
    params = 'EhGKAQ4IARABGAEgASgAOAFAAUICCAE%3D';
  }

  return params ?? (param1! + param2! + param3!);
}

String? _getParam2(String filter) {
  final filterParams = {
    'songs': 'II',
    'videos': 'IQ',
    'albums': 'IY',
    'artists': 'Ig',
    'playlists': 'Io',
    'profiles': 'JY',
    'podcasts': 'JQ',
    'episodes': 'JI',
  };
  return filterParams[filter];
}

/// Index of the first " • " separator run, or `runs.length` when there is
/// none (ytmusicapi's rule) — never -1, which made `sublist` throw.
int getDotSeparatorIndex(List<dynamic> runs) {
  final i =
      runs.indexWhere((e) => e is Map && e.length == 1 && e['text'] == ' • ');
  return i < 0 ? runs.length : i;
}
