/// One release candidate from an indexer, as returned by the
/// Radarr/Sonarr interactive search (/api/v3/release).
class Release {
  final String guid;
  final int indexerId;
  final String title;
  final String indexer;
  final String quality;
  final int sizeBytes;
  final int ageDays;
  final int? seeders;
  final int? leechers;
  final String protocol; // "torrent" or "usenet"
  final bool rejected;
  final List<String> rejections;
  final bool fullSeason;

  const Release({
    required this.guid,
    required this.indexerId,
    required this.title,
    required this.indexer,
    required this.quality,
    required this.sizeBytes,
    required this.ageDays,
    required this.seeders,
    required this.leechers,
    required this.protocol,
    required this.rejected,
    required this.rejections,
    required this.fullSeason,
  });

  bool get isTorrent => protocol == 'torrent';

  String get sizeLabel {
    final gb = sizeBytes / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  String get ageLabel {
    if (ageDays >= 365) return '${(ageDays / 365).toStringAsFixed(1)}y';
    return '${ageDays}d';
  }

  factory Release.fromJson(Map<String, dynamic> json) {
    final quality =
        (json['quality']?['quality']?['name'] as String?) ?? 'Unknown';
    return Release(
      guid: json['guid'] as String? ?? '',
      indexerId: json['indexerId'] as int? ?? 0,
      title: json['title'] as String? ?? 'Unknown release',
      indexer: json['indexer'] as String? ?? 'Unknown indexer',
      quality: quality,
      sizeBytes: json['size'] as int? ?? 0,
      ageDays: json['age'] as int? ?? 0,
      seeders: json['seeders'] as int?,
      leechers: json['leechers'] as int?,
      protocol: json['protocol'] as String? ?? '',
      rejected: json['rejected'] as bool? ?? false,
      rejections: (json['rejections'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      fullSeason: json['fullSeason'] as bool? ?? false,
    );
  }
}
