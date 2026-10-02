/// One of the chips YouTube Music shows over its home feed ("Relax",
/// "Workout", "Energize", …). Selecting it reloads the home feed with
/// [params]; deselecting goes back to the plain feed.
class HomeChip {
  const HomeChip({required this.title, required this.params, this.browseId});

  final String title;
  final String params;
  final String? browseId;

  factory HomeChip.fromJson(Map<dynamic, dynamic> json) => HomeChip(
        title: '${json['title']}',
        params: '${json['params']}',
        browseId: json['browseId'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'title': title, 'params': params, 'browseId': browseId};

  @override
  bool operator ==(Object other) =>
      other is HomeChip && other.params == params && other.title == title;

  @override
  int get hashCode => Object.hash(title, params);
}

/// Chips from a home `sectionListRenderer`'s header. Chips without a title
/// or browse params (YouTube occasionally adds pure UI toggles) are skipped,
/// and so are the Podcasts / Uploads chips, which lead outside music.
List<HomeChip> parseHomeChips(dynamic sectionList) {
  if (sectionList is! Map) return const [];
  final chips = (((sectionList['header'] as Map?)?['chipCloudRenderer']
          as Map?)?['chips'] as List?) ??
      const [];
  final out = <HomeChip>[];
  for (final c in chips) {
    final r = (c is Map) ? c['chipCloudChipRenderer'] as Map? : null;
    if (r == null) continue;
    final runs = ((r['text'] as Map?)?['runs'] as List?) ?? const [];
    final title =
        runs.isEmpty ? '' : '${(runs.first as Map?)?['text'] ?? ''}'.trim();
    final browse =
        (r['navigationEndpoint'] as Map?)?['browseEndpoint'] as Map?;
    final params = browse?['params'] as String?;
    if (title.isEmpty || params == null || params.isEmpty) continue;
    final lower = title.toLowerCase();
    if (lower == 'podcasts' || lower == 'uploaded' || lower == 'uploads') {
      continue;
    }
    out.add(HomeChip(
        title: title,
        params: params,
        browseId: browse?['browseId'] as String?));
  }
  return out;
}
