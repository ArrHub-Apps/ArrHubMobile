/// Display status of a library item, in priority order.
enum MediaStatus { downloading, downloaded, wanted, unmonitored }

/// A movie (Radarr) or series (Sonarr), unified so the library and
/// add-search UIs can be shared between the two services.
class MediaItem {
  final int? id; // library id; null for lookup results not yet added
  final String title;
  final int? year;
  final String overview;
  final String? posterUrl;
  final String? fanartUrl; // wide backdrop art, for detail-sheet headers
  final int externalId; // tmdbId for movies, tvdbId for series
  final bool monitored;
  final bool downloaded;
  final String status;
  final Map<String, dynamic> raw;

  const MediaItem({
    required this.id,
    required this.title,
    required this.year,
    required this.overview,
    required this.posterUrl,
    this.fanartUrl,
    required this.externalId,
    required this.monitored,
    required this.downloaded,
    required this.status,
    required this.raw,
  });

  bool get inLibrary => id != null && id != 0;

  /// Bytes on disk (movie: sizeOnDisk; series: statistics.sizeOnDisk).
  int get sizeOnDisk {
    final direct = raw['sizeOnDisk'];
    if (direct is num) return direct.toInt();
    final stats = raw['statistics'];
    final nested = stats is Map ? stats['sizeOnDisk'] : null;
    return nested is num ? nested.toInt() : 0;
  }

  String get sizeLabel {
    final gb = sizeOnDisk / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
    return '${(sizeOnDisk / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  DateTime? get added {
    final raw = this.raw['added'] as String?;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Community rating (TMDB/IMDb for movies, TVDB-style for series).
  double get rating {
    final ratings = raw['ratings'];
    if (ratings is! Map) return 0;
    final direct = ratings['value']; // Sonarr shape
    if (direct is num) return direct.toDouble();
    for (final source in ['tmdb', 'imdb']) {
      final value = (ratings[source] as Map?)?['value']; // Radarr shape
      if (value is num && value > 0) return value.toDouble();
    }
    return 0;
  }

  /// Library items get the server's cached artwork; lookup results aren't
  /// cached server-side yet, so those use the remote (TMDB/TVDB) URL.
  ///
  /// The bare /MediaCover/... path in images[].url is behind Forms auth and
  /// ignores the apikey param, returning the login page — the API's
  /// /api/v3/mediacover/... route honors ?apikey=, so rewrite to that.
  static String? _image(Map<String, dynamic> json, String baseUrl,
      String apiKey, String coverType) {
    final images = json['images'] as List<dynamic>?;
    if (images == null) return null;
    final inLibrary = (json['id'] as int? ?? 0) != 0;
    String? remote;
    String? local;
    for (final img in images) {
      if (img is Map && img['coverType'] == coverType) {
        final r = img['remoteUrl'] as String?;
        if (r != null && r.isNotEmpty) remote ??= r;
        final l = img['url'] as String?;
        if (l != null && l.isNotEmpty) local ??= l;
      }
    }
    if (inLibrary && local != null) {
      final apiPath =
          local.replaceFirst('/MediaCover/', '/api/v3/mediacover/');
      final sep = apiPath.contains('?') ? '&' : '?';
      return '$baseUrl$apiPath${sep}apikey=$apiKey';
    }
    return remote;
  }

  factory MediaItem.movie(
      Map<String, dynamic> json, String baseUrl, String apiKey) {
    return MediaItem(
      id: json['id'] as int?,
      title: json['title'] as String? ?? 'Unknown',
      year: json['year'] as int?,
      overview: json['overview'] as String? ?? '',
      posterUrl: _image(json, baseUrl, apiKey, 'poster'),
      fanartUrl: _image(json, baseUrl, apiKey, 'fanart'),
      externalId: json['tmdbId'] as int? ?? 0,
      monitored: json['monitored'] as bool? ?? false,
      downloaded: json['hasFile'] as bool? ?? false,
      status: json['status'] as String? ?? '',
      raw: json,
    );
  }

  factory MediaItem.series(
      Map<String, dynamic> json, String baseUrl, String apiKey) {
    final stats = json['statistics'] as Map<String, dynamic>?;
    final fileCount = stats?['episodeFileCount'] as int? ?? 0;
    return MediaItem(
      id: json['id'] as int?,
      title: json['title'] as String? ?? 'Unknown',
      year: json['year'] as int?,
      overview: json['overview'] as String? ?? '',
      posterUrl: _image(json, baseUrl, apiKey, 'poster'),
      fanartUrl: _image(json, baseUrl, apiKey, 'fanart'),
      externalId: json['tvdbId'] as int? ?? 0,
      monitored: json['monitored'] as bool? ?? false,
      downloaded: fileCount > 0,
      status: json['status'] as String? ?? '',
      raw: json,
    );
  }
}

class QualityProfile {
  final int id;
  final String name;
  const QualityProfile({required this.id, required this.name});

  factory QualityProfile.fromJson(Map<String, dynamic> json) =>
      QualityProfile(id: json['id'] as int, name: json['name'] as String);
}

class Language {
  final int id;
  final String name;
  const Language({required this.id, required this.name});

  factory Language.fromJson(Map<String, dynamic> json) =>
      Language(id: json['id'] as int, name: json['name'] as String);
}

class RootFolder {
  final String path;
  const RootFolder({required this.path});

  factory RootFolder.fromJson(Map<String, dynamic> json) =>
      RootFolder(path: json['path'] as String);
}

class DiskSpace {
  final String path;
  final String label;
  final int freeSpace;
  final int totalSpace;

  const DiskSpace({
    required this.path,
    required this.label,
    required this.freeSpace,
    required this.totalSpace,
  });

  double get usedFraction =>
      totalSpace == 0 ? 0 : (totalSpace - freeSpace) / totalSpace;

  static String _bytes(int b) {
    final tb = b / (1024 * 1024 * 1024 * 1024);
    if (tb >= 1) return '${tb.toStringAsFixed(1)} TB';
    final gb = b / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(0)} GB';
  }

  String get freeLabel => _bytes(freeSpace);
  String get totalLabel => _bytes(totalSpace);

  factory DiskSpace.fromJson(Map<String, dynamic> json) => DiskSpace(
        path: json['path'] as String? ?? '',
        label: json['label'] as String? ?? '',
        freeSpace: json['freeSpace'] as int? ?? 0,
        totalSpace: json['totalSpace'] as int? ?? 0,
      );
}
